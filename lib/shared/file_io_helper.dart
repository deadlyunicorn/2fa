import 'dart:typed_data';

import 'file_io_helper_stub.dart'
    if (dart.library.io) 'file_io_helper_io.dart'
    as impl;

/// Reads raw file bytes from [path] on supported platforms, or returns null.
Future<Uint8List?> readFileFromPath(String path) => impl.readFileFromPath(path);

/// Ensures export bytes are written to disk for desktop dialogs that only yield an output path.
Future<void> writeDesktopBytesIfEmpty(Uri outputUri, Uint8List bytes) =>
    impl.writeDesktopBytesIfEmpty(outputUri, bytes);
