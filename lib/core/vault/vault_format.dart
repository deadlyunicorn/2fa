import 'dart:typed_data';

/// Vault file format v1 (.2favault, binary, big-endian)
///
/// | Offset | Size | Field           | Value                            |
/// |--------|------|-----------------|----------------------------------|
/// | 0      | 4    | magic           | ASCII 2FAV (0x32 0x46 0x41 0x56) |
/// | 4      | 2    | format version  | 1 (uint16)                       |
/// | 6      | 1    | kdf id          | 1 = Argon2id                     |
/// | 7      | 4    | kdf memory KiB  | uint32                           |
/// | 11     | 4    | kdf iterations  | uint32                           |
/// | 15     | 1    | kdf parallelism | uint8                            |
/// | 16     | 1    | salt length     | 16                               |
/// | 17     | 16   | salt            | random                           |
/// | 33     | 1    | cipher id       | 1 = AES-256-GCM                  |
/// | 34     | 1    | nonce length    | 12                               |
/// | 35     | 12   | nonce           | random per write                 |
/// | 47     | N    | ciphertext || tag| 16-byte GCM tag                 |
///
/// AAD = header bytes [0, 47)
class VaultFormat {
  const VaultFormat._();

  static const List<int> magicBytes = <int>[0x32, 0x46, 0x41, 0x56]; // "2FAV"
  static const int currentVersion = 1;
  static const int kdfArgon2id = 1;
  static const int cipherAes256Gcm = 1;
  static const int headerLength = 47;
  static const int saltLength = 16;
  static const int nonceLength = 12;
  static const int tagLength = 16;
}

/// Parsed header components from a .2favault file.
class VaultHeader {
  const VaultHeader({
    required this.version,
    required this.kdfId,
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    required this.salt,
    required this.cipherId,
    required this.nonce,
  });

  final int version;
  final int kdfId;
  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final Uint8List salt;
  final int cipherId;
  final Uint8List nonce;
}
