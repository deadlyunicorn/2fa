import 'dart:typed_data';

import 'kdf.dart';

/// Fallback implementation of Web KDF for non-Web platforms.
Future<Uint8List> deriveKeyWeb(
  String password,
  Uint8List salt,
  KdfParams params,
) async {
  return deriveKeySync(password, salt, params: params);
}
