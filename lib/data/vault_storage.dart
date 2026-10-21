import 'dart:typed_data';

/// Interface for persistent storage of encrypted vault data.
abstract class VaultStorage {
  Future<bool> exists();
  Future<bool> backupExists();
  Future<Uint8List?> read();
  Future<Uint8List?> readBackup();
  Future<void> writeAtomic(Uint8List bytes);
  Future<void> restoreBackup();
  Future<void> delete();
}
