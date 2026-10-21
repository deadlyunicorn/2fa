import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/crypto/kdf.dart';
import '../core/crypto/secure_bytes.dart';
import '../core/vault/vault_codec.dart';
import '../core/vault/vault_errors.dart';
import '../core/vault/vault_format.dart';
import '../core/vault/vault_merge.dart';
import '../core/vault/vault_payload.dart';
import 'vault_storage.dart';

/// Repository managing vault persistence, encryption keys, and cryptographic operations (§4, §5.2, §5.6).
class VaultRepository {
  VaultRepository({
    required this.storage,
    this.defaultKdfParams = kIsWeb
        ? KdfParams.owaspBaseline
        : KdfParams.production,
  });

  final VaultStorage storage;
  final KdfParams defaultKdfParams;

  Uint8List? _derivedKey;
  Uint8List? _salt;
  KdfParams? _kdfParams;

  /// Returns `true` if the vault is currently unlocked with the derived key held in memory.
  bool get isUnlocked => _derivedKey != null;

  /// In-memory derived key (32 bytes), or null when locked.
  Uint8List? get derivedKey => _derivedKey;

  /// In-memory salt (16 bytes), or null when locked.
  Uint8List? get salt => _salt;

  /// KDF parameters associated with current unlocked session.
  KdfParams? get kdfParams => _kdfParams;

  /// Locks the vault, zeroes the derived key buffer, and clears session state (§5.2).
  void lock() {
    if (_derivedKey != null) {
      zeroBytes(_derivedKey!);
      _derivedKey = null;
    }
    _salt = null;
    _kdfParams = null;
  }

  /// Sets active session credentials directly (used in tests or migrations).
  void setSession({
    required Uint8List derivedKey,
    required Uint8List salt,
    KdfParams? kdfParams,
  }) {
    if (_derivedKey != null && !identical(_derivedKey, derivedKey)) {
      zeroBytes(_derivedKey!);
    }
    _derivedKey = derivedKey;
    _salt = salt;
    _kdfParams = kdfParams ?? defaultKdfParams;
  }

  /// Checks whether a primary vault file exists in storage.
  Future<bool> hasVault() => storage.exists();

  /// Checks whether a backup vault file (.bak) exists in storage.
  Future<bool> hasBackup() => storage.backupExists();

  /// Creates a new vault initialized with an empty [VaultPayload], encrypted with [password] (§5.2).
  ///
  /// Derives key from a fresh 16-byte salt using [defaultKdfParams], writes the file atomically,
  /// and retains the derived key in memory.
  Future<VaultPayload> createVault(String password) async {
    final effectiveSalt = randomBytes(VaultFormat.saltLength);
    final key = await deriveKey(
      password,
      effectiveSalt,
      params: defaultKdfParams,
    );
    final payload = VaultPayload.empty();

    final bytes = await VaultCodec.encryptWithKey(
      payload: payload,
      key: key,
      salt: effectiveSalt,
      kdfParams: defaultKdfParams,
    );
    await storage.writeAtomic(bytes);

    if (_derivedKey != null) {
      zeroBytes(_derivedKey!);
    }
    _derivedKey = key;
    _salt = effectiveSalt;
    _kdfParams = defaultKdfParams;

    return payload;
  }

  /// Unlocks an existing vault from storage using [password] (§5.2).
  ///
  /// Reads bytes from storage, decrypts with [password], stores the derived key and salt
  /// in memory, and returns the decrypted [VaultPayload].
  Future<VaultPayload> unlock(String password) async {
    final bytes = await storage.read();
    final result = await VaultCodec.decryptWithPassword(
      bytes: bytes,
      password: password,
    );

    if (_derivedKey != null) {
      zeroBytes(_derivedKey!);
    }
    _derivedKey = result.key;
    _salt = result.salt;
    _kdfParams = result.kdfParams;

    return result.payload;
  }

  /// Restores and unlocks the vault from the backup file (.bak) using [password] (§5.6).
  ///
  /// Verifies that [password] successfully decrypts the backup file before overwriting
  /// the main vault file.
  Future<VaultPayload> restoreFromBackup(String password) async {
    final bytes = await storage.readBackup();
    final result = await VaultCodec.decryptWithPassword(
      bytes: bytes,
      password: password,
    );

    await storage.restoreBackup();

    if (_derivedKey != null) {
      zeroBytes(_derivedKey!);
    }
    _derivedKey = result.key;
    _salt = result.salt;
    _kdfParams = result.kdfParams;

    return result.payload;
  }

  /// Saves [payload] to persistent storage using the active in-memory key and salt (§5.2).
  ///
  /// Generates a fresh random 12-byte nonce without re-running key derivation.
  Future<void> save(VaultPayload payload) async {
    if (!isUnlocked) {
      throw StateError('Cannot save vault: vault is locked');
    }
    final bytes = await VaultCodec.encryptWithKey(
      payload: payload,
      key: _derivedKey!,
      salt: _salt!,
      kdfParams: _kdfParams ?? defaultKdfParams,
    );
    await storage.writeAtomic(bytes);
  }

  /// Verifies [password] against the current active vault session (§7.1 #9).
  ///
  /// Derives a key using [password], active [salt], and active [kdfParams],
  /// and compares it in constant time against [_derivedKey], zeroing the temporary key immediately.
  Future<bool> verifyPassword(String password) async {
    if (!isUnlocked) {
      throw StateError('Cannot verify password: vault is locked');
    }
    final tempKey = await deriveKey(
      password,
      _salt!,
      params: _kdfParams ?? defaultKdfParams,
    );
    try {
      return constantTimeEquals(tempKey, _derivedKey!);
    } finally {
      zeroBytes(tempKey);
    }
  }

  /// Changes the master password (§5.2, §7.1 #12).
  ///
  /// Validates [oldPassword], generates a fresh 16-byte salt, derives a new 32-byte key
  /// using [defaultKdfParams], re-encrypts [currentPayload], atomically writes the file,
  /// zeroes the previous key, and updates in-memory credentials.
  Future<void> changePassword(
    String oldPassword,
    String newPassword,
    VaultPayload currentPayload,
  ) async {
    if (!isUnlocked) {
      throw StateError('Cannot change password: vault is locked');
    }
    final isValid = await verifyPassword(oldPassword);
    if (!isValid) {
      throw const WrongPasswordOrCorrupted('Old password is incorrect');
    }

    final newSalt = randomBytes(VaultFormat.saltLength);
    final newKey = await deriveKey(
      newPassword,
      newSalt,
      params: defaultKdfParams,
    );

    final bytes = await VaultCodec.encryptWithKey(
      payload: currentPayload,
      key: newKey,
      salt: newSalt,
      kdfParams: defaultKdfParams,
    );
    await storage.writeAtomic(bytes);

    final oldKey = _derivedKey;
    _derivedKey = newKey;
    _salt = newSalt;
    _kdfParams = defaultKdfParams;

    if (oldKey != null) {
      zeroBytes(oldKey);
    }
  }

  /// Exports [currentPayload] as encrypted `.2favault` bytes using current key and salt (§5.2).
  ///
  /// Generates a fresh random 12-byte nonce.
  Future<Uint8List> exportBytes(VaultPayload currentPayload) async {
    if (!isUnlocked) {
      throw StateError('Cannot export bytes: vault is locked');
    }
    return VaultCodec.encryptWithKey(
      payload: currentPayload,
      key: _derivedKey!,
      salt: _salt!,
      kdfParams: _kdfParams ?? defaultKdfParams,
    );
  }

  /// Decrypts [importedBytes] with [importedPassword], zeroes the temporary key,
  /// runs [mergeVaults], saves the merged result to storage, and returns the report (§6.4).
  Future<({VaultPayload merged, MergeReport report})> importAndMerge(
    Uint8List importedBytes,
    String importedPassword,
    VaultPayload currentPayload,
  ) async {
    if (!isUnlocked) {
      throw StateError('Cannot import and merge: vault is locked');
    }
    final importedResult = await VaultCodec.decryptWithPassword(
      bytes: importedBytes,
      password: importedPassword,
    );
    zeroBytes(importedResult.key);

    final mergeResult = mergeVaults(
      local: currentPayload,
      imported: importedResult.payload,
    );

    await save(mergeResult.merged);
    return mergeResult;
  }

  /// Imports an external vault file during onboarding as the primary vault (§7.1 #1).
  ///
  /// Verifies decryption with [password], writes the raw bytes atomically as the local vault,
  /// and establishes an unlocked session with the imported credentials.
  Future<VaultPayload> importAsNewVault(
    Uint8List importedBytes,
    String password,
  ) async {
    final result = await VaultCodec.decryptWithPassword(
      bytes: importedBytes,
      password: password,
    );

    await storage.writeAtomic(importedBytes);

    if (_derivedKey != null) {
      zeroBytes(_derivedKey!);
    }
    _derivedKey = result.key;
    _salt = result.salt;
    _kdfParams = result.kdfParams;

    return result.payload;
  }

  /// Locks the vault, zeroes key material in memory, and deletes vault files from storage.
  Future<void> deleteVault() async {
    lock();
    await storage.delete();
  }
}

/// Provider for [VaultStorage].
final vaultStorageProvider = Provider<VaultStorage>((ref) {
  return createDefaultVaultStorage();
});

/// Provider for [VaultRepository].
final vaultRepositoryProvider = Provider<VaultRepository>((ref) {
  final storage = ref.watch(vaultStorageProvider);
  return VaultRepository(storage: storage);
});
