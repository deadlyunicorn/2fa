import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/models/otp_algorithm.dart';
import 'package:offline2fa/core/otp/totp.dart';

void main() {
  group('TOTP (RFC 6238)', () {
    // RFC 6238 Appendix B test seeds
    final seedSha1 = Uint8List.fromList(utf8.encode('12345678901234567890'));
    final seedSha256 = Uint8List.fromList(
      utf8.encode('12345678901234567890123456789012'),
    );
    final seedSha512 = Uint8List.fromList(
      utf8.encode(
        '1234567890123456789012345678901234567890123456789012345678901234',
      ),
    );

    // RFC 6238 Appendix B Table 1 test vectors (digits = 8, period = 30)
    final rfc6238Vectors =
        <
          ({
            int time,
            String expectedSha1,
            String expectedSha256,
            String expectedSha512,
          })
        >[
          (
            time: 59,
            expectedSha1: '94287082',
            expectedSha256: '46119246',
            expectedSha512: '90693936',
          ),
          (
            time: 1111111109,
            expectedSha1: '07081804',
            expectedSha256: '68084774',
            expectedSha512: '25091201',
          ),
          (
            time: 1111111111,
            expectedSha1: '14050471',
            expectedSha256: '67062674',
            expectedSha512: '99943326',
          ),
          (
            time: 1234567890,
            expectedSha1: '89005924',
            expectedSha256: '91819424',
            expectedSha512: '93441116',
          ),
          (
            time: 2000000000,
            expectedSha1: '69279037',
            expectedSha256: '90698825',
            expectedSha512: '38618901',
          ),
          (
            time: 20000000000,
            expectedSha1: '65353130',
            expectedSha256: '77737706',
            expectedSha512: '47863826',
          ),
        ];

    group('RFC 6238 Appendix B test vectors (all 18 cases)', () {
      for (final vec in rfc6238Vectors) {
        test('time ${vec.time} SHA1 -> ${vec.expectedSha1}', () {
          final code = totp(
            seedSha1,
            vec.time,
            digits: 8,
            algorithm: OtpAlgorithm.sha1,
          );
          expect(code, equals(vec.expectedSha1));

          final codeFromClass = Totp.generate(
            secret: seedSha1,
            unixSeconds: vec.time,
            digits: 8,
            algorithm: OtpAlgorithm.sha1,
          );
          expect(codeFromClass, equals(vec.expectedSha1));
        });

        test('time ${vec.time} SHA256 -> ${vec.expectedSha256}', () {
          final code = totp(
            seedSha256,
            vec.time,
            digits: 8,
            algorithm: OtpAlgorithm.sha256,
          );
          expect(code, equals(vec.expectedSha256));

          final codeFromClass = Totp.generate(
            secret: seedSha256,
            unixSeconds: vec.time,
            digits: 8,
            algorithm: OtpAlgorithm.sha256,
          );
          expect(codeFromClass, equals(vec.expectedSha256));
        });

        test('time ${vec.time} SHA512 -> ${vec.expectedSha512}', () {
          final code = totp(
            seedSha512,
            vec.time,
            digits: 8,
            algorithm: OtpAlgorithm.sha512,
          );
          expect(code, equals(vec.expectedSha512));

          final codeFromClass = Totp.generate(
            secret: seedSha512,
            unixSeconds: vec.time,
            digits: 8,
            algorithm: OtpAlgorithm.sha512,
          );
          expect(codeFromClass, equals(vec.expectedSha512));
        });
      }
    });

    group('Remaining seconds calculation', () {
      test('period 30 step transitions', () {
        expect(remainingSeconds(0, period: 30), equals(30));
        expect(remainingSeconds(1, period: 30), equals(29));
        expect(remainingSeconds(28, period: 30), equals(2));
        expect(remainingSeconds(29, period: 30), equals(1));
        expect(remainingSeconds(30, period: 30), equals(30));
        expect(remainingSeconds(31, period: 30), equals(29));
        expect(remainingSeconds(59, period: 30), equals(1));
      });

      test('custom periods', () {
        expect(remainingSeconds(10, period: 15), equals(5));
        expect(remainingSeconds(14, period: 15), equals(1));
        expect(remainingSeconds(15, period: 15), equals(15));
        expect(remainingSeconds(0, period: 60), equals(60));
        expect(remainingSeconds(45, period: 60), equals(15));
      });

      test('Totp.remainingSeconds static helper works identically', () {
        expect(Totp.remainingSeconds(25, period: 30), equals(5));
      });

      test('negative unixSeconds throws ArgumentError', () {
        expect(() => remainingSeconds(-1, period: 30), throwsArgumentError);
      });

      test('period <= 0 throws ArgumentError', () {
        expect(() => remainingSeconds(10, period: 0), throwsArgumentError);
        expect(() => remainingSeconds(10, period: -10), throwsArgumentError);
      });
    });

    group('Parameter validations', () {
      test('period < 1 or > 300 throws ArgumentError', () {
        expect(() => totp(seedSha1, 100, period: 0), throwsArgumentError);
        expect(() => totp(seedSha1, 100, period: 301), throwsArgumentError);
      });

      test('negative unixSeconds throws ArgumentError', () {
        expect(() => totp(seedSha1, -1), throwsArgumentError);
      });

      test('digits < 6 or > 8 throws ArgumentError', () {
        expect(() => totp(seedSha1, 100, digits: 5), throwsArgumentError);
        expect(() => totp(seedSha1, 100, digits: 9), throwsArgumentError);
      });
    });
  });
}
