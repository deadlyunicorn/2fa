import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/otp_algorithm.dart';

/// Powers of 10 for digits 0 through 8.
const List<int> _powersOf10 = <int>[
  1,
  10,
  100,
  1000,
  10000,
  100000,
  1000000,
  10000000,
  100000000,
];

/// Generates an HMAC-Based One-Time Password (RFC 4226).
///
/// [secretBytes] is the raw secret key.
/// [counter] is the 64-bit moving factor, which must be >= 0.
/// [digits] is the length of the OTP code, which must be between 6 and 8.
/// [algorithm] is the HMAC digest algorithm (defaults to SHA-1).
String hotp(
  Uint8List secretBytes,
  int counter, {
  int digits = 6,
  OtpAlgorithm algorithm = OtpAlgorithm.sha1,
}) {
  if (counter < 0) {
    throw ArgumentError.value(
      counter,
      'counter',
      'Counter must be non-negative',
    );
  }
  if (digits < 6 || digits > 8) {
    throw ArgumentError.value(
      digits,
      'digits',
      'Digits must be between 6 and 8',
    );
  }

  // 8-byte big-endian counter (using setUint32 for dart2js Web compatibility,
  // as ByteData.setUint64 throws UnsupportedError on dart2js)
  final counterBytes = Uint8List(8);
  final byteData = ByteData.sublistView(counterBytes);
  final high = counter ~/ 0x100000000;
  final low = counter & 0xffffffff;
  byteData.setUint32(0, high, Endian.big);
  byteData.setUint32(4, low, Endian.big);

  // HMAC calculation using package:crypto
  final Hash hash;
  switch (algorithm) {
    case OtpAlgorithm.sha1:
      hash = sha1;
    case OtpAlgorithm.sha256:
      hash = sha256;
    case OtpAlgorithm.sha512:
      hash = sha512;
  }

  final hmac = Hmac(hash, secretBytes).convert(counterBytes).bytes;

  // Dynamic truncation (RFC 4226 §5.4)
  final offset = hmac[hmac.length - 1] & 0x0f;
  final binary =
      ((hmac[offset] & 0x7f) << 24) |
      ((hmac[offset + 1] & 0xff) << 16) |
      ((hmac[offset + 2] & 0xff) << 8) |
      (hmac[offset + 3] & 0xff);

  final otp = binary % _powersOf10[digits];
  return otp.toString().padLeft(digits, '0');
}

/// RFC 4226 HMAC-Based One-Time Password algorithm helper class.
class Hotp {
  const Hotp();

  /// Generates an HOTP code.
  static String generate({
    required Uint8List secret,
    required int counter,
    int digits = 6,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
  }) {
    return hotp(secret, counter, digits: digits, algorithm: algorithm);
  }
}
