import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/vault_controller.dart';
import '../../shared/widgets/busy_overlay.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/obscured_text_field.dart';
import '../../shared/widgets/password_prompt_dialog.dart';
import '../../shared/widgets/responsive_wrapper.dart';

/// Screen displayed when an existing vault is locked (§5.6, §5.7, §7.1 #2).
/// Supports master password unlock, rate-limiting throttle countdown,
/// backup restoration, and hard reset (deletion).
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final TextEditingController _passwordController = TextEditingController();
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _checkLockoutTimer();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _passwordController.dispose();
    super.dispose();
  }

  void _checkLockoutTimer() {
    _countdownTimer?.cancel();
    final vaultState = ref.read(vaultControllerProvider);
    if (vaultState is VaultLocked && vaultState.isLockedOut) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (
        Timer timer,
      ) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        final state = ref.read(vaultControllerProvider);
        if (state is VaultLocked && state.isLockedOut) {
          setState(() {});
        } else {
          timer.cancel();
          setState(() {});
        }
      });
    }
  }

  Future<void> _handleUnlock() async {
    final password = _passwordController.text;
    if (password.isEmpty) return;

    await ref.read(vaultControllerProvider.notifier).unlock(password);
    if (mounted) {
      _checkLockoutTimer();
    }
  }

  Future<void> _handleRestoreBackup() async {
    final password = await PasswordPromptDialog.show(
      context,
      title: 'Restore Backup',
      message: 'Enter the password for your backup vault (.bak):',
      confirmLabel: 'Restore',
    );
    if (password == null || !mounted) return;

    await ref.read(vaultControllerProvider.notifier).restoreBackup(password);
  }

  Future<void> _handleResetVault() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Reset App (Delete Vault)',
      message: 'This will permanently delete your vault and all stored 2FA tokens. This action cannot be undone.',
      requiredConfirmationText: 'DELETE',
      isDestructive: true,
      confirmLabel: 'Delete Vault',
    );

    if (confirmed && mounted) {
      await ref.read(vaultControllerProvider.notifier).resetVault();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(vaultControllerProvider);
    final isBusy = vaultState is VaultUnlocking;
    final theme = Theme.of(context);

    final lockedState = vaultState is VaultLocked ? vaultState : null;
    final isLockedOut = lockedState?.isLockedOut ?? false;
    final remainingLockout = lockedState?.remainingLockoutSeconds ?? 0;
    final hasBackup = lockedState?.hasBackup ?? false;
    final errorMessage = lockedState?.errorMessage;

    // Restart timer if locked out and timer not active
    if (isLockedOut &&
        (_countdownTimer == null || !_countdownTimer!.isActive)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkLockoutTimer());
    }

    final canUnlock = !isBusy && !isLockedOut;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline 2FA'),
        centerTitle: true,
        actions: <Widget>[
          PopupMenuButton<String>(
            tooltip: 'More options',
            icon: const Icon(Icons.more_vert),
            onSelected: (String value) {
              if (value == 'restore') {
                _handleRestoreBackup();
              } else if (value == 'reset') {
                _handleResetVault();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              if (hasBackup)
                const PopupMenuItem<String>(
                  value: 'restore',
                  child: ListTile(
                    leading: Icon(Icons.settings_backup_restore),
                    title: Text('Restore from backup (.bak)'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem<String>(
                value: 'reset',
                child: ListTile(
                  leading: Icon(Icons.delete_forever, color: Colors.red),
                  title: Text(
                    'Reset app (delete vault)',
                    style: TextStyle(color: Colors.red),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: BusyOverlay(
        isBusy: isBusy,
        message: 'Unlocking vault...',
        child: SafeArea(
          child: ResponsiveContentWrapper(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 32.0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Icon(
                      Icons.lock_outline,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Unlock Vault',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter your master password to unlock',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (isLockedOut) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.timer_outlined,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Too many attempts. Try again in ${remainingLockout}s',
                                style: TextStyle(
                                  color: theme.colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else if (errorMessage != null) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          errorMessage,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    ObscuredTextField(
                      controller: _passwordController,
                      autofocus: true,
                      enabled: canUnlock,
                      labelText: 'Master Password',
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (canUnlock) {
                          _handleUnlock();
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: canUnlock ? _handleUnlock : null,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Unlock', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    if (errorMessage != null && hasBackup) ...<Widget>[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.settings_backup_restore),
                        label: const Text('Restore from backup (.bak)'),
                        onPressed: isBusy ? null : _handleRestoreBackup,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
