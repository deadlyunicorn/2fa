import 'dart:typed_data';

/// Stub implementation for reading a file from path on platforms without `dart:io`.
Future<Uint8List?> readFileFromPath(String path) async => null;

/// Stub implementation for saving bytes to desktop file path on platforms without `dart:io`.
Future<void> writeDesktopBytesIfEmpty(Uri outputUri, Uint8List bytes) async {}
