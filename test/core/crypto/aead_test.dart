import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/crypto/aead.dart';
import 'package:offline2fa/core/crypto/secure_bytes.dart';
import 'package:offline2fa/core/vault/vault_errors.dart';

void main() {
  group('AeadCipher', () {
    late Uint8List key;
    late Uint8List nonce;
    late Uint8List aad;
    late Uint8List plaintext;

    setUp(() {
      key = randomBytes(32);
      nonce = randomBytes(12);
      aad = Uint8List.fromList(
        utf8.encode('header-aad-data-47-bytes-exact-length-pad!'),
      );
      plaintext = Uint8List.fromList(
        utf8.encode('{"sample":"secret-data-payload"}'),
      );
    });

    test('encrypts and decrypts round-trip correctly', () async {
      final ciphertextWithTag = await AeadCipher.encrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      // Ciphertext length must be plaintext length + 16-byte GCM tag
      expect(ciphertextWithTag.length, equals(plaintext.length + 16));

      final decrypted = await AeadCipher.decrypt(
        ciphertextWithTag: ciphertextWithTag,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      expect(constantTimeEquals(decrypted, plaintext), isTrue);
    });

    test('round-trip works for empty plaintext', () async {
      final emptyPlaintext = Uint8List(0);
      final ciphertextWithTag = await AeadCipher.encrypt(
        plaintext: emptyPlaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      expect(ciphertextWithTag.length, equals(16)); // tag only

      final decrypted = await AeadCipher.decrypt(
        ciphertextWithTag: ciphertextWithTag,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      expect(decrypted.length, equals(0));
    });

    test('decryption fails with wrong key', () async {
      final ciphertextWithTag = await AeadCipher.encrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      final wrongKey = Uint8List.fromList(key);
      wrongKey[0] ^= 0x01;

      expect(
        () => AeadCipher.decrypt(
          ciphertextWithTag: ciphertextWithTag,
          key: wrongKey,
          nonce: nonce,
          aad: aad,
        ),
        throwsA(isA<WrongPasswordOrCorrupted>()),
      );
    });

    test('decryption fails with wrong nonce', () async {
      final ciphertextWithTag = await AeadCipher.encrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      final wrongNonce = Uint8List.fromList(nonce);
      wrongNonce[0] ^= 0x01;

      expect(
        () => AeadCipher.decrypt(
          ciphertextWithTag: ciphertextWithTag,
          key: key,
          nonce: wrongNonce,
          aad: aad,
        ),
        throwsA(isA<WrongPasswordOrCorrupted>()),
      );
    });

    test('decryption fails with modified AAD', () async {
      final ciphertextWithTag = await AeadCipher.encrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      final modifiedAad = Uint8List.fromList(aad);
      modifiedAad[0] ^= 0x01;

      expect(
        () => AeadCipher.decrypt(
          ciphertextWithTag: ciphertextWithTag,
          key: key,
          nonce: nonce,
          aad: modifiedAad,
        ),
        throwsA(isA<WrongPasswordOrCorrupted>()),
      );
    });

    test('decryption fails with modified ciphertext', () async {
      final ciphertextWithTag = await AeadCipher.encrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      final corrupted = Uint8List.fromList(ciphertextWithTag);
      corrupted[0] ^= 0x01; // flip bit in ciphertext

      expect(
        () => AeadCipher.decrypt(
          ciphertextWithTag: corrupted,
          key: key,
          nonce: nonce,
          aad: aad,
        ),
        throwsA(isA<WrongPasswordOrCorrupted>()),
      );
    });

    test('decryption fails with modified tag', () async {
      final ciphertextWithTag = await AeadCipher.encrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      final corrupted = Uint8List.fromList(ciphertextWithTag);
      corrupted[corrupted.length - 1] ^= 0x01; // flip bit in tag

      expect(
        () => AeadCipher.decrypt(
          ciphertextWithTag: corrupted,
          key: key,
          nonce: nonce,
          aad: aad,
        ),
        throwsA(isA<WrongPasswordOrCorrupted>()),
      );
    });

    test('decryption throws WrongPasswordOrCorrupted when ciphertextWithTag < 16 bytes', () async {
      expect(
        () => AeadCipher.decrypt(
          ciphertextWithTag: Uint8List(15),
          key: key,
          nonce: nonce,
          aad: aad,
        ),
        throwsA(isA<WrongPasswordOrCorrupted>()),
      );
    });

    test('encrypt validates key and nonce lengths', () {
      expect(
        () => AeadCipher.encrypt(
          plaintext: plaintext,
          key: Uint8List(16),
          nonce: nonce,
          aad: aad,
        ),
        throwsArgumentError,
      );

      expect(
        () => AeadCipher.encrypt(
          plaintext: plaintext,
          key: key,
          nonce: Uint8List(8),
          aad: aad,
        ),
        throwsArgumentError,
      );
    });

    test(
      'decrypt validates key and nonce lengths when payload >= 16 bytes',
      () {
        expect(
          () => AeadCipher.decrypt(
            ciphertextWithTag: Uint8List(20),
            key: Uint8List(16),
            nonce: nonce,
            aad: aad,
          ),
          throwsArgumentError,
        );

        expect(
          () => AeadCipher.decrypt(
            ciphertextWithTag: Uint8List(20),
            key: key,
            nonce: Uint8List(8),
            aad: aad,
          ),
          throwsArgumentError,
        );
      },
    );
  });
}
