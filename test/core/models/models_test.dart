import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/models/group.dart';
import 'package:offline2fa/core/models/otp_algorithm.dart';
import 'package:offline2fa/core/models/otp_entry.dart';
import 'package:offline2fa/core/models/otp_type.dart';

void main() {
  group('Group model', () {
    test('JSON serialization round trip', () {
      const group = Group(id: 'g-1', name: 'Work', sortOrder: 2);
      final json = group.toJson();
      final restored = Group.fromJson(json);

      expect(restored, equals(group));
      expect(restored.hashCode, equals(group.hashCode));
      expect(restored.id, equals('g-1'));
      expect(restored.name, equals('Work'));
      expect(restored.sortOrder, equals(2));
    });

    test('copyWith creates modified clone', () {
      const group = Group(id: 'g-1', name: 'Personal', sortOrder: 0);
      final updated = group.copyWith(name: 'Work', sortOrder: 1);

      expect(updated.id, equals('g-1'));
      expect(updated.name, equals('Work'));
      expect(updated.sortOrder, equals(1));

      final updatedIdOnly = group.copyWith(id: 'g-2');
      expect(updatedIdOnly.id, equals('g-2'));
      expect(updatedIdOnly.name, equals('Personal'));
      expect(updatedIdOnly.sortOrder, equals(0));
    });

    test('group equality and toString', () {
      const g1 = Group(id: 'g-1', name: 'Work', sortOrder: 0);
      const g2 = Group(id: 'g-1', name: 'Work', sortOrder: 0);
      const gDiffId = Group(id: 'g-2', name: 'Work', sortOrder: 0);
      const gDiffName = Group(id: 'g-1', name: 'Personal', sortOrder: 0);
      const gDiffOrder = Group(id: 'g-1', name: 'Work', sortOrder: 1);

      expect(g1, equals(g2));
      expect(g1 == gDiffId, isFalse);
      expect(g1 == gDiffName, isFalse);
      expect(g1 == gDiffOrder, isFalse);
      expect(
        g1.toString(),
        contains('Group(id: g-1, name: Work, sortOrder: 0)'),
      );
    });

    test('missing or empty id throws FormatException', () {
      expect(
        () => Group.fromJson({'name': 'Work'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => Group.fromJson({'id': '', 'name': 'Work'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('missing name throws FormatException', () {
      expect(
        () => Group.fromJson({'id': 'g-1'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('OtpType enum', () {
    test('fromString parses case-insensitively', () {
      expect(OtpType.fromString('totp'), equals(OtpType.totp));
      expect(OtpType.fromString('TOTP'), equals(OtpType.totp));
      expect(OtpType.fromString('hotp'), equals(OtpType.hotp));
      expect(OtpType.fromString('HOTP'), equals(OtpType.hotp));
    });

    test('fromString throws FormatException on invalid type', () {
      expect(
        () => OtpType.fromString('invalid'),
        throwsA(isA<FormatException>()),
      );
    });

    test('tryParse handles valid and invalid values', () {
      expect(OtpType.tryParse('totp'), equals(OtpType.totp));
      expect(OtpType.tryParse('HOTP'), equals(OtpType.hotp));
      expect(OtpType.tryParse('other'), isNull);
      expect(OtpType.tryParse(null), isNull);
    });

    test('toJson returns nameValue', () {
      expect(OtpType.totp.toJson(), equals('totp'));
      expect(OtpType.hotp.toJson(), equals('hotp'));
    });
  });

  group('OtpAlgorithm enum', () {
    test(
      'fromString parses SHA1, SHA256, SHA512 case-insensitively with hyphens',
      () {
        expect(OtpAlgorithm.fromString('SHA1'), equals(OtpAlgorithm.sha1));
        expect(OtpAlgorithm.fromString('sha1'), equals(OtpAlgorithm.sha1));
        expect(OtpAlgorithm.fromString('SHA-1'), equals(OtpAlgorithm.sha1));
        expect(OtpAlgorithm.fromString('SHA256'), equals(OtpAlgorithm.sha256));
        expect(OtpAlgorithm.fromString('sha256'), equals(OtpAlgorithm.sha256));
        expect(OtpAlgorithm.fromString('SHA-256'), equals(OtpAlgorithm.sha256));
        expect(OtpAlgorithm.fromString('SHA512'), equals(OtpAlgorithm.sha512));
        expect(OtpAlgorithm.fromString('sha512'), equals(OtpAlgorithm.sha512));
        expect(OtpAlgorithm.fromString('SHA-512'), equals(OtpAlgorithm.sha512));
      },
    );

    test('fromString throws FormatException on unsupported algorithm', () {
      expect(
        () => OtpAlgorithm.fromString('MD5'),
        throwsA(isA<FormatException>()),
      );
    });

    test('tryParse returns algorithm or null', () {
      expect(OtpAlgorithm.tryParse('SHA256'), equals(OtpAlgorithm.sha256));
      expect(OtpAlgorithm.tryParse('MD5'), isNull);
      expect(OtpAlgorithm.tryParse(null), isNull);
    });

    test('toJson returns nameValue', () {
      expect(OtpAlgorithm.sha1.toJson(), equals('SHA1'));
      expect(OtpAlgorithm.sha256.toJson(), equals('SHA256'));
      expect(OtpAlgorithm.sha512.toJson(), equals('SHA512'));
    });
  });

  group('OtpEntry model', () {
    final sampleCreatedAt = DateTime.utc(2026, 10, 21, 9, 0, 0);
    final sampleUpdatedAt = DateTime.utc(2026, 10, 21, 9, 30, 0);

    test('JSON serialization round trip (§5.5 schema)', () {
      final entry = OtpEntry(
        id: 'uuid-1234',
        type: OtpType.totp,
        issuer: 'GitHub',
        account: 'user@example.com',
        secret: 'JBSWY3DPEHPK3PXP',
        algorithm: OtpAlgorithm.sha1,
        digits: 6,
        period: 30,
        counter: 0,
        groupIds: const ['uuid-group-1'],
        note: 'My personal token',
        sortOrder: 1,
        createdAt: sampleCreatedAt,
        updatedAt: sampleUpdatedAt,
      );

      final json = entry.toJson();
      expect(json['id'], equals('uuid-1234'));
      expect(json['type'], equals('totp'));
      expect(json['issuer'], equals('GitHub'));
      expect(json['account'], equals('user@example.com'));
      expect(json['secret'], equals('JBSWY3DPEHPK3PXP'));
      expect(json['algorithm'], equals('SHA1'));
      expect(json['digits'], equals(6));
      expect(json['period'], equals(30));
      expect(
        json.containsKey('counter'),
        isFalse,
      ); // TOTP does not serialize counter
      expect(json['groupIds'], equals(['uuid-group-1']));
      expect(json['note'], equals('My personal token'));
      expect(json['sortOrder'], equals(1));
      expect(json['createdAt'], equals('2026-10-21T09:00:00.000Z'));
      expect(json['updatedAt'], equals('2026-10-21T09:30:00.000Z'));

      final restored = OtpEntry.fromJson(json);
      expect(restored, equals(entry));
      expect(restored.hashCode, equals(entry.hashCode));
    });

    test('HOTP serializes counter and omits period', () {
      final hotpEntry = OtpEntry(
        id: 'hotp-1',
        type: OtpType.hotp,
        issuer: 'AWS',
        account: 'admin',
        secret: 'JBSWY3DPEHPK3PXP',
        counter: 15,
        createdAt: sampleCreatedAt,
        updatedAt: sampleUpdatedAt,
      );

      final json = hotpEntry.toJson();
      expect(json['type'], equals('hotp'));
      expect(json['counter'], equals(15));
      expect(json.containsKey('period'), isFalse);

      final restored = OtpEntry.fromJson(json);
      expect(restored.type, equals(OtpType.hotp));
      expect(restored.counter, equals(15));
      expect(restored.period, equals(30)); // Default period
    });

    test('ignores unknown fields on read', () {
      final json = <String, dynamic>{
        'id': 'uuid-unknown',
        'type': 'totp',
        'secret': 'JBSWY3DPEHPK3PXP',
        'unknownKey1': 'arbitrary_value',
        'image': 'https://example.com/logo.png',
        'custom_nested': {'a': 1, 'b': 2},
      };

      final entry = OtpEntry.fromJson(json);
      expect(entry.id, equals('uuid-unknown'));
      expect(entry.secret, equals('JBSWY3DPEHPK3PXP'));
    });

    test('missing optional fields receive sensible defaults', () {
      final minimalJson = <String, dynamic>{
        'type': 'totp',
        'secret': 'JBSWY3DPEHPK3PXP',
      };

      final entry = OtpEntry.fromJson(minimalJson);
      expect(entry.id, equals(''));
      expect(entry.issuer, equals(''));
      expect(entry.account, equals(''));
      expect(entry.algorithm, equals(OtpAlgorithm.sha1));
      expect(entry.digits, equals(6));
      expect(entry.period, equals(30));
      expect(entry.counter, equals(0));
      expect(entry.groupIds, isEmpty);
      expect(entry.note, equals(''));
      expect(entry.sortOrder, equals(0));
      expect(
        entry.createdAt,
        equals(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)),
      );
      expect(
        entry.updatedAt,
        equals(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)),
      );
    });

    test('throws FormatException when secret is missing or invalid Base32', () {
      expect(
        () => OtpEntry.fromJson({'type': 'totp'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => OtpEntry.fromJson({'type': 'totp', 'secret': ''}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => OtpEntry.fromJson({'type': 'totp', 'secret': 'INVALID0189'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when type is missing or invalid', () {
      expect(
        () => OtpEntry.fromJson({'secret': 'JBSWY3DPEHPK3PXP'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => OtpEntry.fromJson({
          'type': 'unknown',
          'secret': 'JBSWY3DPEHPK3PXP',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'throws FormatException when digits, period, or counter are out of range',
      () {
        expect(
          () => OtpEntry.fromJson({
            'type': 'totp',
            'secret': 'JBSWY3DPEHPK3PXP',
            'digits': 5,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => OtpEntry.fromJson({
            'type': 'totp',
            'secret': 'JBSWY3DPEHPK3PXP',
            'period': 0,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => OtpEntry.fromJson({
            'type': 'hotp',
            'secret': 'JBSWY3DPEHPK3PXP',
            'counter': -1,
          }),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('groupIds is unmodifiable', () {
      final entry = OtpEntry(
        id: '1',
        type: OtpType.totp,
        secret: 'JBSWY3DPEHPK3PXP',
        groupIds: ['g1', 'g2'],
      );

      expect(() => entry.groupIds.add('g3'), throwsUnsupportedError);
    });

    test('copyWith creates modified instance with normalized secret', () {
      final entry = OtpEntry(
        id: '1',
        type: OtpType.totp,
        secret: 'JBSWY3DPEHPK3PXP',
        issuer: 'Initial',
      );

      final updated = entry.copyWith(issuer: 'Updated', secret: 'mzxw6===');

      expect(updated.issuer, equals('Updated'));
      expect(updated.secret, equals('MZXW6'));
    });

    test('toString omits secret for security', () {
      final entry = OtpEntry(
        id: '1',
        type: OtpType.totp,
        secret: 'JBSWY3DPEHPK3PXP',
        issuer: 'SensitiveService',
      );

      final str = entry.toString();
      expect(str.contains('JBSWY3DPEHPK3PXP'), isFalse);
      expect(str.contains('SensitiveService'), isTrue);
    });
  });
}
