/// Argon2id key derivation parameters and isolate runner.
class KdfParams {
  const KdfParams({
    this.memoryKiB = 65536,
    this.iterations = 3,
    this.parallelism = 1,
    this.saltLength = 16,
    this.keyLength = 32,
  });

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final int saltLength;
  final int keyLength;
}
