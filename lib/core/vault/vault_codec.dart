import 'dart:typed_data';

import 'vault_payload.dart';

/// Encrypts and decrypts .2favault files.
class VaultCodec {
  const VaultCodec();

  static Uint8List encrypt({
    required VaultPayload payload,
    required Uint8List key,
    required Uint8List salt,
  }) {
    throw UnimplementedError('VaultCodec.encrypt will be implemented in M2');
  }

  static VaultPayload decrypt({
    required Uint8List vaultBytes,
    required String password,
  }) {
    throw UnimplementedError('VaultCodec.decrypt will be implemented in M2');
  }
}
