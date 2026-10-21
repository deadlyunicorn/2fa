import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'file_io_helper.dart';

/// Function signature for picking a vault file and returning its raw bytes.
typedef FilePickerFn = Future<Uint8List?> Function();

/// Function signature for picking an image file and returning its raw bytes.
typedef ImagePickerFn = Future<Uint8List?> Function();

/// Function signature for saving an encrypted vault file (§7.1 #11).
typedef FileSaverFunction = Future<bool> Function({
  required String fileName,
  required Uint8List bytes,
});

/// Alias for [FileSaverFunction].
typedef FileSaverFn = FileSaverFunction;

/// Formats the default vault export filename as `offline2fa-backup-YYYYMMDD-HHmm.2favault` (§7.1 #11).
String generateVaultBackupFileName([DateTime? now]) {
  final dt = (now ?? DateTime.now()).toLocal();
  final year = dt.year.toString().padLeft(4, '0');
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return 'offline2fa-backup-$year$month$day-$hour$minute.2favault';
}

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
        return await readFileFromPath(file.path!);
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
        return await readFileFromPath(file.path!);
      }
    }
  }
  return null;
}

/// Default implementation for saving a `.2favault` file (§7.1 #11).
Future<bool> saveVaultFile({
  required String fileName,
  required Uint8List bytes,
}) async {
  final Uri? outputUri = await FilePicker.saveFile(
    dialogTitle: 'Export Encrypted Vault',
    fileName: fileName,
    bytes: bytes,
  );
  if (outputUri == null) {
    return false;
  }
  if (!kIsWeb) {
    await writeDesktopBytesIfEmpty(outputUri, bytes);
  }
  return true;
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

/// Global provider for saving vault files (§7.1 #11).
/// Can be overridden in widget tests to inject mock file savers.
final saveVaultFileProvider = Provider<FileSaverFunction>((Ref ref) {
  return saveVaultFile;
});
