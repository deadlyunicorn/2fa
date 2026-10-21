import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/crypto/secure_bytes.dart';

void main() {
  group('zeroBytes', () {
    test('zeros a non-empty buffer', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 255]);
      zeroBytes(bytes);
      expect(bytes, equals(Uint8List(6)));
    });

    test('handles empty buffer without error', () {
      final bytes = Uint8List(0);
      zeroBytes(bytes);
      expect(bytes.length, equals(0));
    });
  });

  group('constantTimeEquals', () {
    test('returns true for identical references', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(constantTimeEquals(bytes, bytes), isTrue);
    });

    test('returns true for separate buffers with identical contents', () {
      final a = Uint8List.fromList([10, 20, 30, 40]);
      final b = Uint8List.fromList([10, 20, 30, 40]);
      expect(constantTimeEquals(a, b), isTrue);
    });

    test('returns true for empty buffers', () {
      expect(constantTimeEquals(Uint8List(0), Uint8List(0)), isTrue);
    });

    test('returns false for buffers of different lengths', () {
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List.fromList([1, 2, 3, 4]);
      expect(constantTimeEquals(a, b), isFalse);
    });

    test('returns false when difference is at the beginning', () {
      final a = Uint8List.fromList([0, 2, 3, 4]);
      final b = Uint8List.fromList([1, 2, 3, 4]);
      expect(constantTimeEquals(a, b), isFalse);
    });

    test('returns false when difference is in the middle', () {
      final a = Uint8List.fromList([1, 2, 3, 4]);
      final b = Uint8List.fromList([1, 99, 3, 4]);
      expect(constantTimeEquals(a, b), isFalse);
    });

    test('returns false when difference is at the end', () {
      final a = Uint8List.fromList([1, 2, 3, 4]);
      final b = Uint8List.fromList([1, 2, 3, 5]);
      expect(constantTimeEquals(a, b), isFalse);
    });
  });

  group('randomBytes', () {
    test('generates exact number of requested bytes', () {
      expect(randomBytes(0).length, equals(0));
      expect(randomBytes(16).length, equals(16));
      expect(randomBytes(32).length, equals(32));
    });

    test('throws ArgumentError on negative length', () {
      expect(() => randomBytes(-1), throwsArgumentError);
    });

    test('generates different sequences on consecutive calls', () {
      final a = randomBytes(32);
      final b = randomBytes(32);
      expect(constantTimeEquals(a, b), isFalse);
    });
  });
}
