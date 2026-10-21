import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/crypto/kdf.dart';
import 'package:offline2fa/core/models/otp_entry.dart';
import 'package:offline2fa/core/models/otp_type.dart';
import 'package:offline2fa/core/vault/vault_codec.dart';
import 'package:offline2fa/core/vault/vault_errors.dart';
import 'package:offline2fa/core/vault/vault_payload.dart';
import 'package:offline2fa/data/vault_controller.dart';
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
  group('VaultController & State Providers', () {
    late FakeVaultStorage storage;
    late VaultRepository repository;
    late ProviderContainer container;

    setUp(() {
      storage = FakeVaultStorage();
      repository = VaultRepository(
        storage: storage,
        defaultKdfParams: KdfParams.testFast,
      );
      container = ProviderContainer(
        overrides: [
          vaultStorageProvider.overrideWithValue(storage),
          vaultRepositoryProvider.overrideWithValue(repository),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state before initialize() is VaultInitial', () {
      final state = container.read(vaultControllerProvider);
      expect(state, equals(const VaultInitial()));
    });

    test('initialize() detects empty storage and sets VaultNoVault', () async {
      final controller = container.read(vaultControllerProvider.notifier);
      await controller.initialize();

      final state = container.read(vaultControllerProvider);
      expect(state, equals(const VaultNoVault(hasBackup: false)));
    });

    test(
      'initialize() detects backup only and sets VaultNoVault(hasBackup: true)',
      () async {
        // Setup state where only backup exists
        await repository.createVault('temp-pass');
        storage._bak = storage._main;
        storage._main = null;
        repository.lock();

        final controller = container.read(vaultControllerProvider.notifier);
        await controller.initialize();

        final state = container.read(vaultControllerProvider);
        expect(state, equals(const VaultNoVault(hasBackup: true)));
      },
    );

    test('initialize() detects existing vault and sets VaultLocked', () async {
      await repository.createVault('mypass');
      repository.lock();

      final controller = container.read(vaultControllerProvider.notifier);
      await controller.initialize();

      final state = container.read(vaultControllerProvider);
      expect(state, isA<VaultLocked>());
    });

    test('create() establishes unlocked state with empty payload', () async {
      final controller = container.read(vaultControllerProvider.notifier);
      await controller.create('secure-password');

      final state = container.read(vaultControllerProvider);
      expect(state, isA<VaultUnlocked>());
      final unlocked = state as VaultUnlocked;
      expect(unlocked.data.entries, isEmpty);
      expect(unlocked.data.groups, isEmpty);
    });

    test('lock() transitions to VaultLocked and resets credentials', () async {
      final controller = container.read(vaultControllerProvider.notifier);
      await controller.create('pass');
      expect(container.read(vaultControllerProvider), isA<VaultUnlocked>());

      await controller.lock();

      final state = container.read(vaultControllerProvider);
      expect(state, isA<VaultLocked>());
      expect(repository.isUnlocked, isFalse);
    });

    test('unlock() succeeds with correct password', () async {
      final controller = container.read(vaultControllerProvider.notifier);
      await controller.create('master-password');
      await controller.lock();

      await controller.unlock('master-password');

      final state = container.read(vaultControllerProvider);
      expect(state, isA<VaultUnlocked>());
    });

    test(
      'unlock() failure tracks failedAttempts and activates throttling',
      () async {
        final controller = container.read(vaultControllerProvider.notifier);
        await controller.create('correct-password');
        await controller.lock();

        // Attempts 1 to 4: increment failed attempts without lockout
        for (var i = 1; i <= 4; i++) {
          await controller.unlock('wrong-password-$i');
          final state = container.read(vaultControllerProvider);
          expect(state, isA<VaultLocked>());
          final locked = state as VaultLocked;
          expect(locked.failedAttempts, equals(i));
          expect(locked.isLockedOut, isFalse);
        }

        // 5th attempt: triggers 1-second delay lockout
        await controller.unlock('wrong-password-5');
        final fifthState =
            container.read(vaultControllerProvider) as VaultLocked;
        expect(fifthState.failedAttempts, equals(5));
        expect(fifthState.isLockedOut, isTrue);
        expect(fifthState.lockoutUntil, isNotNull);

        // Attempting while locked out rejects immediately with remaining time message
        await controller.unlock('correct-password');
        final rejectedState =
            container.read(vaultControllerProvider) as VaultLocked;
        expect(rejectedState.errorMessage, contains('Too many attempts'));
      },
    );

    test('throttle formula matches specifications', () {
      expect(calculateThrottleDelaySeconds(0), equals(0));
      expect(calculateThrottleDelaySeconds(4), equals(0));
      expect(calculateThrottleDelaySeconds(5), equals(1));
      expect(calculateThrottleDelaySeconds(6), equals(2));
      expect(calculateThrottleDelaySeconds(7), equals(4));
      expect(calculateThrottleDelaySeconds(8), equals(8));
      expect(calculateThrottleDelaySeconds(9), equals(16));
      expect(calculateThrottleDelaySeconds(10), equals(30));
      expect(calculateThrottleDelaySeconds(15), equals(30));
    });

    test('restoreBackup() restores and unlocks vault', () async {
      final controller = container.read(vaultControllerProvider.notifier);
      await controller.create('backup-pass');

      final entry1 = OtpEntry(
        id: 'initial-entry',
        type: OtpType.totp,
        issuer: 'Initial',
        account: 'user',
        secret: 'JBSWY3DPEHPK3PXP',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await controller.addEntry(entry1);

      // Add second entry to generate .bak containing entry1
      final entry2 = OtpEntry(
        id: 'second-entry',
        type: OtpType.totp,
        issuer: 'Second',
        account: 'user2',
        secret: 'JBSWY3DPEHPK3PXP',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await controller.addEntry(entry2);

      await controller.lock();
      await controller.restoreBackup('backup-pass');

      final state = container.read(vaultControllerProvider) as VaultUnlocked;
      expect(state.data.entries.length, equals(1));
      expect(state.data.entries.first.id, equals('initial-entry'));
    });

    test('resetVault() wipes storage and sets VaultNoVault', () async {
      final controller = container.read(vaultControllerProvider.notifier);
      await controller.create('temp-pass');
      expect(await storage.exists(), isTrue);

      await controller.resetVault();

      expect(
        container.read(vaultControllerProvider),
        equals(const VaultNoVault()),
      );
      expect(await storage.exists(), isFalse);
    });

    test('verifyPassword and changePassword', () async {
      final controller = container.read(vaultControllerProvider.notifier);
      await controller.create('current-pass');

      expect(await controller.verifyPassword('current-pass'), isTrue);
      expect(await controller.verifyPassword('wrong-pass'), isFalse);

      await controller.changePassword('current-pass', 'new-super-pass');

      expect(await controller.verifyPassword('new-super-pass'), isTrue);
      expect(await controller.verifyPassword('current-pass'), isFalse);
    });

    test('entry CRUD operations', () async {
      final controller = container.read(vaultControllerProvider.notifier);
      await controller.create('pass');

      final entry1 = OtpEntry(
        id: 'entry-1',
        type: OtpType.totp,
        issuer: 'GitHub',
        account: 'dev@github.com',
        secret: 'JBSWY3DPEHPK3PXP',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      // Add entry
      await controller.addEntry(entry1);
      var current =
          (container.read(vaultControllerProvider) as VaultUnlocked).data;
      expect(current.entries.length, equals(1));
      expect(current.entries.first.issuer, equals('GitHub'));

      // Update entry
      final updatedEntry1 = entry1.copyWith(account: 'updated@github.com');
      await controller.updateEntry(updatedEntry1);
      current = (container.read(vaultControllerProvider) as VaultUnlocked).data;
      expect(current.entries.first.account, equals('updated@github.com'));

      // Delete entry
      await controller.deleteEntry('entry-1');
      current = (container.read(vaultControllerProvider) as VaultUnlocked).data;
      expect(current.entries, isEmpty);
    });

    test('reorderEntries follows Flutter ReorderableListView rules', () async {
      final controller = container.read(vaultControllerProvider.notifier);
      await controller.create('pass');

      final e0 = OtpEntry(
        id: 'e0',
        type: OtpType.totp,
        issuer: 'Alpha',
        account: '0',
        secret: 'JBSWY3DPEHPK3PXP',
        sortOrder: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      final e1 = OtpEntry(
        id: 'e1',
        type: OtpType.totp,
        issuer: 'Beta',
        account: '1',
        secret: 'JBSWY3DPEHPK3PXP',
        sortOrder: 1,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      final e2 = OtpEntry(
        id: 'e2',
        type: OtpType.totp,
        issuer: 'Gamma',
        account: '2',
        secret: 'JBSWY3DPEHPK3PXP',
        sortOrder: 2,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      await controller.addEntry(e0);
      await controller.addEntry(e1);
      await controller.addEntry(e2);

      // Move Alpha (index 0) down after Beta (drop at index 2 in ReorderableListView)
      // Convention: if (oldIndex < newIndex) newIndex -= 1 => targetIndex becomes 1
      await controller.reorderEntries(0, 2);

      final reordered = (container.read(
        vaultControllerProvider,
      ) as VaultUnlocked).data.entries;
      expect(reordered[0].id, equals('e1'));
      expect(reordered[0].sortOrder, equals(0));
      expect(reordered[1].id, equals('e0'));
      expect(reordered[1].sortOrder, equals(1));
      expect(reordered[2].id, equals('e2'));
      expect(reordered[2].sortOrder, equals(2));
    });

    test('incrementHotp increments counter and updates timestamp', () async {
      final controller = container.read(vaultControllerProvider.notifier);
      await controller.create('pass');

      final hotp = OtpEntry(
        id: 'hotp-1',
        type: OtpType.hotp,
        issuer: 'Bank',
        account: 'user',
        secret: 'JBSWY3DPEHPK3PXP',
        counter: 5,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await controller.addEntry(hotp);

      await controller.incrementHotp('hotp-1');

      final entries = (container.read(
        vaultControllerProvider,
      ) as VaultUnlocked).data.entries;
      expect(entries.first.counter, equals(6));
    });

    test('group CRUD and deleting group strips ID from entries', () async {
      final controller = container.read(vaultControllerProvider.notifier);
      await controller.create('pass');

      // Add group
      final group = await controller.addGroup('Finance');
      expect(group.name, equals('Finance'));

      var data =
          (container.read(vaultControllerProvider) as VaultUnlocked).data;
      expect(data.groups.length, equals(1));

      // Add entry associated with the group
      final entry = OtpEntry(
        id: 'fin-entry',
        type: OtpType.totp,
        issuer: 'Bank',
        account: 'user',
        secret: 'JBSWY3DPEHPK3PXP',
        groupIds: [group.id],
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await controller.addEntry(entry);

      // Rename group
      await controller.renameGroup(group.id, 'Personal Finance');
      data = (container.read(vaultControllerProvider) as VaultUnlocked).data;
      expect(data.groups.first.name, equals('Personal Finance'));

      // Delete group: should remove group and strip group.id from entry without deleting entry
      await controller.deleteGroup(group.id);
      data = (container.read(vaultControllerProvider) as VaultUnlocked).data;
      expect(data.groups, isEmpty);
      expect(data.entries.length, equals(1));
      expect(data.entries.first.groupIds, isEmpty);
    });

    test('group reordering and setEntryGroups', () async {
      final controller = container.read(vaultControllerProvider.notifier);
      await controller.create('pass');

      final g1 = await controller.addGroup('Group 1');
      final g2 = await controller.addGroup('Group 2');

      final entry = OtpEntry(
        id: 'entry-groups',
        type: OtpType.totp,
        issuer: 'Test',
        account: 'u',
        secret: 'JBSWY3DPEHPK3PXP',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await controller.addEntry(entry);

      await controller.setEntryGroups('entry-groups', [g1.id, g2.id]);
      var data =
          (container.read(vaultControllerProvider) as VaultUnlocked).data;
      expect(data.entries.first.groupIds, equals([g1.id, g2.id]));

      // Reorder groups
      await controller.reorderGroups(1, 0);
      data = (container.read(vaultControllerProvider) as VaultUnlocked).data;
      expect(data.groups[0].id, equals(g2.id));
      expect(data.groups[1].id, equals(g1.id));
    });

    test(
      'serialized write queue guarantees concurrent mutations do not race',
      () async {
        final controller = container.read(vaultControllerProvider.notifier);
        await controller.create('pass');

        // Launch 10 simultaneous addEntry operations
        final futures = <Future<void>>[];
        for (var i = 0; i < 10; i++) {
          final entry = OtpEntry(
            id: 'concurrent-$i',
            type: OtpType.totp,
            issuer: 'Service $i',
            account: 'user$i',
            secret: 'JBSWY3DPEHPK3PXP',
            sortOrder: i,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );
          futures.add(controller.addEntry(entry));
        }

        await Future.wait(futures);

        final state = container.read(vaultControllerProvider) as VaultUnlocked;
        expect(state.data.entries.length, equals(10));

        // Reload from storage to verify persistent disk integrity
        await controller.lock();
        await controller.unlock('pass');
        final reloaded =
            (container.read(vaultControllerProvider) as VaultUnlocked).data;
        expect(reloaded.entries.length, equals(10));
      },
    );

    test('exportBytes and importAndMerge', () async {
      final controller = container.read(vaultControllerProvider.notifier);
      await controller.create('my-pass');

      final entryLocal = OtpEntry(
        id: 'local-1',
        type: OtpType.totp,
        issuer: 'Local',
        account: 'u1',
        secret: 'JBSWY3DPEHPK3PXP',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await controller.addEntry(entryLocal);

      final exportedBytes = await controller.exportBytes();
      expect(exportedBytes, isNotEmpty);

      // Create an external vault with a different entry
      final extEntry = OtpEntry(
        id: 'external-1',
        type: OtpType.totp,
        issuer: 'External',
        account: 'u2',
        secret: 'MZXW6YTBOI======',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      final extPayload = VaultPayload.empty().copyWith(entries: [extEntry]);
      final extBytes = (await VaultCodec.encryptWithPassword(
        payload: extPayload,
        password: 'ext-pass',
        kdfParams: KdfParams.testFast,
      )).bytes;

      final report = await controller.importAndMerge(extBytes, 'ext-pass');
      expect(report.added, equals(1));

      final state = container.read(vaultControllerProvider) as VaultUnlocked;
      expect(state.data.entries.length, equals(2));
      expect(state.data.entries.any((e) => e.issuer == 'External'), isTrue);
    });

    test(
      'searchQueryProvider, selectedGroupIdProvider, filteredEntriesProvider',
      () async {
        final controller = container.read(vaultControllerProvider.notifier);
        await controller.create('pass');

        final gWork = await controller.addGroup('Work');
        final gPersonal = await controller.addGroup('Personal');

        final eWork = OtpEntry(
          id: 'e-work',
          type: OtpType.totp,
          issuer: 'GitHub Enterprise',
          account: 'alice@corp.com',
          secret: 'JBSWY3DPEHPK3PXP',
          groupIds: [gWork.id],
          note: 'Internal corporate login',
          sortOrder: 0,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );
        final ePersonal = OtpEntry(
          id: 'e-personal',
          type: OtpType.totp,
          issuer: 'Personal Email',
          account: 'alice@gmail.com',
          secret: 'JBSWY3DPEHPK3PXP',
          groupIds: [gPersonal.id],
          note: 'Personal recovery note',
          sortOrder: 1,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        await controller.addEntry(eWork);
        await controller.addEntry(ePersonal);

        // Initially no search and no group filter ("All")
        expect(container.read(filteredEntriesProvider).length, equals(2));

        // Filter by group Work
        container.read(selectedGroupIdProvider.notifier).selectGroup(gWork.id);
        expect(container.read(filteredEntriesProvider).length, equals(1));
        expect(
          container.read(filteredEntriesProvider).first.id,
          equals('e-work'),
        );

        // Reset group filter to All
        container.read(selectedGroupIdProvider.notifier).selectGroup(null);
        expect(container.read(filteredEntriesProvider).length, equals(2));

        // Search by issuer (case insensitive)
        container.read(searchQueryProvider.notifier).setQuery('github');
        expect(container.read(filteredEntriesProvider).length, equals(1));
        expect(
          container.read(filteredEntriesProvider).first.id,
          equals('e-work'),
        );

        // Search by account
        container.read(searchQueryProvider.notifier).setQuery('GMAIL');
        expect(container.read(filteredEntriesProvider).length, equals(1));
        expect(
          container.read(filteredEntriesProvider).first.id,
          equals('e-personal'),
        );

        // Search by note
        container.read(searchQueryProvider.notifier).setQuery('corporate');
        expect(container.read(filteredEntriesProvider).length, equals(1));
        expect(
          container.read(filteredEntriesProvider).first.id,
          equals('e-work'),
        );

        // Non-matching search
        container.read(searchQueryProvider.notifier).setQuery('nonexistent');
        expect(container.read(filteredEntriesProvider), isEmpty);

        // Clear search
        container.read(searchQueryProvider.notifier).clear();
        expect(container.read(filteredEntriesProvider).length, equals(2));
      },
    );

    test('tickerProvider emits current epoch seconds', () async {
      final completer = Completer<int>();
      final sub = container.listen<AsyncValue<int>>(tickerProvider, (
        previous,
        next,
      ) {
        if (next.hasValue && !completer.isCompleted) {
          completer.complete(next.value);
        }
      }, fireImmediately: true);

      final tick = await completer.future;
      final expectedSecond = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(tick, closeTo(expectedSecond, 2));
      sub.close();
    });

    group('F-01 Regression: In-flight mutations racing with lock()', () {
      test(
        'lock() during an in-flight addEntry leaves the vault locked',
        () async {
          final storage = GatedStorage();
          final repo = VaultRepository(
            storage: storage,
            defaultKdfParams: KdfParams.testFast,
          );
          final testContainer = ProviderContainer(
            overrides: [
              vaultStorageProvider.overrideWithValue(storage),
              vaultRepositoryProvider.overrideWithValue(repo),
            ],
          );
          addTearDown(testContainer.dispose);
          final ctrl = testContainer.read(vaultControllerProvider.notifier);
          await ctrl.create('password123');

          storage.gate = Completer<void>();
          final entry = OtpEntry(
            id: 'e1',
            type: OtpType.totp,
            issuer: 'X',
            account: 'y',
            secret: 'JBSWY3DPEHPK3PXP',
          );
          final pending = ctrl.addEntry(entry);
          await Future<void>.delayed(Duration.zero);

          await ctrl.lock();
          expect(
            testContainer.read(vaultControllerProvider),
            isA<VaultLocked>(),
          );

          storage.gate!.complete();
          await pending;

          final state = testContainer.read(vaultControllerProvider);
          expect(
            state,
            isA<VaultLocked>(),
            reason: 'state=$state, repo.isUnlocked=${repo.isUnlocked}',
          );
          expect(repo.isUnlocked, isFalse);
        },
      );

      test(
        'lock() during an in-flight importAndMerge leaves the vault locked',
        () async {
          final storage = GatedStorage();
          final repo = VaultRepository(
            storage: storage,
            defaultKdfParams: KdfParams.testFast,
          );
          final testContainer = ProviderContainer(
            overrides: [
              vaultStorageProvider.overrideWithValue(storage),
              vaultRepositoryProvider.overrideWithValue(repo),
            ],
          );
          addTearDown(testContainer.dispose);
          final ctrl = testContainer.read(vaultControllerProvider.notifier);
          await ctrl.create('password123');

          final importedBytes = (await VaultCodec.encryptWithPassword(
            payload: VaultPayload(
              schemaVersion: 1,
              createdAt: DateTime.now().toUtc(),
              modifiedAt: DateTime.now().toUtc(),
              groups: const [],
              entries: [
                OtpEntry(
                  id: 'imp1',
                  type: OtpType.totp,
                  issuer: 'Imported',
                  account: 'user@imp.com',
                  secret: 'JBSWY3DPEHPK3PXP',
                ),
              ],
            ),
            password: 'importedPass',
            kdfParams: KdfParams.testFast,
          )).bytes;

          storage.gate = Completer<void>();
          final pending = ctrl.importAndMerge(importedBytes, 'importedPass');
          await Future<void>.delayed(Duration.zero);

          await ctrl.lock();
          expect(
            testContainer.read(vaultControllerProvider),
            isA<VaultLocked>(),
          );

          storage.gate!.complete();
          await pending;

          final state = testContainer.read(vaultControllerProvider);
          expect(state, isA<VaultLocked>());
          expect(repo.isUnlocked, isFalse);
        },
      );

      test(
        'lock() during an in-flight changePassword leaves the vault locked',
        () async {
          final storage = GatedStorage();
          final repo = VaultRepository(
            storage: storage,
            defaultKdfParams: KdfParams.testFast,
          );
          final testContainer = ProviderContainer(
            overrides: [
              vaultStorageProvider.overrideWithValue(storage),
              vaultRepositoryProvider.overrideWithValue(repo),
            ],
          );
          addTearDown(testContainer.dispose);
          final ctrl = testContainer.read(vaultControllerProvider.notifier);
          await ctrl.create('password123');

          storage.gate = Completer<void>();
          final pending = ctrl.changePassword('password123', 'newPassword456');
          await Future<void>.delayed(Duration.zero);

          await ctrl.lock();
          expect(
            testContainer.read(vaultControllerProvider),
            isA<VaultLocked>(),
          );

          storage.gate!.complete();
          await pending;

          final state = testContainer.read(vaultControllerProvider);
          expect(state, isA<VaultLocked>());
          expect(repo.isUnlocked, isFalse);
          expect(repo.derivedKey, isNull);
        },
      );
    });
  });
}

class GatedStorage implements VaultStorage {
  Uint8List? main;
  Uint8List? bak;
  Completer<void>? gate;

  @override
  Future<bool> exists() async => main != null;
  @override
  Future<bool> backupExists() async => bak != null;
  @override
  Future<Uint8List> read() async =>
      main ?? (throw const VaultFileNotFound('none'));
  @override
  Future<Uint8List> readBackup() async =>
      bak ?? (throw const VaultFileNotFound('none'));
  @override
  Future<void> writeAtomic(Uint8List bytes) async {
    if (gate != null) await gate!.future;
    if (main != null) bak = main;
    main = Uint8List.fromList(bytes);
  }

  @override
  Future<void> restoreBackup() async => main = bak;
  @override
  Future<void> delete() async => main = bak = null;
}
