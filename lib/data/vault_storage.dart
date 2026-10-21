import 'dart:typed_data';

import 'vault_storage_stub.dart'
    if (dart.library.io) 'vault_storage_io.dart'
    if (dart.library.js_interop) 'vault_storage_web.dart'
    as impl;

/// Interface for persistent storage of encrypted vault data (§5.6).
abstract class VaultStorage {
  /// Checks whether the primary vault file exists.
  Future<bool> exists();

  /// Checks whether the backup vault file (.bak) exists.
  Future<bool> backupExists();

  /// Reads and returns the encrypted bytes from the primary vault file.
  ///
  /// Throws [VaultFileNotFound] if the primary vault file does not exist.
  Future<Uint8List> read();

  /// Reads and returns the encrypted bytes from the backup vault file.
  ///
  /// Throws [VaultFileNotFound] if the backup vault file does not exist.
  Future<Uint8List> readBackup();

  /// Atomically writes [bytes] to the primary vault file.
  ///
  /// Writes to a temporary file, flushes to disk, preserves existing
  /// vault bytes in `.bak`, and moves the temporary file to the primary path.
  Future<void> writeAtomic(Uint8List bytes);

  /// Restores the `.bak` file over the primary vault file.
  ///
  /// Throws [VaultFileNotFound] if no backup file exists.
  Future<void> restoreBackup();

  /// Deletes the primary vault file, backup file, and any temporary file.
  Future<void> delete();
}

/// Creates the platform-appropriate default [VaultStorage] instance (§5.6, §8, §9 M10).
VaultStorage createDefaultVaultStorage() => impl.createDefaultVaultStorage();
