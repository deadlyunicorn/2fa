import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/platform_caps.dart';
import '../../core/vault/vault_errors.dart';
import '../../core/vault/vault_merge.dart';
import '../../data/vault_controller.dart';
import '../../shared/auto_lock_service.dart';
import '../../shared/file_picker_service.dart';
import '../../shared/widgets/busy_overlay.dart';
import '../../shared/widgets/password_prompt_dialog.dart';
import '../../shared/widgets/responsive_wrapper.dart';

/// Screen for exporting encrypted vault and importing/merging external vaults (§1.1 #4–#5, §6.4, §7.1 #11, §9 M8).
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _isBusy = false;
  String _busyMessage = '';

  Future<void> _exportVault() async {
    setState(() {
      _isBusy = true;
      _busyMessage = 'Exporting encrypted vault...';
    });

    try {
      final bytes = await ref
          .read(vaultControllerProvider.notifier)
          .exportBytes();
      final defaultFileName = generateVaultBackupFileName();
      final saveFile = ref.read(saveVaultFileProvider);
      final saved = await ref
          .read(autoLockSuppressProvider.notifier)
          .runSuppressed(
            () => saveFile(fileName: defaultFileName, bytes: bytes),
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vault exported successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export vault: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _importAndMergeVault() async {
    final pickFile = ref.read(filePickerProvider);
    final bytes = await ref
        .read(autoLockSuppressProvider.notifier)
        .runSuppressed(() => pickFile());
    if (bytes == null || !mounted) return;

    final password = await PasswordPromptDialog.show(
      context,
      title: 'Unlock Imported Vault',
      message: 'Enter the password for the selected vault file to merge its contents:',
      confirmLabel: 'Import & Merge',
    );
    if (password == null || !mounted) return;

    setState(() {
      _isBusy = true;
      _busyMessage = isWeb
          ? 'Deriving encryption key in browser (may take a few seconds)...'
          : 'Decrypting and merging vault...';
    });

    try {
      final report = await ref
          .read(vaultControllerProvider.notifier)
          .importAndMerge(bytes, password);

      if (!mounted) return;
      setState(() => _isBusy = false);

      await showDialog<void>(
        context: context,
        builder: (ctx) => MergeReportDialog(report: report),
      );
    } on VaultException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userFacingMessage),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to import vault: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: BusyOverlay(
        isBusy: _isBusy,
        message: _busyMessage,
        child: ResponsiveContentWrapper(
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: <Widget>[
              if (isWeb) ...<Widget>[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Browser storage can be cleared by your browser or in private browsing mode. Export regular backups to keep your codes safe.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Export Encrypted Vault Card
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.file_upload_outlined,
                            color: theme.colorScheme.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Export Encrypted Vault',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'The file is encrypted with your current master password. Keep both safe.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _isBusy ? null : _exportVault,
                        icon: const Icon(Icons.download),
                        label: const Text('Export Vault'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Import Vault (Merge) Card
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.merge_type,
                            color: theme.colorScheme.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Import Vault (Merge)',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Entries and groups from the selected .2favault file will be merged into your current vault without overwriting existing accounts.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _isBusy ? null : _importAndMergeVault,
                        icon: const Icon(Icons.file_download_outlined),
                        label: const Text('Import & Merge Vault'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog presenting the result of merging an imported vault (§6.4 #5, §7.1 #11).
class MergeReportDialog extends StatelessWidget {
  const MergeReportDialog({super.key, required this.report});

  final MergeReport report;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Summary'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _MergeReportRow(
              icon: Icons.add_circle_outline,
              label: 'Accounts added',
              value: report.added.toString(),
            ),
            const SizedBox(height: 8),
            _MergeReportRow(
              icon: Icons.content_copy,
              label: 'Duplicates skipped',
              value: report.skippedDuplicates.toString(),
            ),
            const SizedBox(height: 8),
            _MergeReportRow(
              icon: Icons.update,
              label: 'HOTP counters updated',
              value: report.updated.toString(),
            ),
            const SizedBox(height: 8),
            _MergeReportRow(
              icon: Icons.create_new_folder_outlined,
              label: 'Groups created',
              value: report.groupsCreated.toString(),
            ),
            const SizedBox(height: 8),
            _MergeReportRow(
              icon: Icons.warning_amber_outlined,
              label: 'Invalid entries skipped',
              value: report.invalid.toString(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class _MergeReportRow extends StatelessWidget {
  const _MergeReportRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text('$label: $value', style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}
