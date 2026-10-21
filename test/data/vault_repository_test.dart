import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/crypto/kdf.dart';
import 'package:offline2fa/core/models/otp_entry.dart';
import 'package:offline2fa/core/models/otp_type.dart';
import 'package:offline2fa/core/vault/vault_codec.dart';
import 'package:offline2fa/core/vault/vault_errors.dart';
import 'package:offline2fa/core/vault/vault_payload.dart';
import 'package:offline2fa/data/vault_repository.dart';
import 'package:offline2fa/data/vault_storage.dart';

class FakeVaultStorage implements VaultStorage {
  Uint8List? _main;
  Uint8List? _bak;

  @override
  Future<bool> exists() async => _main != null;

  @override
  Future<bool> backupExists() async => _bak != null;

  @override
  Future<Uint8List> read() async {
    if (_main == null) {
      throw const VaultFileNotFound('Main vault not found');
    }
    return Uint8List.fromList(_main!);
  }

  @override
  Future<Uint8List> readBackup() async {
    if (_bak == null) {
      throw const VaultFileNotFound('Backup vault not found');
    }
    return Uint8List.fromList(_bak!);
  }

  @override
  Future<void> writeAtomic(Uint8List bytes) async {
    if (_main != null) {
      _bak = Uint8List.fromList(_main!);
    }
    _main = Uint8List.fromList(bytes);
  }

  @override
  Future<void> restoreBackup() async {
    if (_bak == null) {
      throw const VaultFileNotFound('No backup available');
    }
    _main = Uint8List.fromList(_bak!);
  }

  @override
  Future<void> delete() async {
    _main = null;
    _bak = null;
  }
}

void main() {
  group('VaultRepository', () {
    late FakeVaultStorage storage;
    late VaultRepository repo;

    setUp(() {
      storage = FakeVaultStorage();
      repo = VaultRepository(
        storage: storage,
        defaultKdfParams: KdfParams.testFast,
      );
    });

    test('initial state is locked and empty', () async {
      expect(repo.isUnlocked, isFalse);
      expect(repo.derivedKey, isNull);
      expect(repo.salt, isNull);
      expect(await repo.hasVault(), isFalse);
      expect(await repo.hasBackup(), isFalse);
    });

    test(
      'createVault creates empty vault and establishes unlocked session',
      () async {
        final payload = await repo.createVault('password123');

        expect(payload.entries, isEmpty);
        expect(payload.groups, isEmpty);
        expect(repo.isUnlocked, isTrue);
        expect(repo.derivedKey?.length, equals(32));
        expect(repo.salt?.length, equals(16));
        expect(await repo.hasVault(), isTrue);
        expect(await repo.hasBackup(), isFalse);
      },
    );

    test('lock zeroes derived key buffer and clears session', () async {
      await repo.createVault('password123');
      final originalKeyRef = repo.derivedKey!;
      expect(originalKeyRef.any((b) => b != 0), isTrue);

      repo.lock();

      expect(repo.isUnlocked, isFalse);
      expect(repo.derivedKey, isNull);
      expect(repo.salt, isNull);
      expect(repo.kdfParams, isNull);
      // Key memory buffer is wiped to 0s
      expect(originalKeyRef.every((b) => b == 0), isTrue);
    });

    test('unlock decrypts vault and restores unlocked session', () async {
      await repo.createVault('my-secret-pass');
      repo.lock();
      expect(repo.isUnlocked, isFalse);

      final payload = await repo.unlock('my-secret-pass');
      expect(payload.entries, isEmpty);
      expect(repo.isUnlocked, isTrue);
      expect(repo.derivedKey?.length, equals(32));
      expect(repo.salt?.length, equals(16));
    });

    test(
      'unlock with wrong password throws WrongPasswordOrCorrupted',
      () async {
        await repo.createVault('correct-password');
        repo.lock();

        expect(
          () => repo.unlock('wrong-password'),
          throwsA(isA<WrongPasswordOrCorrupted>()),
        );
        expect(repo.isUnlocked, isFalse);
      },
    );

    test('save persists updated payload when unlocked', () async {
      await repo.createVault('pass');

      final entry = OtpEntry(
        id: 'e1',
        type: OtpType.totp,
        issuer: 'Service',
        account: 'user',
        secret: 'JBSWY3DPEHPK3PXP',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      final updated = (await repo.unlock('pass')).copyWith(entries: [entry]);

      await repo.save(updated);

      repo.lock();
      final reloaded = await repo.unlock('pass');
      expect(reloaded.entries.length, equals(1));
      expect(reloaded.entries.first.id, equals('e1'));
    });

    test('save throws StateError when locked', () async {
      final payload = VaultPayload.empty();
      expect(() => repo.save(payload), throwsStateError);
    });

    test(
      'verifyPassword returns true for correct pass and false for incorrect',
      () async {
        await repo.createVault('verify-test-pass');

        expect(await repo.verifyPassword('verify-test-pass'), isTrue);
        expect(await repo.verifyPassword('wrong-pass'), isFalse);

        repo.lock();
        expect(() => repo.verifyPassword('any'), throwsStateError);
      },
    );

    test(
      'changePassword updates password, regenerates salt, zeroes old key',
      () async {
        final initialPayload = await repo.createVault('initial-pass');
        final oldSalt = Uint8List.fromList(repo.salt!);
        final oldKeyRef = repo.derivedKey!;

        // Attempt with wrong old password fails
        expect(
          () => repo.changePassword('wrong-old', 'new-pass', initialPayload),
          throwsA(isA<WrongPasswordOrCorrupted>()),
        );

        // Change to new password
        await repo.changePassword('initial-pass', 'new-pass', initialPayload);

        expect(repo.isUnlocked, isTrue);
        expect(repo.salt, isNot(equals(oldSalt)));
        expect(oldKeyRef.every((b) => b == 0), isTrue);

        // Lock and verify old password no longer works, but new password works
        repo.lock();
        expect(
          () => repo.unlock('initial-pass'),
          throwsA(isA<WrongPasswordOrCorrupted>()),
        );

        final unlockedPayload = await repo.unlock('new-pass');
        expect(unlockedPayload.schemaVersion, equals(1));
      },
    );

    test(
      'exportBytes returns encrypted bytes decryptable with master password',
      () async {
        final payload = await repo.createVault('export-pass');
        final exportedBytes = await repo.exportBytes(payload);

        expect(exportedBytes.length, greaterThan(47));

        final decrypted = await VaultCodec.decryptWithPassword(
          bytes: exportedBytes,
          password: 'export-pass',
        );
        expect(decrypted.payload.schemaVersion, equals(payload.schemaVersion));
      },
    );

    test('importAndMerge combines payloads and writes to storage', () async {
      final localPayload = await repo.createVault('master-pass');

      // Create an external vault with another password
      final extEntry = OtpEntry(
        id: 'external-id',
        type: OtpType.totp,
        issuer: 'ImportedIssuer',
        account: 'user@test.com',
        secret: 'JBSWY3DPEHPK3PXP',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      final extPayload = VaultPayload.empty().copyWith(entries: [extEntry]);
      final extEncrypt = await VaultCodec.encryptWithPassword(
        payload: extPayload,
        password: 'external-password',
        kdfParams: KdfParams.testFast,
      );

      final mergeResult = await repo.importAndMerge(
        extEncrypt.bytes,
        'external-password',
        localPayload,
      );

      expect(mergeResult.report.added, equals(1));
      expect(mergeResult.merged.entries.length, equals(1));
      expect(mergeResult.merged.entries.first.issuer, equals('ImportedIssuer'));

      // Verify that local disk storage has the merged entry encrypted under master-pass
      repo.lock();
      final reloaded = await repo.unlock('master-pass');
      expect(reloaded.entries.length, equals(1));
      expect(reloaded.entries.first.issuer, equals('ImportedIssuer'));
    });

    test(
      'importAsNewVault replaces vault with external file and password',
      () async {
        final entry = OtpEntry(
          id: 'onboard-1',
          type: OtpType.totp,
          issuer: 'OnboardingService',
          account: 'admin',
          secret: 'JBSWY3DPEHPK3PXP',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );
        final extPayload = VaultPayload.empty().copyWith(entries: [entry]);
        final extBytes = (await VaultCodec.encryptWithPassword(
          payload: extPayload,
          password: 'imported-file-pass',
          kdfParams: KdfParams.testFast,
        )).bytes;

        final result = await repo.importAsNewVault(
          extBytes,
          'imported-file-pass',
        );

        expect(result.entries.length, equals(1));
        expect(result.entries.first.issuer, equals('OnboardingService'));
        expect(repo.isUnlocked, isTrue);

        // Verify unlocking persisted file works with imported-file-pass
        repo.lock();
        final fromStorage = await repo.unlock('imported-file-pass');
        expect(fromStorage.entries.length, equals(1));
      },
    );

    test('restoreFromBackup restores .bak after password validation', () async {
      final initial = await repo.createVault('vault-pass');
      final entry = OtpEntry(
        id: 'e1',
        type: OtpType.totp,
        issuer: 'First',
        account: 'u1',
        secret: 'JBSWY3DPEHPK3PXP',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      // First save creates .bak of initial empty vault
      await repo.save(initial.copyWith(entries: [entry]));
      expect(await repo.hasBackup(), isTrue);

      // Mutate current main with a 2nd entry
      final entry2 = OtpEntry(
        id: 'e2',
        type: OtpType.totp,
        issuer: 'Second',
        account: 'u2',
        secret: 'JBSWY3DPEHPK3PXP',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await repo.save(initial.copyWith(entries: [entry, entry2]));

      // Verify wrong password doesn't restore backup
      expect(
        () => repo.restoreFromBackup('wrong-pass'),
        throwsA(isA<WrongPasswordOrCorrupted>()),
      );

      // Restore with correct password
      final restored = await repo.restoreFromBackup('vault-pass');
      expect(restored.entries.length, equals(1));
      expect(restored.entries.first.issuer, equals('First'));
      expect(repo.isUnlocked, isTrue);
    });

    test('deleteVault zeroes key, locks, and deletes files', () async {
      await repo.createVault('delete-pass');
      expect(await repo.hasVault(), isTrue);

      await repo.deleteVault();

      expect(repo.isUnlocked, isFalse);
      expect(repo.derivedKey, isNull);
      expect(await repo.hasVault(), isFalse);
    });
  });
}
