import 'dart:typed_data';

/// RFC 4648 Base32 encoder and decoder without third-party dependencies.
///
/// Encodes without padding (`=`) for compact display and URI generation.
/// Decodes leniently by stripping spaces, hyphens, and padding, uppercasing,
/// and validating character set (`A–Z`, `2–7`).
class Base32Codec {
  const Base32Codec();

  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Validates and normalizes a Base32 string.
  ///
  /// Strips spaces, hyphens, and '=' padding characters, and converts to uppercase.
  /// Throws [FormatException] if the input is empty or contains invalid characters.
  static String normalize(String input) {
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final code = input.codeUnitAt(i);
      // Skip spaces, hyphens, equals
      if (code == 32 || code == 45 || code == 61) {
        continue;
      }
      // Lowercase a-z -> uppercase A-Z
      if (code >= 97 && code <= 122) {
        buffer.writeCharCode(code - 32);
      } else if ((code >= 65 && code <= 90) || (code >= 50 && code <= 55)) {
        buffer.writeCharCode(code);
      } else {
        throw FormatException('Invalid Base32 character: "${input[i]}"');
      }
    }

    final cleaned = buffer.toString();
    if (cleaned.isEmpty) {
      throw const FormatException('Base32 input cannot be empty');
    }

    final rem = cleaned.length % 8;
    if (rem == 1 || rem == 3 || rem == 6) {
      throw FormatException(
        'Invalid Base32 length (${cleaned.length}): cannot form valid byte sequence',
      );
    }

    return cleaned;
  }

  /// Returns `true` if [input] can be successfully normalized and decoded as Base32.
  static bool isValid(String input) {
    try {
      normalize(input);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Decodes a Base32 string into a [Uint8List].
  ///
  /// Leniently strips spaces (` `), hyphens (`-`), and padding (`=`), uppercases
  /// characters, and validates that all characters are in `A–Z` and `2–7`.
  /// Throws [FormatException] on empty input or invalid characters/lengths.
  static Uint8List decode(String input) {
    final cleaned = normalize(input);
    final byteCount = cleaned.length * 5 ~/ 8;
    final result = Uint8List(byteCount);

    var buffer = 0;
    var bitsLeft = 0;
    var outIdx = 0;

    for (var i = 0; i < cleaned.length; i++) {
      final code = cleaned.codeUnitAt(i);
      final int val;
      if (code >= 65 && code <= 90) {
        val = code - 65;
      } else if (code >= 50 && code <= 55) {
        val = code - 50 + 26;
      } else {
        throw FormatException('Invalid Base32 character: "${cleaned[i]}"');
      }

      buffer = (buffer << 5) | val;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        result[outIdx++] = (buffer >> bitsLeft) & 0xff;
      }
    }

    return result;
  }

  /// Encodes [bytes] into an unpadded RFC 4648 Base32 string.
  ///
  /// Empty input encodes to an empty string `""`.
  static String encode(List<int> bytes) {
    if (bytes.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    var bitBuffer = 0;
    var bitsLeft = 0;

    for (final b in bytes) {
      bitBuffer = (bitBuffer << 8) | (b & 0xff);
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        bitsLeft -= 5;
        final index = (bitBuffer >> bitsLeft) & 0x1f;
        buffer.write(_alphabet[index]);
      }
    }

    if (bitsLeft > 0) {
      final index = (bitBuffer << (5 - bitsLeft)) & 0x1f;
      buffer.write(_alphabet[index]);
    }

    return buffer.toString();
  }
}

/// Convenience alias for [Base32Codec].
typedef Base32 = Base32Codec;
