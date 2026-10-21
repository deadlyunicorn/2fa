/// Typed exceptions for vault operations, format decoding, and cryptography.
sealed class VaultException implements Exception {
  const VaultException(this.message);

  final String message;

  /// User-facing error message (§1.2).
  String get userFacingMessage {
    if (this is UnsupportedVersion) {
      return 'Unsupported vault format version';
    }
    return 'Wrong password or corrupted file';
  }

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when a file does not have the .2favault magic header or is too short (< 63 bytes).
class NotAVaultFile extends VaultException {
  const NotAVaultFile([super.message = 'Not a valid vault file']);
}

/// Thrown when the vault format version is unsupported (version != 1).
class UnsupportedVersion extends VaultException {
  const UnsupportedVersion([super.message = 'Unsupported vault version']);
}

/// Thrown when the KDF algorithm identifier is unsupported (kdfId != 1).
class UnsupportedKdf extends VaultException {
  const UnsupportedKdf([super.message = 'Unsupported KDF algorithm']);
}

/// Thrown when the cipher algorithm identifier is unsupported (cipherId != 1).
class UnsupportedCipher extends VaultException {
  const UnsupportedCipher([super.message = 'Unsupported cipher algorithm']);
}

/// Thrown when vault header parameters exceed safe DoS bounds or violate schema lengths.
class InvalidHeader extends VaultException {
  const InvalidHeader([super.message = 'Invalid vault header parameters']);
}

/// Thrown when AES-256-GCM authentication fails (wrong password or corrupted ciphertext/tag/header).
class WrongPasswordOrCorrupted extends VaultException {
  const WrongPasswordOrCorrupted([
    super.message = 'Wrong password or corrupted file',
  ]);
}

/// Thrown when decrypted payload is invalid UTF-8, invalid JSON, or has an unsupported schemaVersion.
class InvalidPayload extends VaultException {
  const InvalidPayload([super.message = 'Invalid vault payload']);
}

/// Thrown when a required vault file or backup file is not found on disk.
class VaultFileNotFound extends VaultException {
  const VaultFileNotFound([super.message = 'Vault file not found']);
}
