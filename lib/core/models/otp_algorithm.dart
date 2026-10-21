/// Supported hashing algorithms for OTP generation.
enum OtpAlgorithm {
  sha1('SHA1'),
  sha256('SHA256'),
  sha512('SHA512');

  const OtpAlgorithm(this.nameValue);
  final String nameValue;

  static OtpAlgorithm fromString(String value) {
    switch (value.toUpperCase()) {
      case 'SHA256':
        return OtpAlgorithm.sha256;
      case 'SHA512':
        return OtpAlgorithm.sha512;
      case 'SHA1':
      default:
        return OtpAlgorithm.sha1;
    }
  }
}
