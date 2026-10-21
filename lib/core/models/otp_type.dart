/// Supported OTP generation types.
enum OtpType {
  totp('totp'),
  hotp('hotp');

  const OtpType(this.nameValue);

  /// String representation in JSON and URI schemes.
  final String nameValue;

  /// Parses a string into an [OtpType], case-insensitively.
  ///
  /// Throws [FormatException] if [value] is not a recognized OTP type.
  static OtpType fromString(String value) {
    switch (value.trim().toLowerCase()) {
      case 'totp':
        return OtpType.totp;
      case 'hotp':
        return OtpType.hotp;
      default:
        throw FormatException('Unknown OTP type: "$value"');
    }
  }

  /// Attempts to parse a string into an [OtpType], returning `null` if invalid.
  static OtpType? tryParse(String? value) {
    if (value == null) return null;
    switch (value.trim().toLowerCase()) {
      case 'totp':
        return OtpType.totp;
      case 'hotp':
        return OtpType.hotp;
      default:
        return null;
    }
  }

  /// Converts this [OtpType] to JSON string representation.
  String toJson() => nameValue;
}
