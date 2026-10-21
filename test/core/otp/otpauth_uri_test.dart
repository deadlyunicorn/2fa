import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/models/otp_algorithm.dart';
import 'package:offline2fa/core/models/otp_entry.dart';
import 'package:offline2fa/core/models/otp_type.dart';
import 'package:offline2fa/core/otp/otpauth_uri.dart';

void main() {
  group('OtpAuthUri', () {
    group('Google Key Uri Format standard parsing', () {
      test('parses standard TOTP URI with label and query issuer', () {
        const uri =
            'otpauth://totp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP&issuer=Example';
        final entry = OtpAuthUri.parse(uri);

        expect(entry.type, equals(OtpType.totp));
        expect(entry.issuer, equals('Example'));
        expect(entry.account, equals('alice@google.com'));
        expect(entry.secret, equals('JBSWY3DPEHPK3PXP'));
        expect(entry.algorithm, equals(OtpAlgorithm.sha1));
        expect(entry.digits, equals(6));
        expect(entry.period, equals(30));
        expect(entry.counter, equals(0));
      });

      test('parses standard HOTP URI with counter', () {
        const uri =
            'otpauth://hotp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&counter=42';
        final entry = OtpAuthUri.parse(uri);

        expect(entry.type, equals(OtpType.hotp));
        expect(entry.issuer, equals('Example'));
        expect(entry.account, equals('alice@google.com'));
        expect(entry.secret, equals('JBSWY3DPEHPK3PXP'));
        expect(entry.counter, equals(42));
      });
    });

    group('Label parsing and issuer precedence', () {
      test('label without issuer sets empty issuer and parses account', () {
        const uri = 'otpauth://totp/alice@google.com?secret=JBSWY3DPEHPK3PXP';
        final entry = OtpAuthUri.parse(uri);

        expect(entry.issuer, equals(''));
        expect(entry.account, equals('alice@google.com'));
      });

      test('label issuer used when query issuer is absent', () {
        const uri =
            'otpauth://totp/GitHub:user@example.com?secret=JBSWY3DPEHPK3PXP';
        final entry = OtpAuthUri.parse(uri);

        expect(entry.issuer, equals('GitHub'));
        expect(entry.account, equals('user@example.com'));
      });

      test('query issuer takes precedence over label issuer', () {
        const uri =
            'otpauth://totp/OldIssuer:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=NewIssuer';
        final entry = OtpAuthUri.parse(uri);

        expect(entry.issuer, equals('NewIssuer'));
        expect(entry.account, equals('user@example.com'));
      });

      test('strips leading space after colon in label', () {
        const uri =
            'otpauth://totp/GitHub:%20user@example.com?secret=JBSWY3DPEHPK3PXP';
        final entry = OtpAuthUri.parse(uri);

        expect(entry.issuer, equals('GitHub'));
        expect(entry.account, equals('user@example.com'));
      });

      test('URL-encoded characters in issuer and account', () {
        const uri =
            'otpauth://totp/Acme%20Corp:alice%2Bwork%40example.com?secret=JBSWY3DPEHPK3PXP';
        final entry = OtpAuthUri.parse(uri);

        expect(entry.issuer, equals('Acme Corp'));
        expect(entry.account, equals('alice+work@example.com'));
      });
    });

    group('Secret normalization and validation', () {
      test('normalizes lowercase, spaces, and padding in secret', () {
        const uri = 'otpauth://totp/Test:user?secret=jbsw%20y3dp-ehpk%203pxp=';
        final entry = OtpAuthUri.parse(uri);

        expect(entry.secret, equals('JBSWY3DPEHPK3PXP'));
      });

      test('missing secret throws InvalidOtpAuthUriException', () {
        const uri = 'otpauth://totp/Test:user';
        expect(
          () => OtpAuthUri.parse(uri),
          throwsA(isA<InvalidOtpAuthUriException>()),
        );
      });

      test('empty secret throws InvalidOtpAuthUriException', () {
        const uri = 'otpauth://totp/Test:user?secret=';
        expect(
          () => OtpAuthUri.parse(uri),
          throwsA(isA<InvalidOtpAuthUriException>()),
        );
      });

      test('invalid Base32 secret throws InvalidOtpAuthUriException', () {
        const uri = 'otpauth://totp/Test:user?secret=INVALID0189';
        expect(
          () => OtpAuthUri.parse(uri),
          throwsA(isA<InvalidOtpAuthUriException>()),
        );
      });
    });

    group('Parameters: algorithm, digits, period, counter', () {
      test('parses custom algorithm SHA256 and SHA512 (case-insensitive)', () {
        final entrySha256 = OtpAuthUri.parse(
          'otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP&algorithm=sha256',
        );
        expect(entrySha256.algorithm, equals(OtpAlgorithm.sha256));

        final entrySha512 = OtpAuthUri.parse(
          'otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP&algorithm=SHA512',
        );
        expect(entrySha512.algorithm, equals(OtpAlgorithm.sha512));
      });

      test('parses custom digits (7, 8)', () {
        final entry7 = OtpAuthUri.parse(
          'otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP&digits=7',
        );
        expect(entry7.digits, equals(7));

        final entry8 = OtpAuthUri.parse(
          'otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP&digits=8',
        );
        expect(entry8.digits, equals(8));
      });

      test('digits out of range throws InvalidOtpAuthUriException', () {
        expect(
          () => OtpAuthUri.parse(
            'otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP&digits=5',
          ),
          throwsA(isA<InvalidOtpAuthUriException>()),
        );
        expect(
          () => OtpAuthUri.parse(
            'otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP&digits=9',
          ),
          throwsA(isA<InvalidOtpAuthUriException>()),
        );
      });

      test('parses custom period (e.g. 60s)', () {
        final entry = OtpAuthUri.parse(
          'otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP&period=60',
        );
        expect(entry.period, equals(60));
      });

      test('period out of range throws InvalidOtpAuthUriException', () {
        expect(
          () => OtpAuthUri.parse(
            'otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP&period=0',
          ),
          throwsA(isA<InvalidOtpAuthUriException>()),
        );
        expect(
          () => OtpAuthUri.parse(
            'otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP&period=301',
          ),
          throwsA(isA<InvalidOtpAuthUriException>()),
        );
      });

      test('HOTP missing counter throws InvalidOtpAuthUriException', () {
        expect(
          () => OtpAuthUri.parse(
            'otpauth://hotp/Test:user?secret=JBSWY3DPEHPK3PXP',
          ),
          throwsA(isA<InvalidOtpAuthUriException>()),
        );
      });

      test('HOTP negative counter throws InvalidOtpAuthUriException', () {
        expect(
          () => OtpAuthUri.parse(
            'otpauth://hotp/Test:user?secret=JBSWY3DPEHPK3PXP&counter=-5',
          ),
          throwsA(isA<InvalidOtpAuthUriException>()),
        );
      });

      test('ignores unknown query parameters', () {
        const uri =
            'otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP&image=https://example.com/logo.png&custom_param=123';
        final entry = OtpAuthUri.parse(uri);

        expect(entry.issuer, equals('Test'));
        expect(entry.account, equals('user'));
        expect(entry.secret, equals('JBSWY3DPEHPK3PXP'));
      });

      test('invalid algorithm parameter throws InvalidOtpAuthUriException', () {
        const uri =
            'otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP&algorithm=UNKNOWN';
        expect(
          () => OtpAuthUri.parse(uri),
          throwsA(isA<InvalidOtpAuthUriException>()),
        );
      });

      test('parses URI with empty host and path segment type', () {
        const uri = 'otpauth:///totp/Test:user?secret=JBSWY3DPEHPK3PXP';
        final entry = OtpAuthUri.parse(uri);
        expect(entry.type, equals(OtpType.totp));
        expect(entry.issuer, equals('Test'));
        expect(entry.account, equals('user'));
      });

      test('missing type throws InvalidOtpAuthUriException', () {
        const uri = 'otpauth://?secret=JBSWY3DPEHPK3PXP';
        expect(
          () => OtpAuthUri.parse(uri),
          throwsA(isA<InvalidOtpAuthUriException>()),
        );
      });

      test('custom id parameter is respected in parse', () {
        const uri = 'otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP';
        final entry = OtpAuthUri.parse(uri, id: 'custom-uuid-123');
        expect(entry.id, equals('custom-uuid-123'));
      });

      test('OtpAuthUri class and exception helpers', () {
        const parser = OtpAuthUri();
        expect(parser, isNotNull);

        const ex = InvalidOtpAuthUriException('test error');
        expect(ex.toString(), equals('test error'));
      });
    });

    group('Scheme validations and migrations', () {
      test('rejects otpauth-migration scheme with MigrationNotSupportedException', () {
        const uri =
            'otpauth-migration://offline?data=CjEKCkhlbGxvId6tvQoSCUdpdEh1Yi5jb20aBGFsaWNlIAEoATACCICAwPQC';

        expect(
          () => OtpAuthUri.parse(uri),
          throwsA(isA<MigrationNotSupportedException>()),
        );
        expect(
          () => OtpAuthUri.parse(uri),
          throwsA(isA<MigrationNotSupported>()),
        );
      });

      test('rejects non-otpauth schemes', () {
        expect(
          () => OtpAuthUri.parse(
            'https://example.com/totp?secret=JBSWY3DPEHPK3PXP',
          ),
          throwsA(isA<InvalidOtpAuthUriException>()),
        );
        expect(
          () => OtpAuthUri.parse('ftp://totp/user?secret=JBSWY3DPEHPK3PXP'),
          throwsA(isA<InvalidOtpAuthUriException>()),
        );
      });

      test('case-insensitive scheme and type', () {
        const uri = 'OTPAUTH://TOTP/Test:user?secret=JBSWY3DPEHPK3PXP';
        final entry = OtpAuthUri.parse(uri);

        expect(entry.type, equals(OtpType.totp));
        expect(entry.issuer, equals('Test'));
        expect(entry.account, equals('user'));
      });
    });

    group('Round trip serialize -> parse', () {
      test('TOTP with issuer round trip', () {
        final original = OtpEntry(
          id: 'test-id-1',
          type: OtpType.totp,
          issuer: 'GitHub',
          account: 'alice@example.com',
          secret: 'JBSWY3DPEHPK3PXP',
          algorithm: OtpAlgorithm.sha256,
          digits: 8,
          period: 60,
        );

        final serialized = OtpAuthUri.serialize(original);
        final parsed = OtpAuthUri.parse(serialized);

        expect(parsed.type, equals(original.type));
        expect(parsed.issuer, equals(original.issuer));
        expect(parsed.account, equals(original.account));
        expect(parsed.secret, equals(original.secret));
        expect(parsed.algorithm, equals(original.algorithm));
        expect(parsed.digits, equals(original.digits));
        expect(parsed.period, equals(original.period));
      });

      test('HOTP with issuer and counter round trip', () {
        final original = OtpEntry(
          id: 'test-id-2',
          type: OtpType.hotp,
          issuer: 'Google',
          account: 'bob@example.com',
          secret: 'JBSWY3DPEHPK3PXP',
          algorithm: OtpAlgorithm.sha1,
          digits: 6,
          counter: 17,
        );

        final serialized = OtpAuthUri.serialize(original);
        final parsed = OtpAuthUri.parse(serialized);

        expect(parsed.type, equals(original.type));
        expect(parsed.issuer, equals(original.issuer));
        expect(parsed.account, equals(original.account));
        expect(parsed.secret, equals(original.secret));
        expect(parsed.algorithm, equals(original.algorithm));
        expect(parsed.digits, equals(original.digits));
        expect(parsed.counter, equals(original.counter));
      });

      test('TOTP without issuer round trip', () {
        final original = OtpEntry(
          id: 'test-id-3',
          type: OtpType.totp,
          issuer: '',
          account: 'standalone_user',
          secret: 'JBSWY3DPEHPK3PXP',
        );

        final serialized = OtpAuthUri.serialize(original);
        final parsed = OtpAuthUri.parse(serialized);

        expect(parsed.issuer, equals(''));
        expect(parsed.account, equals('standalone_user'));
        expect(parsed.secret, equals('JBSWY3DPEHPK3PXP'));
      });
    });
  });
}
