import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/vault/vault_errors.dart';
import 'vault_storage.dart';

/// Web implementation of [VaultStorage] storing encrypted vault data in browser localStorage
/// via [SharedPreferences] (§4, §8, §9 M10).
class VaultStorageWeb implements VaultStorage {
  VaultStorageWeb({
    this.preferences,
    Future<SharedPreferences> Function()? preferencesProvider,
  }) : _preferencesProvider =
           preferencesProvider ?? SharedPreferences.getInstance;

  final SharedPreferences? preferences;
  final Future<SharedPreferences> Function() _preferencesProvider;

  static const String mainKey = 'offline2fa_web_vault_b64';
  static const String backupKey = 'offline2fa_web_vault_bak_b64';

  Future<SharedPreferences> _getPrefs() async =>
      preferences ?? await _preferencesProvider();

  @override
  Future<bool> exists() async {
    final prefs = await _getPrefs();
    final value = prefs.getString(mainKey);
    return value != null && value.isNotEmpty;
  }

  @override
  Future<bool> backupExists() async {
    final prefs = await _getPrefs();
    final value = prefs.getString(backupKey);
    return value != null && value.isNotEmpty;
  }

  @override
  Future<Uint8List> read() async {
    final prefs = await _getPrefs();
    final value = prefs.getString(mainKey);
    if (value == null || value.isEmpty) {
      throw const VaultFileNotFound('Main vault file does not exist');
    }
    return base64Decode(value);
  }

  @override
  Future<Uint8List> readBackup() async {
    final prefs = await _getPrefs();
    final value = prefs.getString(backupKey);
    if (value == null || value.isEmpty) {
      throw const VaultFileNotFound('Backup vault file does not exist');
    }
    return base64Decode(value);
  }

  @override
  Future<void> writeAtomic(Uint8List bytes) async {
    final prefs = await _getPrefs();
    final current = prefs.getString(mainKey);

    // 1. If existing vault is present, rotate it to backup
    if (current != null && current.isNotEmpty) {
      await prefs.setString(backupKey, current);
    }

    // 2. Write new vault bytes encoded as base64
    final encoded = base64Encode(bytes);
    await prefs.setString(mainKey, encoded);
  }

  @override
  Future<void> restoreBackup() async {
    final prefs = await _getPrefs();
    final backup = prefs.getString(backupKey);
    if (backup == null || backup.isEmpty) {
      throw const VaultFileNotFound('Backup vault file does not exist');
    }
    await prefs.setString(mainKey, backup);
  }

  @override
  Future<void> delete() async {
    final prefs = await _getPrefs();
    await prefs.remove(mainKey);
    await prefs.remove(backupKey);
  }
}

/// Creates the default Web implementation of [VaultStorage].
VaultStorage createDefaultVaultStorage() => VaultStorageWeb();
