import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/models/otp_algorithm.dart';
import 'package:offline2fa/core/models/otp_type.dart';
import 'package:offline2fa/core/otp/otpauth_uri.dart';
import 'package:offline2fa/features/add_entry/qr_image_decoder.dart';

void main() {
  group('qr_image_decoder', () {
    late Uint8List validTotpBytes;
    late Uint8List largeHotpBytes;
    late Uint8List noQrBytes;

    setUpAll(() {
      validTotpBytes = File('test/fixtures/qr/valid_totp.png')
          .readAsBytesSync();
      largeHotpBytes = File('test/fixtures/qr/large_hotp.png')
          .readAsBytesSync();
      noQrBytes = File('test/fixtures/qr/no_qr.png').readAsBytesSync();
    });

    test('decodes valid_totp.png correctly and parses into OtpEntry', () async {
      final decoded = await decodeQrFromImageBytes(validTotpBytes);
      expect(decoded, isNotNull);
      expect(
        decoded,
        'otpauth://totp/GitHub:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA1&digits=6&period=30',
      );

      final entry = OtpAuthUri.parse(decoded!);
      expect(entry.type, OtpType.totp);
      expect(entry.issuer, 'GitHub');
      expect(entry.account, 'alice@example.com');
      expect(entry.secret, 'JBSWY3DPEHPK3PXP');
      expect(entry.algorithm, OtpAlgorithm.sha1);
      expect(entry.digits, 6);
      expect(entry.period, 30);
    });

    test('synchronous decode works for valid_totp.png', () {
      final decoded = decodeQrFromImageBytesSync(validTotpBytes);
      expect(decoded, isNotNull);
      expect(decoded, contains('GitHub:alice@example.com'));
    });

    test('decodes large_hotp.png (>1024px) downscaling path', () async {
      final decoded = await decodeQrFromImageBytes(largeHotpBytes);
      expect(decoded, isNotNull);
      expect(
        decoded,
        'otpauth://hotp/Example:bob@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&algorithm=SHA1&digits=6&counter=42',
      );

      final entry = OtpAuthUri.parse(decoded!);
      expect(entry.type, OtpType.hotp);
      expect(entry.issuer, 'Example');
      expect(entry.account, 'bob@example.com');
      expect(entry.secret, 'JBSWY3DPEHPK3PXP');
      expect(entry.counter, 42);
    });

    test('returns null for image with no QR code', () async {
      final decoded = await decodeQrFromImageBytes(noQrBytes);
      expect(decoded, isNull);

      final decodedSync = decodeQrFromImageBytesSync(noQrBytes);
      expect(decodedSync, isNull);
    });

    test('returns null cleanly for empty bytes', () async {
      final decoded = await decodeQrFromImageBytes(Uint8List(0));
      expect(decoded, isNull);

      final decodedSync = decodeQrFromImageBytesSync(Uint8List(0));
      expect(decodedSync, isNull);
    });

    test('returns null cleanly for corrupt/invalid image bytes', () async {
      final corruptBytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9]);
      final decoded = await decodeQrFromImageBytes(corruptBytes);
      expect(decoded, isNull);

      final decodedSync = decodeQrFromImageBytesSync(corruptBytes);
      expect(decodedSync, isNull);
    });
  });
}
