import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hashlib/hashlib.dart';

/// Configuration parameters for Argon2id key derivation.
class KdfParams {
  const KdfParams({
    this.memoryKiB = 65536,
    this.iterations = 3,
    this.parallelism = 1,
    this.saltLength = 16,
    this.keyLength = 32,
  });

  /// Production default (§5.3): Argon2id, m = 64 MiB, t = 3, p = 1.
  static const KdfParams production = KdfParams(
    memoryKiB: 65536,
    iterations: 3,
    parallelism: 1,
    saltLength: 16,
    keyLength: 32,
  );

  /// OWASP recommended baseline: m = 19456 KiB (19 MiB), t = 2, p = 1.
  static const KdfParams owaspBaseline = KdfParams(
    memoryKiB: 19456,
    iterations: 2,
    parallelism: 1,
    saltLength: 16,
    keyLength: 32,
  );

  /// Fast parameters for unit and widget tests (§10): m = 1024 KiB, t = 1, p = 1.
  static const KdfParams testFast = KdfParams(
    memoryKiB: 1024,
    iterations: 1,
    parallelism: 1,
    saltLength: 16,
    keyLength: 32,
  );

  /// Memory size in kibibytes (KiB).
  final int memoryKiB;

  /// Number of iterations / passes.
  final int iterations;

  /// Degree of parallelism (number of lanes / threads).
  final int parallelism;

  /// Expected salt length in bytes.
  final int saltLength;

  /// Derived key length in bytes.
  final int keyLength;

  KdfParams copyWith({
    int? memoryKiB,
    int? iterations,
    int? parallelism,
    int? saltLength,
    int? keyLength,
  }) {
    return KdfParams(
      memoryKiB: memoryKiB ?? this.memoryKiB,
      iterations: iterations ?? this.iterations,
      parallelism: parallelism ?? this.parallelism,
      saltLength: saltLength ?? this.saltLength,
      keyLength: keyLength ?? this.keyLength,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KdfParams &&
          runtimeType == other.runtimeType &&
          memoryKiB == other.memoryKiB &&
          iterations == other.iterations &&
          parallelism == other.parallelism &&
          saltLength == other.saltLength &&
          keyLength == other.keyLength;

  @override
  int get hashCode =>
      Object.hash(memoryKiB, iterations, parallelism, saltLength, keyLength);

  @override
  String toString() =>
      'KdfParams(m: ${memoryKiB}KiB, t: $iterations, p: $parallelism, saltLen: $saltLength, keyLen: $keyLength)';
}

/// Derives a cryptographic key synchronously using Argon2id.
Uint8List deriveKeySync(
  String password,
  Uint8List salt, {
  KdfParams params = KdfParams.production,
}) {
  if (salt.length != params.saltLength) {
    throw ArgumentError.value(
      salt.length,
      'salt.length',
      'Salt length must match params.saltLength (${params.saltLength})',
    );
  }

  final argon2 = Argon2(
    type: Argon2Type.argon2id,
    version: Argon2Version.v13,
    salt: salt,
    parallelism: params.parallelism,
    memorySizeKB: params.memoryKiB,
    iterations: params.iterations,
    hashLength: params.keyLength,
  );

  final digest = argon2.convert(utf8.encode(password));
  return Uint8List.fromList(digest.bytes);
}

/// Derives a cryptographic key asynchronously using Argon2id.
///
/// Runs in a background isolate (§5.3) on native platforms for production parameters to keep UI responsive.
/// On Web, runs synchronously after a brief frame yield (§9 M10) since isolates are not supported in JS.
/// When using [KdfParams.testFast], runs synchronously to support Flutter's fakeAsync test harness.
Future<Uint8List> deriveKey(
  String password,
  Uint8List salt, {
  KdfParams params = KdfParams.production,
}) async {
  if (kIsWeb) {
    await Future<void>.delayed(Duration.zero);
    return deriveKeySync(password, salt, params: params);
  }
  if (params == KdfParams.testFast) {
    return deriveKeySync(password, salt, params: params);
  }
  return Isolate.run(() => deriveKeySync(password, salt, params: params));
}
