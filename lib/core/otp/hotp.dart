import 'dart:typed_data';

import '../models/otp_algorithm.dart';

/// RFC 4226 HMAC-Based One-Time Password algorithm.
class Hotp {
  const Hotp();

  static String generate({
    required Uint8List secret,
    required int counter,
    int digits = 6,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
  }) {
    throw UnimplementedError('Hotp.generate will be implemented in M1');
  }
}
