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

enum EntryTileAction { details, edit, reveal, delete }

/// Tile widget representing a single OTP entry in the entries list (§7.1 #3).
class EntryTile extends ConsumerWidget {
  const EntryTile({
    super.key,
    required this.entry,
    required this.index,
    this.canReorder = false,
  });

  final OtpEntry entry;
  final int index;
  final bool canReorder;

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

  Future<void> _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    EntryTileAction action,
  ) async {
    switch (action) {
      case EntryTileAction.details:
        await context.push('/entry/${entry.id}');
      case EntryTileAction.edit:
        await context.push('/entry/${entry.id}/edit');
      case EntryTileAction.reveal:
        await context.push('/entry/${entry.id}/reveal');
      case EntryTileAction.delete:
        final accountName = entry.issuer.isNotEmpty
            ? entry.issuer
            : entry.account;
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Delete account',
          message:
              'Are you sure you want to delete "$accountName"? This cannot be undone.',
          confirmLabel: 'Delete',
          isDestructive: true,
        );
        if (confirmed == true && context.mounted) {
          await ref
              .read(vaultControllerProvider.notifier)
              .deleteEntry(entry.id);
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Decode secret bytes safely
    Uint8List? secretBytes;
    try {
      secretBytes = Base32Codec.decode(entry.secret);
    } catch (_) {
      secretBytes = null;
    }

    final String currentCode;
    int remSeconds = 0;
    String? nextCode;

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
      if (remSeconds <= 5) {
        nextCode = totp(
          secretBytes,
          epochSeconds + remSeconds,
          period: entry.period,
          digits: entry.digits,
          algorithm: entry.algorithm,
        );
      }
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.0),
        onTap: () => _copyCode(context, ref, currentCode),
        onLongPress: () => context.push('/entry/${entry.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: <Widget>[
              LetterAvatar(
                issuer: entry.issuer,
                account: entry.account,
                size: 44.0,
              ),
              const SizedBox(width: 14.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      titleText,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitleText != null &&
                        subtitleText.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2.0),
                      Text(
                        subtitleText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6.0),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8.0,
                      children: <Widget>[
                        CodeText(code: currentCode, fontSize: 22.0),
                        if (nextCode != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                'Next: ',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              CodeText(
                                code: nextCode,
                                fontSize: 14.0,
                                isFaint: true,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8.0),
              if (entry.type == OtpType.totp)
                CountdownRing(
                  remainingSeconds: remSeconds,
                  period: entry.period,
                  size: 32.0,
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
              PopupMenuButton<EntryTileAction>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'More options',
                onSelected: (action) => _handleMenuAction(context, ref, action),
                itemBuilder: (context) => <PopupMenuEntry<EntryTileAction>>[
                  const PopupMenuItem(
                    value: EntryTileAction.details,
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.info_outline),
                        SizedBox(width: 12),
                        Text('Details'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: EntryTileAction.edit,
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.edit_outlined),
                        SizedBox(width: 12),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: EntryTileAction.reveal,
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.visibility_outlined),
                        SizedBox(width: 12),
                        Text('Reveal secret'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: EntryTileAction.delete,
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Delete',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (canReorder)
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4.0),
                    child: Icon(
                      Icons.drag_handle,
                      color: theme.colorScheme.onSurfaceVariant,
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
