import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Function signature for picking a vault file and returning its raw bytes.
typedef FilePickerFn = Future<Uint8List?> Function();

/// Function signature for picking an image file and returning its raw bytes.
typedef ImagePickerFn = Future<Uint8List?> Function();

/// Default implementation for picking a `.2favault` file.
Future<Uint8List?> pickVaultFile() async {
  final PlatformFile? file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: <String>['2favault'],
  );
  if (file != null) {
    try {
      return await file.readAsBytes();
    } catch (_) {
      if (file.path != null) {
        return await File(file.path!).readAsBytes();
      }
    }
  }
  return null;
}

/// Default implementation for picking an image file (§7.1 #7).
Future<Uint8List?> pickImageFile() async {
  final PlatformFile? file = await FilePicker.pickFile(type: FileType.image);
  if (file != null) {
    try {
      return await file.readAsBytes();
    } catch (_) {
      if (file.path != null) {
        return await File(file.path!).readAsBytes();
      }
    }
  }
  return null;
}

/// Global provider for picking vault files (§7.1 #1).
/// Can be overridden in widget tests to inject mock vault files.
final filePickerProvider = Provider<FilePickerFn>((Ref ref) {
  return pickVaultFile;
});

/// Global provider for picking image files (§7.1 #4, #7).
/// Can be overridden in widget tests to inject mock image files.
final imagePickerProvider = Provider<ImagePickerFn>((Ref ref) {
  return pickImageFile;
});
