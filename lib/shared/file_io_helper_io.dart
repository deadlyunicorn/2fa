import 'dart:io';

import 'package:flutter/foundation.dart';

/// Reads file bytes directly from a local filesystem path on `dart:io` platforms.
Future<Uint8List?> readFileFromPath(String path) async {
  try {
    return await File(path).readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Ensures bytes are flushed to the output file on desktop platforms (§7.1 #11).
Future<void> writeDesktopBytesIfEmpty(Uri outputUri, Uint8List bytes) async {
  try {
    final String outputPath = outputUri.isScheme('file')
        ? outputUri.toFilePath()
        : outputUri.path;
    if (outputPath.isNotEmpty) {
      final isDesktop =
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS;
      final file = File(outputPath);
      if (isDesktop || !file.existsSync() || file.lengthSync() == 0) {
        await file.writeAsBytes(bytes, flush: true);
      }
    }
  } catch (_) {
    // In case path cannot be written directly on mobile where plugin already handled it.
  }
}
