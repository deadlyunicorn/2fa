import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/otp/otpauth_uri.dart';
import '../../core/platform/platform_caps.dart';
import '../../shared/file_picker_service.dart';
import '../../shared/widgets/responsive_wrapper.dart';
import 'manual_entry_screen.dart';
import 'qr_image_decoder.dart';

export 'manual_entry_screen.dart';
export 'qr_image_decoder.dart';
export 'scan_qr_screen.dart';

/// Helper to pick an image, decode a QR code, and navigate to manual entry screen (§7.1 #7).
Future<void> handleImageQrImport(
  BuildContext context,
  WidgetRef ref, {
  bool replace = false,
}) async {
  final pickImage = ref.read(imagePickerProvider);
  final bytes = await pickImage();
  if (bytes == null || !context.mounted) {
    return;
  }

  final decodeQr = ref.read(qrImageDecoderProvider);
  final qrText = await decodeQr(bytes);
  if (!context.mounted) {
    return;
  }

  if (qrText == null) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No QR code found in image'),
        duration: Duration(seconds: 3),
      ),
    );
    return;
  }

  final trimmed = qrText.trim();
  if (trimmed.toLowerCase().startsWith('otpauth-migration:')) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Not supported yet'),
        duration: Duration(seconds: 3),
      ),
    );
    return;
  }

  try {
    final entry = OtpAuthUri.parse(trimmed);
    if (!context.mounted) return;
    if (replace) {
      context.pushReplacement('/add/manual', extra: entry);
    } else {
      unawaited(context.push('/add/manual', extra: entry));
    }
  } on MigrationNotSupportedException {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Not supported yet'),
        duration: Duration(seconds: 3),
      ),
    );
  } on OtpAuthUriException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Invalid 2FA QR code: ${e.message}'),
        duration: const Duration(seconds: 3),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Invalid 2FA QR code: $e'),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

/// Screen offering account addition via camera, image QR, or manual entry (§7.1 #4).
class AddHubScreen extends ConsumerWidget {
  const AddHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canScan = supportsCamera;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Account')),
      body: ResponsiveContentWrapper(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 8.0),
              Text(
                'Choose how you want to add your 2FA account:',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20.0),
              if (canScan) ...<Widget>[
                FilledButton.icon(
                  onPressed: () => context.push('/add/scan'),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR Code'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                  ),
                ),
                const SizedBox(height: 12.0),
                OutlinedButton.icon(
                  onPressed: () => context.push('/add/manual'),
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('Enter Manually'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                  ),
                ),
                const SizedBox(height: 12.0),
                OutlinedButton.icon(
                  onPressed: () => handleImageQrImport(context, ref),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Import QR from Image'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                  ),
                ),
              ] else ...<Widget>[
                FilledButton.icon(
                  onPressed: () => context.push('/add/manual'),
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('Enter Manually'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                  ),
                ),
                const SizedBox(height: 12.0),
                OutlinedButton.icon(
                  onPressed: () => handleImageQrImport(context, ref),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Load QR from Image File'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Screen for editing an existing OTP entry (§7.1 #5).
class EntryEditScreen extends StatelessWidget {
  const EntryEditScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    return ManualEntryScreen(entryId: id);
  }
}

/// Backward-compatible alias for [AddHubScreen].
typedef AddEntryScreen = AddHubScreen;
