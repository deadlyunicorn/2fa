import 'dart:convert';
import 'dart:typed_data';

import '../crypto/aead.dart';
import '../crypto/kdf.dart';
import '../crypto/secure_bytes.dart';
import 'vault_errors.dart';
import 'vault_format.dart';
import 'vault_payload.dart';

/// Encrypts and decrypts .2favault files (§5.2, §5.4).
class VaultCodec {
  const VaultCodec._();

  /// Encrypts [payload] using an already-derived 32-byte [key], [salt], and [kdfParams].
  ///
  /// Uses a fresh 12-byte random nonce from [Random.secure] if [nonce] is not provided.
  /// Authenticates the 47-byte header as AAD.
  /// Returns `header (47 bytes) || ciphertext || GCM tag (16 bytes)`.
  static Future<Uint8List> encryptWithKey({
    required VaultPayload payload,
    required Uint8List key,
    required Uint8List salt,
    required KdfParams kdfParams,
    Uint8List? nonce,
  }) async {
    final effectiveNonce = nonce ?? randomBytes(VaultFormat.nonceLength);

    final header = VaultHeader.fromKdfParams(
      kdfParams: kdfParams,
      salt: salt,
      nonce: effectiveNonce,
    );
    final headerBytes = header.toBytes();

    final jsonString = jsonEncode(payload.toJson());
    final plaintext = Uint8List.fromList(utf8.encode(jsonString));

    final Uint8List ciphertextWithTag;
    try {
      ciphertextWithTag = await AeadCipher.encrypt(
        plaintext: plaintext,
        key: key,
        nonce: effectiveNonce,
        aad: headerBytes,
      );
    } finally {
      zeroBytes(plaintext);
    }

    final result = Uint8List(headerBytes.length + ciphertextWithTag.length);
    result.setRange(0, headerBytes.length, headerBytes);
    result.setRange(headerBytes.length, result.length, ciphertextWithTag);
    return result;
  }

  /// Encrypts [payload] from a plaintext [password], generating a fresh 16-byte salt
  /// (or using [salt] if provided), deriving a 32-byte key via [deriveKey], and encrypting.
  ///
  /// Returns record containing the final vault bytes, derived key, and salt.
  static Future<({Uint8List bytes, Uint8List key, Uint8List salt})>
  encryptWithPassword({
    required VaultPayload payload,
    required String password,
    KdfParams kdfParams = KdfParams.production,
    Uint8List? salt,
    Uint8List? nonce,
  }) async {
    final effectiveSalt = salt ?? randomBytes(VaultFormat.saltLength);
    final key = await deriveKey(password, effectiveSalt, params: kdfParams);

    final bytes = await encryptWithKey(
      payload: payload,
      key: key,
      salt: effectiveSalt,
      kdfParams: kdfParams,
      nonce: nonce,
    );

    return (bytes: bytes, key: key, salt: effectiveSalt);
  }

  /// Decrypts a vault file given an already-derived 32-byte [key].
  ///
  /// Authenticates the header and ciphertext with AES-256-GCM.
  /// Throws [VaultException] subclasses on any validation, decryption, or decoding error.
  static Future<VaultPayload> decryptWithKey({
    required Uint8List bytes,
    required Uint8List key,
  }) async {
    final header = VaultHeader.deserialize(bytes);
    final headerBytes = bytes.sublist(0, VaultFormat.headerLength);
    final ciphertextWithTag = bytes.sublist(VaultFormat.headerLength);

    final plaintext = await AeadCipher.decrypt(
      ciphertextWithTag: ciphertextWithTag,
      key: key,
      nonce: header.nonce,
      aad: headerBytes,
    );

    try {
      final String jsonString;
      try {
        jsonString = utf8.decode(plaintext);
      } catch (_) {
        throw const InvalidPayload('Decrypted payload is not valid UTF-8');
      }

      final Object? decoded;
      try {
        decoded = jsonDecode(jsonString);
      } catch (_) {
        throw const InvalidPayload('Decrypted payload is not valid JSON');
      }

      if (decoded is! Map<String, dynamic>) {
        throw const InvalidPayload(
          'Decrypted payload is not a valid JSON object',
        );
      }

      return VaultPayload.fromJson(decoded);
    } finally {
      zeroBytes(plaintext);
    }
  }

  /// Decrypts a vault file using [password].
  ///
  /// Reads KDF parameters and salt from the header, derives the master key via [deriveKey],
  /// and decrypts the payload.
  ///
  /// Returns record containing the payload, derived key, salt, and parsed KdfParams.
  static Future<
    ({VaultPayload payload, Uint8List key, Uint8List salt, KdfParams kdfParams})
  >
  decryptWithPassword({
    required Uint8List bytes,
    required String password,
  }) async {
    final header = VaultHeader.deserialize(bytes);
    final kdfParams = header.toKdfParams();
    final key = await deriveKey(password, header.salt, params: kdfParams);

    try {
      final payload = await decryptWithKey(bytes: bytes, key: key);

      return (
        payload: payload,
        key: key,
        salt: header.salt,
        kdfParams: kdfParams,
      );
    } catch (_) {
      zeroBytes(key);
      rethrow;
    }
  }
}
