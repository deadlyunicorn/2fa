import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/vault/vault_errors.dart';
import 'package:offline2fa/data/vault_storage_io.dart';
import 'package:path/path.dart' as p;

void main() {
  group('VaultStorageIo', () {
    late Directory tempDir;
    late VaultStorageIo storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vault_storage_test_');
      storage = VaultStorageIo(directoryProvider: () async => tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('initial state: neither main vault nor backup exists', () async {
      expect(await storage.exists(), isFalse);
      expect(await storage.backupExists(), isFalse);
    });

    test(
      'read() and readBackup() throw VaultFileNotFound when files are absent',
      () async {
        expect(() => storage.read(), throwsA(isA<VaultFileNotFound>()));
        expect(() => storage.readBackup(), throwsA(isA<VaultFileNotFound>()));
      },
    );

    test(
      'first writeAtomic creates vault.2favault without backup and cleans .tmp',
      () async {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        await storage.writeAtomic(bytes);

        expect(await storage.exists(), isTrue);
        expect(await storage.backupExists(), isFalse);

        final readBytes = await storage.read();
        expect(readBytes, equals(bytes));

        final tmpFile = File(p.join(tempDir.path, VaultStorageIo.tempFileName));
        expect(await tmpFile.exists(), isFalse);
      },
    );

    test('second writeAtomic updates vault.2favault and preserves previous contents in .bak', () async {
      final firstBytes = Uint8List.fromList([10, 20, 30]);
      final secondBytes = Uint8List.fromList([40, 50, 60, 70]);

      await storage.writeAtomic(firstBytes);
      expect(await storage.backupExists(), isFalse);

      await storage.writeAtomic(secondBytes);
      expect(await storage.exists(), isTrue);
      expect(await storage.backupExists(), isTrue);

      final current = await storage.read();
      final backup = await storage.readBackup();
      expect(current, equals(secondBytes));
      expect(backup, equals(firstBytes));
    });

    test('restoreBackup restores .bak content over main file', () async {
      final firstBytes = Uint8List.fromList([11, 22, 33]);
      final secondBytes = Uint8List.fromList([44, 55, 66]);

      await storage.writeAtomic(firstBytes);
      await storage.writeAtomic(secondBytes);

      expect(await storage.read(), equals(secondBytes));
      expect(await storage.readBackup(), equals(firstBytes));

      await storage.restoreBackup();

      expect(await storage.read(), equals(firstBytes));
      // Backup file still exists after restore
      expect(await storage.backupExists(), isTrue);
      expect(await storage.readBackup(), equals(firstBytes));
    });

    test(
      'restoreBackup throws VaultFileNotFound if no backup exists',
      () async {
        final bytes = Uint8List.fromList([1, 2, 3]);
        await storage.writeAtomic(bytes);

        expect(await storage.backupExists(), isFalse);
        expect(
          () => storage.restoreBackup(),
          throwsA(isA<VaultFileNotFound>()),
        );
      },
    );

    test('delete removes main, backup, and temporary files', () async {
      final firstBytes = Uint8List.fromList([1, 2, 3]);
      final secondBytes = Uint8List.fromList([4, 5, 6]);

      await storage.writeAtomic(firstBytes);
      await storage.writeAtomic(secondBytes);

      // Create a dummy .tmp file to verify delete cleans it too
      final tmpFile = File(p.join(tempDir.path, VaultStorageIo.tempFileName));
      await tmpFile.writeAsBytes([9, 9, 9]);

      expect(await storage.exists(), isTrue);
      expect(await storage.backupExists(), isTrue);
      expect(await tmpFile.exists(), isTrue);

      await storage.delete();

      expect(await storage.exists(), isFalse);
      expect(await storage.backupExists(), isFalse);
      expect(await tmpFile.exists(), isFalse);

      // Subsequent delete on empty state does not throw
      await expectLater(storage.delete(), completes);
    });

    test('writeAtomic auto-creates nested non-existent directory', () async {
      final nestedDir = Directory(p.join(tempDir.path, 'nested', 'support'));
      final nestedStorage = VaultStorageIo(
        directoryProvider: () async => nestedDir,
      );

      expect(await nestedDir.exists(), isFalse);

      final bytes = Uint8List.fromList([1, 3, 5, 7]);
      await nestedStorage.writeAtomic(bytes);

      expect(await nestedDir.exists(), isTrue);
      expect(await nestedStorage.exists(), isTrue);
      expect(await nestedStorage.read(), equals(bytes));
    });
  });
}
