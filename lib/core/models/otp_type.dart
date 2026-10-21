/// Supported OTP generation types.
enum OtpType {
  totp('totp'),
  hotp('hotp');

  const OtpType(this.nameValue);
  final String nameValue;

  static OtpType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'hotp':
        return OtpType.hotp;
      case 'totp':
      default:
        return OtpType.totp;
    }
  }
}
