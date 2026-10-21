import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/platform_caps.dart';
import '../../shared/widgets/responsive_wrapper.dart';
import 'manual_entry_screen.dart';

export 'manual_entry_screen.dart';

/// Screen offering account addition via camera, image QR, or manual entry (§7.1 #4).
class AddHubScreen extends StatelessWidget {
  const AddHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Image QR import is coming in M6'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
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
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Image QR loading is coming in M6'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
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

/// Placeholder screen for camera QR scanning (§7.1 #6, M6).
class ScanQrScreen extends StatelessWidget {
  const ScanQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: const Center(
        child: Text('Camera QR scanner will be implemented in M6'),
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
