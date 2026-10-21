import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/models/otp_algorithm.dart';
import 'package:offline2fa/core/otp/hotp.dart';

void main() {
  group('HOTP (RFC 4226)', () {
    // RFC 4226 Appendix D test secret: 20 bytes ASCII "12345678901234567890"
    final secretBytes = Uint8List.fromList(utf8.encode('12345678901234567890'));

    final expectedValues = <int, String>{
      0: '755224',
      1: '287082',
      2: '359152',
      3: '969429',
      4: '338314',
      5: '254676',
      6: '287922',
      7: '162583',
      8: '399871',
      9: '520489',
    };

    group('RFC 4226 Appendix D test vectors (counters 0-9)', () {
      for (final entry in expectedValues.entries) {
        test('counter ${entry.key} -> ${entry.value}', () {
          final code = hotp(
            secretBytes,
            entry.key,
            digits: 6,
            algorithm: OtpAlgorithm.sha1,
          );
          expect(code, equals(entry.value));

          // Also test Hotp.generate helper
          final codeFromClass = Hotp.generate(
            secret: secretBytes,
            counter: entry.key,
            digits: 6,
            algorithm: OtpAlgorithm.sha1,
          );
          expect(codeFromClass, equals(entry.value));
        });
      }
    });

    group('Digits validation and formatting', () {
      test('7 digits output', () {
        final code7 = hotp(secretBytes, 0, digits: 7);
        expect(code7.length, equals(7));
        expect(code7, equals('4755224'));
      });

      test('8 digits output', () {
        final code8 = hotp(secretBytes, 0, digits: 8);
        expect(code8.length, equals(8));
        expect(code8, equals('84755224'));
      });

      test('padding with leading zeros', () {
        // Test with arbitrary key that yields leading zeroes
        final zeroKey = Uint8List(20);
        final code = hotp(zeroKey, 0, digits: 6);
        expect(code.length, equals(6));
        expect(int.tryParse(code), isNotNull);
      });

      test('digits < 6 throws ArgumentError', () {
        expect(() => hotp(secretBytes, 0, digits: 5), throwsArgumentError);
      });

      test('digits > 8 throws ArgumentError', () {
        expect(() => hotp(secretBytes, 0, digits: 9), throwsArgumentError);
      });
    });

    group('Counter validation', () {
      test('negative counter throws ArgumentError', () {
        expect(() => hotp(secretBytes, -1), throwsArgumentError);
      });

      test('large counter works (64-bit int)', () {
        final code = hotp(secretBytes, 0x7FFFFFFFFFFFFFFF, digits: 6);
        expect(code.length, equals(6));
      });
    });

    group('Algorithm support', () {
      test('SHA256 generates valid 6-digit code', () {
        final code = hotp(secretBytes, 0, algorithm: OtpAlgorithm.sha256);
        expect(code.length, equals(6));
      });

      test('SHA512 generates valid 6-digit code', () {
        final code = hotp(secretBytes, 0, algorithm: OtpAlgorithm.sha512);
        expect(code.length, equals(6));
      });
    });
  });
}
