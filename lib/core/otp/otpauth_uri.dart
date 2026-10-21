import '../models/otp_entry.dart';

/// Parser and serializer for otpauth:// URIs.
class OtpAuthUri {
  const OtpAuthUri();

  static OtpEntry parse(String uriString) {
    throw UnimplementedError('OtpAuthUri.parse will be implemented in M1');
  }

  static String serialize(OtpEntry entry) {
    throw UnimplementedError('OtpAuthUri.serialize will be implemented in M1');
  }
}
