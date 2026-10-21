import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/crypto/kdf.dart';
import 'package:offline2fa/core/crypto/secure_bytes.dart';

void main() {
  group('KdfParams', () {
    test('default constructor matches production parameters', () {
      const params = KdfParams();
      expect(params.memoryKiB, equals(65536));
      expect(params.iterations, equals(3));
      expect(params.parallelism, equals(1));
      expect(params.saltLength, equals(16));
      expect(params.keyLength, equals(32));
      expect(params, equals(KdfParams.production));
    });

    test('owaspBaseline parameters match specification', () {
      expect(KdfParams.owaspBaseline.memoryKiB, equals(19456));
      expect(KdfParams.owaspBaseline.iterations, equals(2));
      expect(KdfParams.owaspBaseline.parallelism, equals(1));
      expect(KdfParams.owaspBaseline.saltLength, equals(16));
      expect(KdfParams.owaspBaseline.keyLength, equals(32));
    });

    test('webDefault parameters match specification', () {
      expect(KdfParams.webDefault.memoryKiB, equals(4096));
      expect(KdfParams.webDefault.iterations, equals(1));
      expect(KdfParams.webDefault.parallelism, equals(1));
      expect(KdfParams.webDefault.saltLength, equals(16));
      expect(KdfParams.webDefault.keyLength, equals(32));
    });

    test('testFast parameters match specification', () {
      expect(KdfParams.testFast.memoryKiB, equals(1024));
      expect(KdfParams.testFast.iterations, equals(1));
      expect(KdfParams.testFast.parallelism, equals(1));
      expect(KdfParams.testFast.saltLength, equals(16));
      expect(KdfParams.testFast.keyLength, equals(32));
    });

    test('copyWith updates properties correctly', () {
      final modified = KdfParams.testFast.copyWith(
        memoryKiB: 2048,
        iterations: 2,
      );
      expect(modified.memoryKiB, equals(2048));
      expect(modified.iterations, equals(2));
      expect(modified.parallelism, equals(1));
    });

    test('equality and hashCode work as expected', () {
      const a = KdfParams(memoryKiB: 2048, iterations: 2);
      const b = KdfParams(memoryKiB: 2048, iterations: 2);
      const c = KdfParams(memoryKiB: 4096, iterations: 2);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('2048KiB'));
    });
  });

  group('Argon2id Key Derivation', () {
    test('derives known cross-checked Argon2id test vector', () {
      // Known vector for:
      // password: "password"
      // salt: "somesalt" (8 bytes)
      // m: 16 KiB, t: 2, p: 1, keyLength: 32
      // Output: 058202c0723cd88c24408ccac1cbf828dee63bcf3843a150ea364a1e0b4e1ff8
      const customParams = KdfParams(
        memoryKiB: 16,
        iterations: 2,
        parallelism: 1,
        saltLength: 8,
        keyLength: 32,
      );

      final salt = Uint8List.fromList(utf8.encode('somesalt'));
      final key = deriveKeySync('password', salt, params: customParams);

      const expectedHex =
          '058202c0723cd88c24408ccac1cbf828dee63bcf3843a150ea364a1e0b4e1ff8';
      final actualHex = key
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(actualHex, equals(expectedHex));
    });

    test(
      'throws ArgumentError when salt length does not match params.saltLength',
      () {
        final shortSalt = Uint8List(8);
        expect(
          () =>
              deriveKeySync('password', shortSalt, params: KdfParams.testFast),
          throwsArgumentError,
        );
      },
    );

    test('is deterministic for identical inputs', () {
      final salt = Uint8List.fromList(List.filled(16, 7));
      final key1 = deriveKeySync(
        'secret-pass',
        salt,
        params: KdfParams.testFast,
      );
      final key2 = deriveKeySync(
        'secret-pass',
        salt,
        params: KdfParams.testFast,
      );
      expect(constantTimeEquals(key1, key2), isTrue);
    });

    test('different password produces different key', () {
      final salt = Uint8List.fromList(List.filled(16, 7));
      final key1 = deriveKeySync(
        'password-A',
        salt,
        params: KdfParams.testFast,
      );
      final key2 = deriveKeySync(
        'password-B',
        salt,
        params: KdfParams.testFast,
      );
      expect(constantTimeEquals(key1, key2), isFalse);
    });

    test('different salt produces different key', () {
      final salt1 = Uint8List.fromList(List.filled(16, 1));
      final salt2 = Uint8List.fromList(List.filled(16, 2));
      final key1 = deriveKeySync(
        'same-password',
        salt1,
        params: KdfParams.testFast,
      );
      final key2 = deriveKeySync(
        'same-password',
        salt2,
        params: KdfParams.testFast,
      );
      expect(constantTimeEquals(key1, key2), isFalse);
    });

    test(
      'asynchronous deriveKey runs in isolate and matches deriveKeySync',
      () async {
        final salt = Uint8List.fromList(List.generate(16, (i) => i));
        final syncKey = deriveKeySync(
          'isolate-test',
          salt,
          params: KdfParams.testFast,
        );
        final asyncKey = await deriveKey(
          'isolate-test',
          salt,
          params: KdfParams.testFast,
        );
        expect(constantTimeEquals(syncKey, asyncKey), isTrue);
      },
    );

    test('deriveKeyWeb produces identical derived key', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final syncKey = deriveKeySync(
        'web-test',
        salt,
        params: KdfParams.testFast,
      );
      final webKey = await deriveKeyWeb('web-test', salt, KdfParams.testFast);
      expect(constantTimeEquals(syncKey, webKey), isTrue);
    });
  });
}
