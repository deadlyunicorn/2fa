/// Supported hashing algorithms for OTP generation.
enum OtpAlgorithm {
  sha1('SHA1'),
  sha256('SHA256'),
  sha512('SHA512');

  const OtpAlgorithm(this.nameValue);

  /// String representation in JSON and URI query parameters.
  final String nameValue;

  /// Parses a string into an [OtpAlgorithm], case-insensitively.
  ///
  /// Supports values like 'SHA1', 'SHA-1', 'sha256', etc.
  /// Throws [FormatException] if [value] is not a recognized OTP algorithm.
  static OtpAlgorithm fromString(String value) {
    switch (value.trim().toUpperCase()) {
      case 'SHA1':
      case 'SHA-1':
        return OtpAlgorithm.sha1;
      case 'SHA256':
      case 'SHA-256':
        return OtpAlgorithm.sha256;
      case 'SHA512':
      case 'SHA-512':
        return OtpAlgorithm.sha512;
      default:
        throw FormatException('Unsupported OTP algorithm: "$value"');
    }
  }

  /// Attempts to parse a string into an [OtpAlgorithm], returning `null` if invalid.
  static OtpAlgorithm? tryParse(String? value) {
    if (value == null) return null;
    switch (value.trim().toUpperCase()) {
      case 'SHA1':
      case 'SHA-1':
        return OtpAlgorithm.sha1;
      case 'SHA256':
      case 'SHA-256':
        return OtpAlgorithm.sha256;
      case 'SHA512':
      case 'SHA-512':
        return OtpAlgorithm.sha512;
      default:
        return null;
    }
  }

  /// Converts this [OtpAlgorithm] to JSON string representation.
  String toJson() => nameValue;
}
