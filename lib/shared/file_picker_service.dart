import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Function signature for picking a vault file and returning its raw bytes.
typedef FilePickerFn = Future<Uint8List?> Function();

/// Global provider for picking vault files (§7.1 #1).
/// Can be overridden in widget tests to inject mock vault files.
final filePickerProvider = Provider<FilePickerFn>((Ref ref) {
  return () async {
    final PlatformFile? file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['2favault'],
    );
    if (file != null) {
      return await file.readAsBytes();
    }
    return null;
  };
});
