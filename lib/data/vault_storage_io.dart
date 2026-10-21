import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'vault_storage.dart';

/// File system implementation of [VaultStorage] with atomic writes and backup.
class VaultStorageIo implements VaultStorage {
  VaultStorageIo({this.customDirectory});

  final String? customDirectory;

  Future<String> _getDirectory() async {
    if (customDirectory != null) return customDirectory!;
    final Directory dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  Future<File> _getFile(String filename) async {
    final String dir = await _getDirectory();
    return File(p.join(dir, filename));
  }

  @override
  Future<bool> exists() async {
    final File file = await _getFile('vault.2favault');
    return file.exists();
  }

  @override
  Future<bool> backupExists() async {
    final File file = await _getFile('vault.2favault.bak');
    return file.exists();
  }

  @override
  Future<Uint8List?> read() async {
    final File file = await _getFile('vault.2favault');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<Uint8List?> readBackup() async {
    final File file = await _getFile('vault.2favault.bak');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> writeAtomic(Uint8List bytes) async {
    final File target = await _getFile('vault.2favault');
    final File tmp = await _getFile('vault.2favault.tmp');
    final File bak = await _getFile('vault.2favault.bak');

    await tmp.writeAsBytes(bytes, flush: true);
    if (await target.exists()) {
      await target.copy(bak.path);
    }
    await tmp.rename(target.path);
  }

  @override
  Future<void> restoreBackup() async {
    final File target = await _getFile('vault.2favault');
    final File bak = await _getFile('vault.2favault.bak');
    if (await bak.exists()) {
      await bak.copy(target.path);
    }
  }

  @override
  Future<void> delete() async {
    final File target = await _getFile('vault.2favault');
    final File bak = await _getFile('vault.2favault.bak');
    final File tmp = await _getFile('vault.2favault.tmp');
    if (await target.exists()) await target.delete();
    if (await bak.exists()) await bak.delete();
    if (await tmp.exists()) await tmp.delete();
  }
}
