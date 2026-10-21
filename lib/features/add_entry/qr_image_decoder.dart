import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Pure-Dart QR decoder that extracts QR content from raw image bytes (§7.1 #7, §9 M6).
///
/// Converts [Uint8List] image bytes into luminance data, runs binarization via
/// [HybridBinarizer] / [GlobalHistogramBinarizer], and decodes with [QRCodeReader].
/// If the initial decode fails and dimensions exceed 1024 px, downscales and re-attempts.
String? decodeQrFromImageBytesSync(Uint8List bytes) {
  if (bytes.isEmpty) {
    return null;
  }

  try {
    final image = img.decodeImage(bytes);
    if (image == null) {
      return null;
    }

    // 1. Try the original image
    final originalResult = _decodeQrFromImage(image);
    if (originalResult != null) {
      return originalResult;
    }

    // 2. Downscale if dimensions exceed 1024 px and re-attempt (§7.1 #7)
    if (image.width > 1024 || image.height > 1024) {
      final img.Image resized;
      if (image.width >= image.height) {
        resized = img.copyResize(image, width: 1024);
      } else {
        resized = img.copyResize(image, height: 1024);
      }
      return _decodeQrFromImage(resized);
    }

    return null;
  } catch (_) {
    return null;
  }
}

/// Asynchronous wrapper executing [decodeQrFromImageBytesSync] in a background isolate.
Future<String?> decodeQrFromImageBytes(
  Uint8List bytes, {
  bool runInIsolate = true,
}) async {
  if (bytes.isEmpty) {
    return null;
  }
  if (!runInIsolate) {
    return decodeQrFromImageBytesSync(bytes);
  }
  return Isolate.run(() => decodeQrFromImageBytesSync(bytes));
}

/// Internal helper that attempts multiple binarizer and inversion passes.
String? _decodeQrFromImage(img.Image image) {
  final width = image.width;
  final height = image.height;
  if (width == 0 || height == 0) {
    return null;
  }

  final pixels = Int32List(width * height);
  var index = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = image.getPixel(x, y);
      // Treat transparent or semi-transparent background as white
      if (pixel.a < 128) {
        pixels[index++] = 0xFFFFFFFF;
      } else {
        pixels[index++] =
            (0xFF << 24) |
            (pixel.r.toInt() << 16) |
            (pixel.g.toInt() << 8) |
            pixel.b.toInt();
      }
    }
  }

  final source = RGBLuminanceSource(width, height, pixels);
  final reader = QRCodeReader();
  final hints = DecodeHints()..put(DecodeHintType.tryHarder);

  // Pass 1: Standard HybridBinarizer
  try {
    final result = reader.decode(
      BinaryBitmap(HybridBinarizer(source)),
      hints: hints,
    );
    if (result.text.isNotEmpty) {
      return result.text;
    }
  } catch (_) {}

  // Pass 2: GlobalHistogramBinarizer
  try {
    final result = reader.decode(
      BinaryBitmap(GlobalHistogramBinarizer(source)),
      hints: hints,
    );
    if (result.text.isNotEmpty) {
      return result.text;
    }
  } catch (_) {}

  // Pass 3: Inverted luminance with HybridBinarizer (white QR on dark background)
  try {
    final inverted = InvertedLuminanceSource(source);
    final result = reader.decode(
      BinaryBitmap(HybridBinarizer(inverted)),
      hints: hints,
    );
    if (result.text.isNotEmpty) {
      return result.text;
    }
  } catch (_) {}

  // Pass 4: Inverted luminance with GlobalHistogramBinarizer
  try {
    final inverted = InvertedLuminanceSource(source);
    final result = reader.decode(
      BinaryBitmap(GlobalHistogramBinarizer(inverted)),
      hints: hints,
    );
    if (result.text.isNotEmpty) {
      return result.text;
    }
  } catch (_) {}

  return null;
}

/// Function signature for QR image decoding.
typedef QrImageDecoderFn = Future<String?> Function(Uint8List bytes);

/// Riverpod provider for QR image decoding.
/// Can be overridden in tests to mock image decoding.
final qrImageDecoderProvider = Provider<QrImageDecoderFn>((Ref ref) {
  return decodeQrFromImageBytes;
});
