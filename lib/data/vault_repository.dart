import 'dart:typed_data';

import '../core/crypto/secure_bytes.dart';
import '../core/vault/vault_payload.dart';
import 'vault_storage.dart';

/// Repository managing vault persistence, key derivation caching, and payload state.
class VaultRepository {
  VaultRepository({required this.storage});

  final VaultStorage storage;

  Uint8List? _derivedKey;
  Uint8List? _salt;

  bool get isUnlocked => _derivedKey != null;

  void lock() {
    if (_derivedKey != null) {
      zeroBytes(_derivedKey!);
      _derivedKey = null;
    }
    _salt = null;
  }

  void setSession({required Uint8List derivedKey, required Uint8List salt}) {
    _derivedKey = derivedKey;
    _salt = salt;
  }

  Uint8List? get derivedKey => _derivedKey;
  Uint8List? get salt => _salt;

  Future<void> save(VaultPayload payload) async {
    throw UnimplementedError('VaultRepository.save will be implemented in M3');
  }
}
