import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../vault/vault_errors.dart';

/// AES-256-GCM authenticated encryption and decryption helpers (§5.2, §5.4).
class AeadCipher {
  const AeadCipher._();

  static final AesGcm _algorithm = AesGcm.with256bits();

  /// Encrypts [plaintext] using AES-256-GCM with [key], [nonce], and authenticated additional data [aad].
  ///
  /// Returns `ciphertext || 16-byte GCM tag`.
  static Future<Uint8List> encrypt({
    required Uint8List plaintext,
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
  }) async {
    if (key.length != 32) {
      throw ArgumentError.value(
        key.length,
        'key.length',
        'AES-256 key must be 32 bytes',
      );
    }
    if (nonce.length != 12) {
      throw ArgumentError.value(
        nonce.length,
        'nonce.length',
        'AES-GCM nonce must be 12 bytes',
      );
    }

    final secretBox = await _algorithm.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );

    final cipherText = secretBox.cipherText;
    final macBytes = secretBox.mac.bytes;
    final result = Uint8List(cipherText.length + macBytes.length);
    result.setRange(0, cipherText.length, cipherText);
    result.setRange(cipherText.length, result.length, macBytes);
    return result;
  }

  /// Decrypts [ciphertextWithTag] (`ciphertext || 16-byte GCM tag`) using [key], [nonce], and [aad].
  ///
  /// Throws [WrongPasswordOrCorrupted] if authentication fails, data is corrupted,
  /// or [ciphertextWithTag] is shorter than 16 bytes.
  static Future<Uint8List> decrypt({
    required Uint8List ciphertextWithTag,
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
  }) async {
    if (ciphertextWithTag.length < 16) {
      throw const WrongPasswordOrCorrupted();
    }
    if (key.length != 32) {
      throw ArgumentError.value(
        key.length,
        'key.length',
        'AES-256 key must be 32 bytes',
      );
    }
    if (nonce.length != 12) {
      throw ArgumentError.value(
        nonce.length,
        'nonce.length',
        'AES-GCM nonce must be 12 bytes',
      );
    }

    final cipherTextLength = ciphertextWithTag.length - 16;
    final cipherText = ciphertextWithTag.sublist(0, cipherTextLength);
    final macBytes = ciphertextWithTag.sublist(cipherTextLength);

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));

    try {
      final clearText = await _algorithm.decrypt(
        secretBox,
        secretKey: SecretKey(key),
        aad: aad,
      );
      return Uint8List.fromList(clearText);
    } on SecretBoxAuthenticationError {
      throw const WrongPasswordOrCorrupted();
    } catch (_) {
      throw const WrongPasswordOrCorrupted();
    }
  }
}
