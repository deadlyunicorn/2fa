import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/otp_entry.dart';
import '../../core/models/otp_type.dart';
import '../../core/otp/base32.dart';
import '../../core/otp/hotp.dart';
import '../../core/otp/totp.dart';
import '../../data/prefs_repository.dart';
import '../../data/vault_controller.dart';
import '../../shared/clipboard_service.dart';
import '../../shared/widgets/code_text.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/countdown_ring.dart';
import '../../shared/widgets/letter_avatar.dart';
import '../../shared/widgets/responsive_wrapper.dart';

/// Screen displaying full details and live code of a single OTP entry (§7.1 #8).
class EntryDetailsScreen extends ConsumerWidget {
  const EntryDetailsScreen({super.key, required this.id});

  final String id;

  Future<void> _copyCode(
    BuildContext context,
    WidgetRef ref,
    String code,
  ) async {
    final prefs = ref.read(prefsProvider);
    final clipboard = ref.read(clipboardServiceProvider);
    final message = await clipboard.copyCode(
      code,
      clearAfterSeconds: prefs.clipboardClearSeconds,
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteEntry(
    BuildContext context,
    WidgetRef ref,
    OtpEntry entry,
  ) async {
    final accountName = entry.issuer.isNotEmpty ? entry.issuer : entry.account;
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete account',
      message:
          'Are you sure you want to delete "$accountName"? This action cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );

    if (confirmed == true && context.mounted) {
      await ref.read(vaultControllerProvider.notifier).deleteEntry(entry.id);
      if (context.mounted) {
        context.go('/');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final vaultState = ref.watch(vaultControllerProvider);

    if (vaultState is! VaultUnlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account Details')),
        body: const Center(child: Text('Vault is locked')),
      );
    }

    final entryIndex = vaultState.data.entries.indexWhere((e) => e.id == id);
    if (entryIndex == -1) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account Details')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text('Account not found'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to accounts'),
              ),
            ],
          ),
        ),
      );
    }

    final entry = vaultState.data.entries[entryIndex];
    final allGroups = vaultState.data.groups;
    final assignedGroups = allGroups
        .where((g) => entry.groupIds.contains(g.id))
        .toList();

    // OTP calculation
    Uint8List? secretBytes;
    try {
      secretBytes = Base32Codec.decode(entry.secret);
    } catch (_) {
      secretBytes = null;
    }

    final String currentCode;
    int remSeconds = 0;

    if (secretBytes == null) {
      currentCode = '------';
    } else if (entry.type == OtpType.totp) {
      final epochSeconds =
          ref.watch(tickerProvider).value ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000);
      remSeconds = remainingSeconds(epochSeconds, period: entry.period);
      currentCode = totp(
        secretBytes,
        epochSeconds,
        period: entry.period,
        digits: entry.digits,
        algorithm: entry.algorithm,
      );
    } else {
      currentCode = hotp(
        secretBytes,
        entry.counter,
        digits: entry.digits,
        algorithm: entry.algorithm,
      );
    }

    final titleText = entry.issuer.isNotEmpty ? entry.issuer : entry.account;
    final subtitleText = entry.issuer.isNotEmpty ? entry.account : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Details'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => context.push('/entry/${entry.id}/edit'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () => _deleteEntry(context, ref, entry),
          ),
        ],
      ),
      body: ResponsiveContentWrapper(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Header Card
              Card(
                elevation: 0.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: <Widget>[
                      LetterAvatar(
                        issuer: entry.issuer,
                        account: entry.account,
                        size: 64.0,
                      ),
                      const SizedBox(height: 12.0),
                      Text(
                        titleText,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (subtitleText != null &&
                          subtitleText.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4.0),
                        Text(
                          subtitleText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 20.0),
                      // Live Code Box
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20.0,
                          vertical: 16.0,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            CodeText(code: currentCode, fontSize: 32.0),
                            const SizedBox(width: 16.0),
                            if (entry.type == OtpType.totp)
                              CountdownRing(
                                remainingSeconds: remSeconds,
                                period: entry.period,
                                size: 36.0,
                              )
                            else
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                tooltip: 'Next HOTP code',
                                onPressed: () {
                                  ref
                                      .read(vaultControllerProvider.notifier)
                                      .incrementHotp(entry.id);
                                },
                              ),
                            const SizedBox(width: 8.0),
                            IconButton(
                              icon: const Icon(Icons.copy),
                              tooltip: 'Copy code',
                              onPressed: () =>
                                  _copyCode(context, ref, currentCode),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16.0),
              // Metadata Card
              Card(
                elevation: 0.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: Column(
                    children: <Widget>[
                      _MetadataRow(
                        label: 'Type',
                        value: entry.type == OtpType.totp
                            ? 'TOTP (Time-based)'
                            : 'HOTP (Counter-based)',
                      ),
                      const Divider(),
                      _MetadataRow(
                        label: 'Algorithm',
                        value: entry.algorithm.name.toUpperCase(),
                      ),
                      const Divider(),
                      _MetadataRow(
                        label: 'Digits',
                        value: '${entry.digits} digits',
                      ),
                      const Divider(),
                      if (entry.type == OtpType.totp)
                        _MetadataRow(
                          label: 'Period',
                          value: '${entry.period} seconds',
                        )
                      else
                        _MetadataRow(
                          label: 'Counter',
                          value: '${entry.counter}',
                        ),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              'Groups',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 16.0),
                            Expanded(
                              child: assignedGroups.isEmpty
                                  ? const Text('None', textAlign: TextAlign.end)
                                  : Wrap(
                                      alignment: WrapAlignment.end,
                                      spacing: 6.0,
                                      runSpacing: 4.0,
                                      children: <Widget>[
                                        for (final g in assignedGroups)
                                          Chip(
                                            label: Text(
                                              g.name,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            padding: EdgeInsets.zero,
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                      if (entry.note.isNotEmpty) ...<Widget>[
                        const Divider(),
                        _MetadataRow(label: 'Note', value: entry.note),
                      ],
                      const Divider(),
                      _MetadataRow(
                        label: 'Created',
                        value: entry.createdAt
                            .toLocal()
                            .toString()
                            .split('.')
                            .first,
                      ),
                      const Divider(),
                      _MetadataRow(
                        label: 'Updated',
                        value: entry.updatedAt
                            .toLocal()
                            .toString()
                            .split('.')
                            .first,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24.0),
              // Action Buttons
              OutlinedButton.icon(
                onPressed: () => context.push('/entry/${entry.id}/edit'),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit Account'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14.0),
                ),
              ),
              const SizedBox(height: 12.0),
              OutlinedButton.icon(
                onPressed: () => context.push('/entry/${entry.id}/reveal'),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Reveal secret / Export QR'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14.0),
                ),
              ),
              const SizedBox(height: 12.0),
              TextButton.icon(
                onPressed: () => _deleteEntry(context, ref, entry),
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                label: Text(
                  'Delete Account',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14.0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16.0),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
