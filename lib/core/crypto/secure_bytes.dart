import 'dart:typed_data';

/// Utility to safely wipe sensitive byte buffers from memory.
void zeroBytes(Uint8List bytes) {
  bytes.fillRange(0, bytes.length, 0);
}
