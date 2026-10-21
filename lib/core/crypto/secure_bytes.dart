import 'dart:math';
import 'dart:typed_data';

/// Utility to safely wipe sensitive byte buffers from memory.
void zeroBytes(Uint8List bytes) {
  bytes.fillRange(0, bytes.length, 0);
}

/// Constant-time comparison of two byte sequences to mitigate timing attacks.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result == 0;
}

/// Generates [length] cryptographically secure pseudorandom bytes.
Uint8List randomBytes(int length) {
  if (length < 0) {
    throw ArgumentError.value(length, 'length', 'Length must be non-negative');
  }
  final random = Random.secure();
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}
