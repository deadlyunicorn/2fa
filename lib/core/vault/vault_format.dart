import 'dart:typed_data';

import '../crypto/kdf.dart';
import 'vault_errors.dart';

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
/// Minimum valid file size = 47 (header) + 16 (GCM tag) = 63 bytes.
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
  static const int minFileLength = headerLength + tagLength; // 63 bytes

  // DoS guard parameter limits (§5.3, §5.4)
  static const int maxMemoryKiB = 1048576; // 1 GiB in KiB
  static const int minMemoryKiB = 1;
  static const int maxIterations = 20;
  static const int minIterations = 1;
  static const int maxParallelism = 16;
  static const int minParallelism = 1;
}

/// Parsed header components from a .2favault file.
class VaultHeader {
  const VaultHeader({
    this.version = VaultFormat.currentVersion,
    this.kdfId = VaultFormat.kdfArgon2id,
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    required this.salt,
    this.cipherId = VaultFormat.cipherAes256Gcm,
    required this.nonce,
  });

  factory VaultHeader.fromKdfParams({
    required KdfParams kdfParams,
    required Uint8List salt,
    required Uint8List nonce,
  }) {
    return VaultHeader(
      memoryKiB: kdfParams.memoryKiB,
      iterations: kdfParams.iterations,
      parallelism: kdfParams.parallelism,
      salt: salt,
      nonce: nonce,
    );
  }

  final int version;
  final int kdfId;
  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final Uint8List salt;
  final int cipherId;
  final Uint8List nonce;

  /// Returns the KdfParams specified by this header.
  KdfParams toKdfParams() => KdfParams(
    memoryKiB: memoryKiB,
    iterations: iterations,
    parallelism: parallelism,
    saltLength: salt.length,
    keyLength: 32,
  );

  /// Serializes this header into exactly 47 bytes per §5.4.
  Uint8List toBytes() {
    if (salt.length != VaultFormat.saltLength) {
      throw ArgumentError.value(
        salt.length,
        'salt.length',
        'Salt must be exactly ${VaultFormat.saltLength} bytes',
      );
    }
    if (nonce.length != VaultFormat.nonceLength) {
      throw ArgumentError.value(
        nonce.length,
        'nonce.length',
        'Nonce must be exactly ${VaultFormat.nonceLength} bytes',
      );
    }

    final out = Uint8List(VaultFormat.headerLength);
    final byteData = ByteData.sublistView(out);

    // 0..3: magic
    out.setRange(0, 4, VaultFormat.magicBytes);
    // 4..5: version
    byteData.setUint16(4, version, Endian.big);
    // 6: kdf id
    byteData.setUint8(6, kdfId);
    // 7..10: kdf memory KiB
    byteData.setUint32(7, memoryKiB, Endian.big);
    // 11..14: kdf iterations
    byteData.setUint32(11, iterations, Endian.big);
    // 15: kdf parallelism
    byteData.setUint8(15, parallelism);
    // 16: salt length
    byteData.setUint8(16, salt.length);
    // 17..32: salt
    out.setRange(17, 33, salt);
    // 33: cipher id
    byteData.setUint8(33, cipherId);
    // 34: nonce length
    byteData.setUint8(34, nonce.length);
    // 35..46: nonce
    out.setRange(35, 47, nonce);

    return out;
  }

  /// Deserializes and validates a header from vault file bytes (§5.4).
  ///
  /// Throws:
  /// - [NotAVaultFile] if length < 63 bytes or magic does not match ASCII `2FAV`.
  /// - [UnsupportedVersion] if version != 1.
  /// - [UnsupportedKdf] if kdfId != 1.
  /// - [UnsupportedCipher] if cipherId != 1.
  /// - [InvalidHeader] if header parameters violate safe bounds or length constraints.
  factory VaultHeader.deserialize(Uint8List bytes) {
    if (bytes.length < VaultFormat.minFileLength) {
      throw NotAVaultFile(
        'Vault file is too short (got ${bytes.length} bytes, minimum is ${VaultFormat.minFileLength} bytes)',
      );
    }

    // Check magic (0..4)
    if (bytes[0] != VaultFormat.magicBytes[0] ||
        bytes[1] != VaultFormat.magicBytes[1] ||
        bytes[2] != VaultFormat.magicBytes[2] ||
        bytes[3] != VaultFormat.magicBytes[3]) {
      throw const NotAVaultFile('Invalid vault magic header');
    }

    final byteData = ByteData.sublistView(bytes);

    final version = byteData.getUint16(4, Endian.big);
    if (version != VaultFormat.currentVersion) {
      throw UnsupportedVersion('Unsupported vault format version: $version');
    }

    final kdfId = byteData.getUint8(6);
    if (kdfId != VaultFormat.kdfArgon2id) {
      throw UnsupportedKdf('Unsupported KDF identifier: $kdfId');
    }

    final memoryKiB = byteData.getUint32(7, Endian.big);
    final iterations = byteData.getUint32(11, Endian.big);
    final parallelism = byteData.getUint8(15);
    final saltLength = byteData.getUint8(16);

    final cipherId = byteData.getUint8(33);
    if (cipherId != VaultFormat.cipherAes256Gcm) {
      throw UnsupportedCipher('Unsupported cipher identifier: $cipherId');
    }

    final nonceLength = byteData.getUint8(34);

    // Validate bounds (§5.3, §5.4 DoS guards)
    if (memoryKiB < VaultFormat.minMemoryKiB ||
        memoryKiB > VaultFormat.maxMemoryKiB) {
      throw InvalidHeader(
        'memoryKiB ($memoryKiB) out of safe bounds (1..${VaultFormat.maxMemoryKiB} KiB)',
      );
    }
    if (iterations < VaultFormat.minIterations ||
        iterations > VaultFormat.maxIterations) {
      throw InvalidHeader(
        'iterations ($iterations) out of safe bounds (1..${VaultFormat.maxIterations})',
      );
    }
    if (parallelism < VaultFormat.minParallelism ||
        parallelism > VaultFormat.maxParallelism) {
      throw InvalidHeader(
        'parallelism ($parallelism) out of safe bounds (1..${VaultFormat.maxParallelism})',
      );
    }
    if (saltLength != VaultFormat.saltLength) {
      throw InvalidHeader(
        'saltLength must be ${VaultFormat.saltLength}, got $saltLength',
      );
    }
    if (nonceLength != VaultFormat.nonceLength) {
      throw InvalidHeader(
        'nonceLength must be ${VaultFormat.nonceLength}, got $nonceLength',
      );
    }

    final salt = bytes.sublist(17, 33);
    final nonce = bytes.sublist(35, 47);

    return VaultHeader(
      version: version,
      kdfId: kdfId,
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      salt: salt,
      cipherId: cipherId,
      nonce: nonce,
    );
  }
}
