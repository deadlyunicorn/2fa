import 'dart:typed_data';

import '../models/otp_algorithm.dart';

/// RFC 6238 Time-Based One-Time Password algorithm.
class Totp {
  const Totp();

  static String generate({
    required Uint8List secret,
    required int unixSeconds,
    int period = 30,
    int digits = 6,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
  }) {
    throw UnimplementedError('Totp.generate will be implemented in M1');
  }

  static int remainingSeconds(int unixSeconds, {int period = 30}) {
    return period - (unixSeconds % period);
  }
}
