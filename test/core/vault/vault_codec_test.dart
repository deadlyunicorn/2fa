import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/crypto/aead.dart';
import 'package:offline2fa/core/crypto/kdf.dart';
import 'package:offline2fa/core/crypto/secure_bytes.dart';
import 'package:offline2fa/core/models/group.dart';
import 'package:offline2fa/core/models/otp_algorithm.dart';
import 'package:offline2fa/core/models/otp_entry.dart';
import 'package:offline2fa/core/models/otp_type.dart';
import 'package:offline2fa/core/vault/vault_codec.dart';
import 'package:offline2fa/core/vault/vault_errors.dart';
import 'package:offline2fa/core/vault/vault_format.dart';
import 'package:offline2fa/core/vault/vault_payload.dart';

void main() {
  final now = DateTime.utc(2026, 10, 21, 12, 0, 0);

  const sampleGroup = Group(id: 'group-uuid-1', name: 'Work', sortOrder: 0);

  final sampleEntry = OtpEntry(
    id: 'entry-uuid-1',
    type: OtpType.totp,
    issuer: 'GitHub',
    account: 'alice@work.com',
    secret: 'JBSWY3DPEHPK3PXP',
    algorithm: OtpAlgorithm.sha1,
    digits: 6,
    period: 30,
    groupIds: const ['group-uuid-1'],
    note: 'GitHub primary 2FA',
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  );

  final samplePayload = VaultPayload(
    schemaVersion: 1,
    createdAt: now,
    modifiedAt: now,
    groups: [sampleGroup],
    entries: [sampleEntry],
  );

  const testPassword = 'correct horse battery staple';

  group('VaultCodec Round-trip', () {
    test(
      'encryptWithPassword and decryptWithPassword round-trip succeeds',
      () async {
        final encrypted = await VaultCodec.encryptWithPassword(
          payload: samplePayload,
          password: testPassword,
          kdfParams: KdfParams.testFast,
        );

        expect(
          encrypted.bytes.length,
          greaterThanOrEqualTo(VaultFormat.minFileLength),
        );
        expect(encrypted.key.length, equals(32));
        expect(encrypted.salt.length, equals(16));

        final decrypted = await VaultCodec.decryptWithPassword(
          bytes: encrypted.bytes,
          password: testPassword,
        );

        expect(decrypted.payload, equals(samplePayload));
        expect(constantTimeEquals(decrypted.key, encrypted.key), isTrue);
        expect(constantTimeEquals(decrypted.salt, encrypted.salt), isTrue);
        expect(decrypted.kdfParams, equals(KdfParams.testFast));
      },
    );

    test('encryptWithKey and decryptWithKey round-trip succeeds', () async {
      final key = randomBytes(32);
      final salt = randomBytes(16);

      final vaultBytes = await VaultCodec.encryptWithKey(
        payload: samplePayload,
        key: key,
        salt: salt,
        kdfParams: KdfParams.testFast,
      );

      final restoredPayload = await VaultCodec.decryptWithKey(
        bytes: vaultBytes,
        key: key,
      );

      expect(restoredPayload, equals(samplePayload));
    });
  });

  group('VaultCodec Authentication & Tamper Detection', () {
    late Uint8List validVaultBytes;
    late Uint8List validKey;

    setUp(() async {
      final enc = await VaultCodec.encryptWithPassword(
        payload: samplePayload,
        password: testPassword,
        kdfParams: KdfParams.testFast,
      );
      validVaultBytes = enc.bytes;
      validKey = enc.key;
    });

    test(
      'decrypting with wrong password throws WrongPasswordOrCorrupted',
      () async {
        expect(
          () => VaultCodec.decryptWithPassword(
            bytes: validVaultBytes,
            password: 'wrong password',
          ),
          throwsA(isA<WrongPasswordOrCorrupted>()),
        );
      },
    );

    test('decrypting with wrong key throws WrongPasswordOrCorrupted', () async {
      final wrongKey = Uint8List.fromList(validKey);
      wrongKey[0] ^= 0x01;

      expect(
        () => VaultCodec.decryptWithKey(bytes: validVaultBytes, key: wrongKey),
        throwsA(isA<WrongPasswordOrCorrupted>()),
      );
    });

    test(
      'flipped byte in header salt throws WrongPasswordOrCorrupted',
      () async {
        final corrupted = Uint8List.fromList(validVaultBytes);
        corrupted[17] ^= 0x01; // first byte of salt

        expect(
          () => VaultCodec.decryptWithPassword(
            bytes: corrupted,
            password: testPassword,
          ),
          throwsA(isA<WrongPasswordOrCorrupted>()),
        );
      },
    );

    test(
      'flipped byte in header nonce throws WrongPasswordOrCorrupted',
      () async {
        final corrupted = Uint8List.fromList(validVaultBytes);
        corrupted[35] ^= 0x01; // first byte of nonce

        expect(
          () => VaultCodec.decryptWithPassword(
            bytes: corrupted,
            password: testPassword,
          ),
          throwsA(isA<WrongPasswordOrCorrupted>()),
        );
      },
    );

    test('tampered header memoryKiB (still within bounds) fails AAD authentication', () async {
      final corrupted = Uint8List.fromList(validVaultBytes);
      final byteData = ByteData.sublistView(corrupted);
      byteData.setUint32(7, 2048, Endian.big); // valid memoryKiB, but altered

      expect(
        () => VaultCodec.decryptWithPassword(
          bytes: corrupted,
          password: testPassword,
        ),
        throwsA(isA<WrongPasswordOrCorrupted>()),
      );
    });

    test('tampered header iterations (still within bounds) fails AAD authentication', () async {
      final corrupted = Uint8List.fromList(validVaultBytes);
      final byteData = ByteData.sublistView(corrupted);
      byteData.setUint32(11, 2, Endian.big); // valid iterations, but altered

      expect(
        () => VaultCodec.decryptWithPassword(
          bytes: corrupted,
          password: testPassword,
        ),
        throwsA(isA<WrongPasswordOrCorrupted>()),
      );
    });

    test(
      'flipped byte in ciphertext throws WrongPasswordOrCorrupted',
      () async {
        final corrupted = Uint8List.fromList(validVaultBytes);
        // Offset 47 is first byte of ciphertext
        corrupted[47] ^= 0x01;

        expect(
          () => VaultCodec.decryptWithPassword(
            bytes: corrupted,
            password: testPassword,
          ),
          throwsA(isA<WrongPasswordOrCorrupted>()),
        );
      },
    );

    test('flipped byte in GCM tag throws WrongPasswordOrCorrupted', () async {
      final corrupted = Uint8List.fromList(validVaultBytes);
      // Last byte is inside the 16-byte GCM tag
      corrupted[corrupted.length - 1] ^= 0x01;

      expect(
        () => VaultCodec.decryptWithPassword(
          bytes: corrupted,
          password: testPassword,
        ),
        throwsA(isA<WrongPasswordOrCorrupted>()),
      );
    });
  });

  group('VaultCodec Header Validation & Bounds Checking', () {
    late Uint8List validVaultBytes;

    setUp(() async {
      final enc = await VaultCodec.encryptWithPassword(
        payload: samplePayload,
        password: testPassword,
        kdfParams: KdfParams.testFast,
      );
      validVaultBytes = enc.bytes;
    });

    test('invalid magic throws NotAVaultFile', () async {
      final corrupted = Uint8List.fromList(validVaultBytes);
      corrupted[0] = 0x00; // '2' -> 0x00

      expect(
        () => VaultCodec.decryptWithPassword(
          bytes: corrupted,
          password: testPassword,
        ),
        throwsA(isA<NotAVaultFile>()),
      );
    });

    test('unsupported version != 1 throws UnsupportedVersion', () async {
      final corrupted = Uint8List.fromList(validVaultBytes);
      final byteData = ByteData.sublistView(corrupted);
      byteData.setUint16(4, 2, Endian.big); // version 2

      expect(
        () => VaultCodec.decryptWithPassword(
          bytes: corrupted,
          password: testPassword,
        ),
        throwsA(isA<UnsupportedVersion>()),
      );
    });

    test('unsupported kdfId != 1 throws UnsupportedKdf', () async {
      final corrupted = Uint8List.fromList(validVaultBytes);
      corrupted[6] = 2; // kdfId 2

      expect(
        () => VaultCodec.decryptWithPassword(
          bytes: corrupted,
          password: testPassword,
        ),
        throwsA(isA<UnsupportedKdf>()),
      );
    });

    test('unsupported cipherId != 1 throws UnsupportedCipher', () async {
      final corrupted = Uint8List.fromList(validVaultBytes);
      corrupted[33] = 2; // cipherId 2

      expect(
        () => VaultCodec.decryptWithPassword(
          bytes: corrupted,
          password: testPassword,
        ),
        throwsA(isA<UnsupportedCipher>()),
      );
    });

    test(
      'out-of-bounds memoryKiB (0 or > 1 GiB) throws InvalidHeader',
      () async {
        final zeroMemory = Uint8List.fromList(validVaultBytes);
        ByteData.sublistView(zeroMemory).setUint32(7, 0, Endian.big);
        expect(
          () => VaultCodec.decryptWithPassword(
            bytes: zeroMemory,
            password: testPassword,
          ),
          throwsA(isA<InvalidHeader>()),
        );

        final hugeMemory = Uint8List.fromList(validVaultBytes);
        ByteData.sublistView(hugeMemory)
            .setUint32(7, 1048577, Endian.big); // > 1 GiB
        expect(
          () => VaultCodec.decryptWithPassword(
            bytes: hugeMemory,
            password: testPassword,
          ),
          throwsA(isA<InvalidHeader>()),
        );
      },
    );

    test('out-of-bounds iterations (0 or > 20) throws InvalidHeader', () async {
      final zeroIter = Uint8List.fromList(validVaultBytes);
      ByteData.sublistView(zeroIter).setUint32(11, 0, Endian.big);
      expect(
        () => VaultCodec.decryptWithPassword(
          bytes: zeroIter,
          password: testPassword,
        ),
        throwsA(isA<InvalidHeader>()),
      );

      final hugeIter = Uint8List.fromList(validVaultBytes);
      ByteData.sublistView(hugeIter).setUint32(11, 21, Endian.big);
      expect(
        () => VaultCodec.decryptWithPassword(
          bytes: hugeIter,
          password: testPassword,
        ),
        throwsA(isA<InvalidHeader>()),
      );
    });

    test(
      'out-of-bounds parallelism (0 or > 16) throws InvalidHeader',
      () async {
        final zeroParallel = Uint8List.fromList(validVaultBytes);
        zeroParallel[15] = 0;
        expect(
          () => VaultCodec.decryptWithPassword(
            bytes: zeroParallel,
            password: testPassword,
          ),
          throwsA(isA<InvalidHeader>()),
        );

        final hugeParallel = Uint8List.fromList(validVaultBytes);
        hugeParallel[15] = 17;
        expect(
          () => VaultCodec.decryptWithPassword(
            bytes: hugeParallel,
            password: testPassword,
          ),
          throwsA(isA<InvalidHeader>()),
        );
      },
    );

    test('saltLength != 16 throws InvalidHeader', () async {
      final badSaltLen = Uint8List.fromList(validVaultBytes);
      badSaltLen[16] = 32;
      expect(
        () => VaultCodec.decryptWithPassword(
          bytes: badSaltLen,
          password: testPassword,
        ),
        throwsA(isA<InvalidHeader>()),
      );
    });

    test('nonceLength != 12 throws InvalidHeader', () async {
      final badNonceLen = Uint8List.fromList(validVaultBytes);
      badNonceLen[34] = 16;
      expect(
        () => VaultCodec.decryptWithPassword(
          bytes: badNonceLen,
          password: testPassword,
        ),
        throwsA(isA<InvalidHeader>()),
      );
    });

    test('truncated file (< 63 bytes) throws NotAVaultFile', () async {
      expect(
        () => VaultCodec.decryptWithPassword(
          bytes: Uint8List(0),
          password: testPassword,
        ),
        throwsA(isA<NotAVaultFile>()),
      );

      expect(
        () => VaultCodec.decryptWithPassword(
          bytes: Uint8List(46), // < headerLength (47)
          password: testPassword,
        ),
        throwsA(isA<NotAVaultFile>()),
      );

      expect(
        () => VaultCodec.decryptWithPassword(
          bytes: Uint8List(62), // < minFileLength (63)
          password: testPassword,
        ),
        throwsA(isA<NotAVaultFile>()),
      );
    });
  });

  group('VaultCodec Invalid Plaintext Payloads', () {
    test('non-UTF8 or non-JSON plaintext throws InvalidPayload', () async {
      final key = randomBytes(32);
      final salt = randomBytes(16);
      final nonce = randomBytes(12);
      final header = VaultHeader.fromKdfParams(
        kdfParams: KdfParams.testFast,
        salt: salt,
        nonce: nonce,
      );
      final headerBytes = header.toBytes();

      // Encrypt invalid JSON string
      final invalidJson = Uint8List.fromList(
        utf8.encode('this is not valid json!'),
      );
      final cipherTextWithTag = await AeadCipher.encrypt(
        plaintext: invalidJson,
        key: key,
        nonce: nonce,
        aad: headerBytes,
      );

      final vaultBytes = Uint8List(
        headerBytes.length + cipherTextWithTag.length,
      );
      vaultBytes.setRange(0, headerBytes.length, headerBytes);
      vaultBytes.setRange(
        headerBytes.length,
        vaultBytes.length,
        cipherTextWithTag,
      );

      expect(
        () => VaultCodec.decryptWithKey(bytes: vaultBytes, key: key),
        throwsA(isA<InvalidPayload>()),
      );
    });
  });

  group('Golden Test Fixture (test/fixtures/v1_sample.2favault)', () {
    test('reads and decrypts golden v1_sample.2favault with correct horse battery staple', () async {
      final file = File('test/fixtures/v1_sample.2favault');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'v1_sample.2favault fixture must exist on disk',
      );

      final fileBytes = file.readAsBytesSync();
      expect(fileBytes.length, greaterThanOrEqualTo(VaultFormat.minFileLength));

      final decrypted = await VaultCodec.decryptWithPassword(
        bytes: fileBytes,
        password: 'correct horse battery staple',
      );

      final payload = decrypted.payload;
      expect(payload.schemaVersion, equals(1));
      expect(payload.groups.length, equals(2));
      expect(payload.entries.length, equals(2));

      // Verify groups
      final groupWork = payload.groups.firstWhere((g) => g.name == 'Work');
      expect(groupWork.id, equals('00000000-0000-4000-8000-000000000001'));
      expect(groupWork.sortOrder, equals(0));

      final groupPersonal = payload.groups.firstWhere(
        (g) => g.name == 'Personal',
      );
      expect(groupPersonal.id, equals('00000000-0000-4000-8000-000000000002'));
      expect(groupPersonal.sortOrder, equals(1));

      // Verify TOTP entry
      final totp = payload.entries.firstWhere((e) => e.type == OtpType.totp);
      expect(totp.id, equals('10000000-0000-4000-8000-000000000001'));
      expect(totp.issuer, equals('GitHub'));
      expect(totp.account, equals('alice@example.com'));
      expect(totp.secret, equals('JBSWY3DPEHPK3PXP'));
      expect(totp.algorithm, equals(OtpAlgorithm.sha1));
      expect(totp.digits, equals(6));
      expect(totp.period, equals(30));
      expect(totp.groupIds, equals(['00000000-0000-4000-8000-000000000001']));

      // Verify HOTP entry
      final hotp = payload.entries.firstWhere((e) => e.type == OtpType.hotp);
      expect(hotp.id, equals('10000000-0000-4000-8000-000000000002'));
      expect(hotp.issuer, equals('Acme Corp'));
      expect(hotp.account, equals('alice@acme.corp'));
      expect(hotp.secret, equals('KRSXG5CTMVRXEZLU'));
      expect(hotp.algorithm, equals(OtpAlgorithm.sha256));
      expect(hotp.digits, equals(8));
      expect(hotp.counter, equals(42));
      expect(hotp.groupIds, equals(['00000000-0000-4000-8000-000000000002']));
    });

    test('decrypting golden fixture with wrong password fails', () async {
      final file = File('test/fixtures/v1_sample.2favault');
      final fileBytes = file.readAsBytesSync();

      expect(
        () => VaultCodec.decryptWithPassword(
          bytes: fileBytes,
          password: 'wrong-password-here',
        ),
        throwsA(isA<WrongPasswordOrCorrupted>()),
      );
    });
  });
}
