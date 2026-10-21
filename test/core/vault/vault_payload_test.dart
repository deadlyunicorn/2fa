import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/models/group.dart';
import 'package:offline2fa/core/models/otp_algorithm.dart';
import 'package:offline2fa/core/models/otp_entry.dart';
import 'package:offline2fa/core/models/otp_type.dart';
import 'package:offline2fa/core/vault/vault_errors.dart';
import 'package:offline2fa/core/vault/vault_payload.dart';

void main() {
  group('VaultPayload', () {
    final now = DateTime.utc(2026, 10, 21, 12, 0, 0);

    test('round-trip JSON serialization and deserialization', () {
      const group = Group(id: 'g-1', name: 'Personal', sortOrder: 0);
      final entry = OtpEntry(
        id: 'e-1',
        type: OtpType.totp,
        issuer: 'Google',
        account: 'alice@gmail.com',
        secret: 'JBSWY3DPEHPK3PXP',
        algorithm: OtpAlgorithm.sha1,
        digits: 6,
        period: 30,
        groupIds: ['g-1'],
        note: 'My backup code',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      );

      final payload = VaultPayload(
        schemaVersion: 1,
        createdAt: now,
        modifiedAt: now,
        groups: [group],
        entries: [entry],
      );

      final json = payload.toJson();
      final restored = VaultPayload.fromJson(json);

      expect(restored.schemaVersion, equals(1));
      expect(restored.createdAt, equals(now));
      expect(restored.modifiedAt, equals(now));
      expect(restored.groups, equals([group]));
      expect(restored.entries, equals([entry]));
      expect(restored.invalidEntriesSkipped, equals(0));
      expect(restored, equals(payload));
    });

    test('ignores unknown top-level and entry fields', () {
      final json = {
        'schemaVersion': 1,
        'createdAt': now.toIso8601String(),
        'modifiedAt': now.toIso8601String(),
        'unknownRootField': 'ignored',
        'groups': [
          {'id': 'g-1', 'name': 'Work', 'extra': 'ignored'},
        ],
        'entries': [
          {
            'id': 'e-1',
            'type': 'totp',
            'issuer': 'Slack',
            'account': 'bob@work.com',
            'secret': 'JBSWY3DPEHPK3PXP',
            'extraEntryProp': 12345,
          },
        ],
      };

      final payload = VaultPayload.fromJson(json);
      expect(payload.groups.length, equals(1));
      expect(payload.entries.length, equals(1));
      expect(payload.invalidEntriesSkipped, equals(0));
    });

    test('skips invalid entries and increments invalidEntriesSkipped', () {
      final json = {
        'schemaVersion': 1,
        'createdAt': now.toIso8601String(),
        'modifiedAt': now.toIso8601String(),
        'entries': [
          // Valid entry
          {
            'id': 'e-1',
            'type': 'totp',
            'issuer': 'GitHub',
            'account': 'dev',
            'secret': 'JBSWY3DPEHPK3PXP',
          },
          // Missing secret
          {'id': 'e-2', 'type': 'totp', 'issuer': 'Broken1', 'account': 'dev'},
          // Invalid Base32 secret
          {
            'id': 'e-3',
            'type': 'totp',
            'issuer': 'Broken2',
            'account': 'dev',
            'secret': '1890Invalid!',
          },
          // Missing type
          {
            'id': 'e-4',
            'issuer': 'Broken3',
            'account': 'dev',
            'secret': 'JBSWY3DPEHPK3PXP',
          },
          // Non-map item
          'not a map',
        ],
      };

      final payload = VaultPayload.fromJson(json);
      expect(payload.entries.length, equals(1));
      expect(payload.entries.first.issuer, equals('GitHub'));
      expect(payload.invalidEntriesSkipped, equals(4));
    });

    test('throws InvalidPayload on unsupported schemaVersion', () {
      expect(
        () => VaultPayload.fromJson({'schemaVersion': 2}),
        throwsA(isA<InvalidPayload>()),
      );

      expect(
        () => VaultPayload.fromJson({'schemaVersion': 0}),
        throwsA(isA<InvalidPayload>()),
      );

      expect(() => VaultPayload.fromJson({}), throwsA(isA<InvalidPayload>()));
    });

    test('empty factory creates initialized empty payload', () {
      final empty = VaultPayload.empty(now: now);
      expect(empty.schemaVersion, equals(1));
      expect(empty.createdAt, equals(now));
      expect(empty.modifiedAt, equals(now));
      expect(empty.groups, isEmpty);
      expect(empty.entries, isEmpty);
      expect(empty.invalidEntriesSkipped, equals(0));
    });

    test('copyWith updates all properties', () {
      final initial = VaultPayload.empty(now: now);
      final newTime = DateTime.utc(2026, 10, 22);
      const group = Group(id: 'g-2', name: 'Other', sortOrder: 1);
      final entry = OtpEntry(
        id: 'e-2',
        type: OtpType.totp,
        issuer: 'A',
        account: 'b',
        secret: 'JBSWY3DPEHPK3PXP',
      );

      final updated = initial.copyWith(
        schemaVersion: 1,
        createdAt: newTime,
        modifiedAt: newTime,
        groups: [group],
        entries: [entry],
        invalidEntriesSkipped: 2,
      );

      expect(updated.createdAt, equals(newTime));
      expect(updated.modifiedAt, equals(newTime));
      expect(updated.groups, equals([group]));
      expect(updated.entries, equals([entry]));
      expect(updated.invalidEntriesSkipped, equals(2));
      expect(updated.hashCode, isNot(equals(initial.hashCode)));
      expect(updated.toString(), contains('groups: 1, entries: 1'));
    });

    test('skips malformed group objects in groups array', () {
      final json = {
        'schemaVersion': 1,
        'createdAt': now.toIso8601String(),
        'modifiedAt': now.toIso8601String(),
        'groups': [
          {'id': '', 'name': 'invalid empty id'},
          'not a map',
          {'id': 'valid-id', 'name': 'Valid Group'},
        ],
      };

      final payload = VaultPayload.fromJson(json);
      expect(payload.groups.length, equals(1));
      expect(payload.groups.first.name, equals('Valid Group'));
    });
  });

  group('VaultException subclasses', () {
    test('subclasses instantiate and provide user-friendly toString', () {
      const e1 = NotAVaultFile('Custom not a vault');
      expect(e1.toString(), contains('Custom not a vault'));

      const e2 = UnsupportedVersion('Custom unsupported version');
      expect(e2.toString(), contains('Custom unsupported version'));

      const e3 = UnsupportedKdf('Custom unsupported KDF');
      expect(e3.toString(), contains('Custom unsupported KDF'));

      const e4 = UnsupportedCipher('Custom unsupported cipher');
      expect(e4.toString(), contains('Custom unsupported cipher'));

      const e5 = InvalidHeader('Custom invalid header');
      expect(e5.toString(), contains('Custom invalid header'));

      const e6 = WrongPasswordOrCorrupted('Wrong password or corrupted file');
      expect(e6.toString(), contains('Wrong password or corrupted file'));

      const e7 = InvalidPayload('Custom invalid payload');
      expect(e7.toString(), contains('Custom invalid payload'));
    });
  });
}
