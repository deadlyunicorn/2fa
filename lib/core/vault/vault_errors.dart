/// Typed exceptions for vault operations and format decoding.
sealed class VaultException implements Exception {
  const VaultException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class NotAVaultFileException extends VaultException {
  const NotAVaultFileException([super.message = 'Not a valid vault file']);
}

class UnsupportedVersionException extends VaultException {
  const UnsupportedVersionException([
    super.message = 'Unsupported vault version',
  ]);
}

class UnsupportedKdfException extends VaultException {
  const UnsupportedKdfException([super.message = 'Unsupported KDF algorithm']);
}

class UnsupportedCipherException extends VaultException {
  const UnsupportedCipherException([
    super.message = 'Unsupported cipher algorithm',
  ]);
}

class InvalidHeaderException extends VaultException {
  const InvalidHeaderException([
    super.message = 'Invalid vault header parameters',
  ]);
}

class WrongPasswordOrCorruptedFileException extends VaultException {
  const WrongPasswordOrCorruptedFileException([
    super.message = 'Wrong password or corrupted file',
  ]);
}

class InvalidPayloadException extends VaultException {
  const InvalidPayloadException([super.message = 'Invalid vault payload']);
}
