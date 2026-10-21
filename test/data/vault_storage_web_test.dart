import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/vault/vault_errors.dart';
import 'package:offline2fa/data/vault_storage_web.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('VaultStorageWeb', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('initial state reports no vault and no backup', () async {
      final storage = VaultStorageWeb();

      expect(await storage.exists(), isFalse);
      expect(await storage.backupExists(), isFalse);
      expect(() => storage.read(), throwsA(isA<VaultFileNotFound>()));
      expect(() => storage.readBackup(), throwsA(isA<VaultFileNotFound>()));
    });

    test('writeAtomic writes primary vault and read returns bytes', () async {
      final storage = VaultStorageWeb();
      final sampleBytes = Uint8List.fromList([1, 2, 3, 4, 5, 42, 255]);

      await storage.writeAtomic(sampleBytes);

      expect(await storage.exists(), isTrue);
      expect(await storage.backupExists(), isFalse);

      final readBytes = await storage.read();
      expect(readBytes, equals(sampleBytes));
    });

    test('second writeAtomic rotates old vault to backup', () async {
      final storage = VaultStorageWeb();
      final firstBytes = Uint8List.fromList([10, 20, 30]);
      final secondBytes = Uint8List.fromList([40, 50, 60, 70]);

      await storage.writeAtomic(firstBytes);
      expect(await storage.backupExists(), isFalse);

      await storage.writeAtomic(secondBytes);
      expect(await storage.backupExists(), isTrue);

      expect(await storage.read(), equals(secondBytes));
      expect(await storage.readBackup(), equals(firstBytes));
    });

    test('restoreBackup restores backup bytes over primary vault', () async {
      final storage = VaultStorageWeb();
      final firstBytes = Uint8List.fromList([10, 20, 30]);
      final secondBytes = Uint8List.fromList([40, 50, 60, 70]);

      await storage.writeAtomic(firstBytes);
      await storage.writeAtomic(secondBytes);

      expect(await storage.read(), equals(secondBytes));
      expect(await storage.readBackup(), equals(firstBytes));

      await storage.restoreBackup();

      expect(await storage.read(), equals(firstBytes));
      expect(await storage.readBackup(), equals(firstBytes));
    });

    test(
      'restoreBackup throws VaultFileNotFound when no backup exists',
      () async {
        final storage = VaultStorageWeb();
        expect(
          () => storage.restoreBackup(),
          throwsA(isA<VaultFileNotFound>()),
        );

        await storage.writeAtomic(Uint8List.fromList([1, 2, 3]));
        expect(
          () => storage.restoreBackup(),
          throwsA(isA<VaultFileNotFound>()),
        );
      },
    );

    test('delete removes both primary vault and backup', () async {
      final storage = VaultStorageWeb();
      final firstBytes = Uint8List.fromList([1, 2, 3]);
      final secondBytes = Uint8List.fromList([4, 5, 6]);

      await storage.writeAtomic(firstBytes);
      await storage.writeAtomic(secondBytes);

      expect(await storage.exists(), isTrue);
      expect(await storage.backupExists(), isTrue);

      await storage.delete();

      expect(await storage.exists(), isFalse);
      expect(await storage.backupExists(), isFalse);
      expect(() => storage.read(), throwsA(isA<VaultFileNotFound>()));
      expect(() => storage.readBackup(), throwsA(isA<VaultFileNotFound>()));
    });

    test('custom preferences instance can be injected', () async {
      SharedPreferences.setMockInitialValues({
        VaultStorageWeb.mainKey: base64Encode([9, 8, 7]),
        VaultStorageWeb.backupKey: base64Encode([6, 5, 4]),
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = VaultStorageWeb(preferences: prefs);

      expect(await storage.exists(), isTrue);
      expect(await storage.backupExists(), isTrue);
      expect(await storage.read(), equals(Uint8List.fromList([9, 8, 7])));
      expect(await storage.readBackup(), equals(Uint8List.fromList([6, 5, 4])));
    });
  });
}
