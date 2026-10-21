import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/vault/vault_errors.dart';
import 'vault_storage.dart';

/// File system implementation of [VaultStorage] with atomic writes and backup (§5.6).
class VaultStorageIo implements VaultStorage {
  VaultStorageIo({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;

  static const String mainFileName = 'vault.2favault';
  static const String backupFileName = 'vault.2favault.bak';
  static const String tempFileName = 'vault.2favault.tmp';

  Future<Directory> _getDirectory() async {
    final Directory dir = await _directoryProvider();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _getFile(String filename) async {
    final Directory dir = await _getDirectory();
    return File(p.join(dir.path, filename));
  }

  @override
  Future<bool> exists() async {
    final Directory dir = await _directoryProvider();
    final file = File(p.join(dir.path, mainFileName));
    return file.exists();
  }

  @override
  Future<bool> backupExists() async {
    final Directory dir = await _directoryProvider();
    final file = File(p.join(dir.path, backupFileName));
    return file.exists();
  }

  @override
  Future<Uint8List> read() async {
    final file = await _getFile(mainFileName);
    if (!await file.exists()) {
      throw const VaultFileNotFound('Main vault file does not exist');
    }
    return file.readAsBytes();
  }

  @override
  Future<Uint8List> readBackup() async {
    final file = await _getFile(backupFileName);
    if (!await file.exists()) {
      throw const VaultFileNotFound('Backup vault file does not exist');
    }
    return file.readAsBytes();
  }

  @override
  Future<void> writeAtomic(Uint8List bytes) async {
    final Directory dir = await _getDirectory();
    final target = File(p.join(dir.path, mainFileName));
    final tmp = File(p.join(dir.path, tempFileName));
    final bak = File(p.join(dir.path, backupFileName));

    // 1. Write tmp file with flush: true
    await tmp.writeAsBytes(bytes, flush: true);

    // 2. If target exists, copy to .bak
    if (await target.exists()) {
      await target.copy(bak.path);
    }

    // 3. Rename tmp to target
    await tmp.rename(target.path);
  }

  @override
  Future<void> restoreBackup() async {
    final target = await _getFile(mainFileName);
    final bak = await _getFile(backupFileName);
    if (!await bak.exists()) {
      throw const VaultFileNotFound('Backup vault file does not exist');
    }
    await bak.copy(target.path);
  }

  @override
  Future<void> delete() async {
    final Directory dir = await _directoryProvider();
    final target = File(p.join(dir.path, mainFileName));
    final bak = File(p.join(dir.path, backupFileName));
    final tmp = File(p.join(dir.path, tempFileName));

    if (await target.exists()) await target.delete();
    if (await bak.exists()) await bak.delete();
    if (await tmp.exists()) await tmp.delete();
  }
}

/// Creates the default I/O implementation of [VaultStorage].
VaultStorage createDefaultVaultStorage() => VaultStorageIo();
