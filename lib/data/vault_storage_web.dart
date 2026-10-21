import 'dart:typed_data';

import 'vault_storage.dart';

/// Web (IndexedDB / LocalStorage) implementation of [VaultStorage] (Phase 3).
class VaultStorageWeb implements VaultStorage {
  @override
  Future<bool> exists() async => false;

  @override
  Future<bool> backupExists() async => false;

  @override
  Future<Uint8List?> read() async => null;

  @override
  Future<Uint8List?> readBackup() async => null;

  @override
  Future<void> writeAtomic(Uint8List bytes) async {
    throw UnimplementedError('VaultStorageWeb will be implemented in Phase 3');
  }

  @override
  Future<void> restoreBackup() async {
    throw UnimplementedError('VaultStorageWeb will be implemented in Phase 3');
  }

  @override
  Future<void> delete() async {
    throw UnimplementedError('VaultStorageWeb will be implemented in Phase 3');
  }
}
