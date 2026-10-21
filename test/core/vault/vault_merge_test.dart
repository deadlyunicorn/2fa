import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/models/group.dart';
import 'package:offline2fa/core/models/otp_algorithm.dart';
import 'package:offline2fa/core/models/otp_entry.dart';
import 'package:offline2fa/core/models/otp_type.dart';
import 'package:offline2fa/core/vault/vault_merge.dart';
import 'package:offline2fa/core/vault/vault_payload.dart';

void main() {
  final now = DateTime.utc(2026, 10, 21, 12, 0, 0);
  final mergeTime = DateTime.utc(2026, 10, 21, 13, 0, 0);

  OtpEntry createTotp({
    required String id,
    required String issuer,
    required String account,
    required String secret,
    List<String> groupIds = const [],
    int sortOrder = 0,
  }) {
    return OtpEntry(
      id: id,
      type: OtpType.totp,
      issuer: issuer,
      account: account,
      secret: secret,
      algorithm: OtpAlgorithm.sha1,
      digits: 6,
      period: 30,
      groupIds: groupIds,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
  }

  OtpEntry createHotp({
    required String id,
    required String issuer,
    required String account,
    required String secret,
    required int counter,
    List<String> groupIds = const [],
    int sortOrder = 0,
  }) {
    return OtpEntry(
      id: id,
      type: OtpType.hotp,
      issuer: issuer,
      account: account,
      secret: secret,
      algorithm: OtpAlgorithm.sha1,
      digits: 6,
      counter: counter,
      groupIds: groupIds,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('VaultMerge', () {
    test('empty local + full imported adds all entries and creates groups', () {
      final local = VaultPayload.empty(now: now);
      const importedGroup = Group(id: 'imp-g1', name: 'Work', sortOrder: 0);
      final importedEntry = createTotp(
        id: 'imp-e1',
        issuer: 'GitHub',
        account: 'dev@github.com',
        secret: 'JBSWY3DPEHPK3PXP',
        groupIds: ['imp-g1'],
      );

      final imported = VaultPayload(
        createdAt: now,
        modifiedAt: now,
        groups: [importedGroup],
        entries: [importedEntry],
      );

      final result = mergeVaults(
        local: local,
        imported: imported,
        now: mergeTime,
      );

      expect(result.report.added, equals(1));
      expect(result.report.groupsCreated, equals(1));
      expect(result.report.skippedDuplicates, equals(0));
      expect(result.report.updated, equals(0));
      expect(result.report.invalid, equals(0));

      expect(result.merged.groups.length, equals(1));
      expect(result.merged.groups.first.name, equals('Work'));
      expect(
        result.merged.groups.first.id,
        isNot(equals('imp-g1')),
      ); // new UUID

      expect(result.merged.entries.length, equals(1));
      final mergedEntry = result.merged.entries.first;
      expect(mergedEntry.issuer, equals('GitHub'));
      expect(mergedEntry.id, isNot(equals('imp-e1'))); // new UUID
      expect(mergedEntry.groupIds, equals([result.merged.groups.first.id]));
      expect(result.merged.modifiedAt, equals(mergeTime));
    });

    test('full local + empty imported changes nothing', () {
      const localGroup = Group(id: 'loc-g1', name: 'Personal', sortOrder: 0);
      final localEntry = createTotp(
        id: 'loc-e1',
        issuer: 'Google',
        account: 'user@gmail.com',
        secret: 'JBSWY3DPEHPK3PXP',
      );
      final local = VaultPayload(
        createdAt: now,
        modifiedAt: now,
        groups: [localGroup],
        entries: [localEntry],
      );
      final imported = VaultPayload.empty(now: now);

      final result = mergeVaults(
        local: local,
        imported: imported,
        now: mergeTime,
      );

      expect(result.report.added, equals(0));
      expect(result.report.groupsCreated, equals(0));
      expect(result.report.skippedDuplicates, equals(0));
      expect(result.report.updated, equals(0));
      expect(result.merged.entries, equals(local.entries));
      expect(result.merged.groups, equals(local.groups));
      expect(result.merged.modifiedAt, equals(now)); // untouched
    });

    test('all duplicates: TOTP skipped, identical HOTP skipped', () {
      final localTotp = createTotp(
        id: 'e1',
        issuer: 'GitHub',
        account: 'user@example.com',
        secret: 'JBSWY3DPEHPK3PXP',
      );
      final localHotp = createHotp(
        id: 'e2',
        issuer: 'Acme',
        account: 'admin',
        secret: 'KRSXG5CTMVRXEZLU',
        counter: 10,
      );
      final local = VaultPayload(
        createdAt: now,
        modifiedAt: now,
        entries: [localTotp, localHotp],
      );

      final importedTotp = createTotp(
        id: 'diff-id-1',
        issuer: '  github  ', // case & trim difference
        account: 'User@Example.COM ',
        secret: 'jbsw y3dp ehpk 3pxp', // space & lowercase base32
      );
      final importedHotp = createHotp(
        id: 'diff-id-2',
        issuer: 'Acme',
        account: 'admin',
        secret: 'KRSXG5CTMVRXEZLU',
        counter: 10, // identical counter
      );
      final imported = VaultPayload(
        createdAt: now,
        modifiedAt: now,
        entries: [importedTotp, importedHotp],
      );

      final result = mergeVaults(local: local, imported: imported);

      expect(result.report.added, equals(0));
      expect(result.report.skippedDuplicates, equals(2));
      expect(result.report.updated, equals(0));
      expect(result.merged.entries.length, equals(2));
    });

    test('HOTP duplicate with different counter updates local to max(local, imported)', () {
      final localHotp1 = createHotp(
        id: 'e1',
        issuer: 'Acme1',
        account: 'alice',
        secret: 'KRSXG5CTMVRXEZLU',
        counter: 5,
      );
      final localHotp2 = createHotp(
        id: 'e2',
        issuer: 'Acme2',
        account: 'bob',
        secret: 'JBSWY3DPEHPK3PXP',
        counter: 20,
      );
      final local = VaultPayload(
        createdAt: now,
        modifiedAt: now,
        entries: [localHotp1, localHotp2],
      );

      final importedHotp1 = createHotp(
        id: 'imp-1',
        issuer: 'Acme1',
        account: 'alice',
        secret: 'KRSXG5CTMVRXEZLU',
        counter: 15, // higher than local 5
      );
      final importedHotp2 = createHotp(
        id: 'imp-2',
        issuer: 'Acme2',
        account: 'bob',
        secret: 'JBSWY3DPEHPK3PXP',
        counter: 8, // lower than local 20
      );
      final imported = VaultPayload(
        createdAt: now,
        modifiedAt: now,
        entries: [importedHotp1, importedHotp2],
      );

      final result = mergeVaults(
        local: local,
        imported: imported,
        now: mergeTime,
      );

      expect(result.report.updated, equals(2));
      expect(result.report.added, equals(0));
      expect(result.report.skippedDuplicates, equals(0));

      final e1 = result.merged.entries.firstWhere((e) => e.issuer == 'Acme1');
      expect(e1.counter, equals(15)); // max(5, 15)
      expect(e1.updatedAt, equals(mergeTime));

      final e2 = result.merged.entries.firstWhere((e) => e.issuer == 'Acme2');
      expect(e2.counter, equals(20)); // max(20, 8)
      expect(e2.updatedAt, equals(mergeTime));
    });

    test('same secret with different labels (issuer or account) is kept as separate entry', () {
      final local = VaultPayload(
        createdAt: now,
        modifiedAt: now,
        entries: [
          createTotp(
            id: 'e1',
            issuer: 'GitHub',
            account: 'alice@work.com',
            secret: 'JBSWY3DPEHPK3PXP',
          ),
        ],
      );

      final imported = VaultPayload(
        createdAt: now,
        modifiedAt: now,
        entries: [
          // Same secret, different account
          createTotp(
            id: 'imp-1',
            issuer: 'GitHub',
            account: 'alice@personal.com',
            secret: 'JBSWY3DPEHPK3PXP',
          ),
          // Same secret, different issuer
          createTotp(
            id: 'imp-2',
            issuer: 'GitLab',
            account: 'alice@work.com',
            secret: 'JBSWY3DPEHPK3PXP',
          ),
        ],
      );

      final result = mergeVaults(local: local, imported: imported);

      expect(result.report.added, equals(2));
      expect(result.report.skippedDuplicates, equals(0));
      expect(result.merged.entries.length, equals(3));
    });

    test(
      'group matching is case-insensitive and trimmed, reuses local group ID',
      () {
        const localGroup = Group(
          id: 'local-work-id',
          name: 'Work',
          sortOrder: 0,
        );
        final local = VaultPayload(
          createdAt: now,
          modifiedAt: now,
          groups: [localGroup],
        );

        const importedGroup = Group(
          id: 'imported-work-id',
          name: '  work  ',
          sortOrder: 5,
        );
        final importedEntry = createTotp(
          id: 'imp-e1',
          issuer: 'Slack',
          account: 'dev',
          secret: 'JBSWY3DPEHPK3PXP',
          groupIds: ['imported-work-id', 'unknown-group-id'],
        );
        final imported = VaultPayload(
          createdAt: now,
          modifiedAt: now,
          groups: [importedGroup],
          entries: [importedEntry],
        );

        final result = mergeVaults(local: local, imported: imported);

        expect(result.report.groupsCreated, equals(0));
        expect(result.report.added, equals(1));
        expect(result.merged.groups.length, equals(1));
        expect(result.merged.groups.first.id, equals('local-work-id'));

        final addedEntry = result.merged.entries.first;
        // 'imported-work-id' remapped to 'local-work-id', 'unknown-group-id' dropped
        expect(addedEntry.groupIds, equals(['local-work-id']));
      },
    );

    test('avoids ID collisions with local entries by assigning new UUIDs', () {
      const collisionId = 'collision-uuid-1234';
      final local = VaultPayload(
        createdAt: now,
        modifiedAt: now,
        entries: [
          createTotp(
            id: collisionId,
            issuer: 'LocalApp',
            account: 'loc',
            secret: 'JBSWY3DPEHPK3PXP',
          ),
        ],
      );

      final imported = VaultPayload(
        createdAt: now,
        modifiedAt: now,
        entries: [
          createTotp(
            id: collisionId, // Same ID, but different account
            issuer: 'ImportedApp',
            account: 'imp',
            secret: 'KRSXG5CTMVRXEZLU',
          ),
        ],
      );

      final result = mergeVaults(local: local, imported: imported);

      expect(result.report.added, equals(1));
      expect(result.merged.entries.length, equals(2));
      final ids = result.merged.entries.map((e) => e.id).toSet();
      expect(
        ids.length,
        equals(2),
        reason: 'Every entry in merged vault must have a unique ID',
      );
    });

    test('reports invalid entries from imported payload', () {
      final local = VaultPayload.empty(now: now);
      final imported = VaultPayload(
        createdAt: now,
        modifiedAt: now,
        invalidEntriesSkipped: 3,
      );

      final result = mergeVaults(local: local, imported: imported);
      expect(result.report.invalid, equals(3));
    });

    test(
      'VaultMerge.merge static wrapper works with local or current parameters',
      () {
        final local = VaultPayload.empty(now: now);
        final imported = VaultPayload.empty(now: now);

        final res1 = VaultMerge.merge(local: local, imported: imported);
        final res2 = VaultMerge.merge(current: local, imported: imported);

        expect(res1.report, equals(res2.report));
        expect(() => VaultMerge.merge(imported: imported), throwsArgumentError);
      },
    );
  });
}
