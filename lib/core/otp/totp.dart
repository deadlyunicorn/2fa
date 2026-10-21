import 'dart:typed_data';

import '../models/otp_algorithm.dart';
import 'hotp.dart';

/// Generates a Time-Based One-Time Password (RFC 6238).
///
/// [secretBytes] is the raw secret key.
/// [unixSeconds] is the current Unix epoch time in seconds.
/// [period] is the time step size in seconds, which must be between 1 and 300.
/// [digits] is the length of the OTP code, which must be between 6 and 8.
/// [algorithm] is the HMAC digest algorithm (defaults to SHA-1).
String totp(
  Uint8List secretBytes,
  int unixSeconds, {
  int period = 30,
  int digits = 6,
  OtpAlgorithm algorithm = OtpAlgorithm.sha1,
}) {
  if (unixSeconds < 0) {
    throw ArgumentError.value(
      unixSeconds,
      'unixSeconds',
      'unixSeconds must be non-negative',
    );
  }
  if (period < 1 || period > 300) {
    throw ArgumentError.value(
      period,
      'period',
      'Period must be between 1 and 300',
    );
  }

  final counter = unixSeconds ~/ period;
  return hotp(secretBytes, counter, digits: digits, algorithm: algorithm);
}

/// Internal implementation of remaining seconds in period.
int _calcRemainingSeconds(int unixSeconds, int period) {
  if (period <= 0) {
    throw ArgumentError.value(period, 'period', 'Period must be positive');
  }
  if (unixSeconds < 0) {
    throw ArgumentError.value(
      unixSeconds,
      'unixSeconds',
      'unixSeconds must be non-negative',
    );
  }
  final rem = unixSeconds % period;
  return period - rem;
}

/// Computes the remaining seconds in the current TOTP period.
///
/// Returns a value in the range `1..period`.
int remainingSeconds(int unixSeconds, {int period = 30}) =>
    _calcRemainingSeconds(unixSeconds, period);

/// RFC 6238 Time-Based One-Time Password algorithm helper class.
class Totp {
  const Totp();

  /// Generates a TOTP code.
  static String generate({
    required Uint8List secret,
    required int unixSeconds,
    int period = 30,
    int digits = 6,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
  }) {
    return totp(
      secret,
      unixSeconds,
      period: period,
      digits: digits,
      algorithm: algorithm,
    );
  }

  /// Computes the remaining seconds in the current TOTP period.
  static int remainingSeconds(int unixSeconds, {int period = 30}) =>
      _calcRemainingSeconds(unixSeconds, period);
}
