import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/vault/vault_errors.dart';
import '../../data/vault_controller.dart';
import '../../shared/file_picker_service.dart';
import '../../shared/widgets/busy_overlay.dart';
import '../../shared/widgets/obscured_text_field.dart';
import '../../shared/widgets/password_prompt_dialog.dart';
import '../../shared/widgets/responsive_wrapper.dart';

/// Screen displayed when no active vault is present (§7.1 #1).
/// Allows creating a new vault with password confirmation or importing an existing vault.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _disclaimerAccepted = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _isPasswordLengthValid => _passwordController.text.length >= 8;
  bool get _doPasswordsMatch =>
      _passwordController.text == _confirmController.text;

  bool get _canCreateVault =>
      _isPasswordLengthValid && _doPasswordsMatch && _disclaimerAccepted;

  String? get _passwordError {
    if (_passwordController.text.isNotEmpty && !_isPasswordLengthValid) {
      return 'Password must be at least 8 characters';
    }
    return null;
  }

  String? get _confirmError {
    if (_confirmController.text.isNotEmpty && !_doPasswordsMatch) {
      return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _handleCreateVault() async {
    if (!_canCreateVault) return;
    setState(() => _errorMessage = null);

    try {
      await ref
          .read(vaultControllerProvider.notifier)
          .create(_passwordController.text);
    } catch (e) {
      final msg = e is VaultException ? e.message : e.toString();
      setState(() => _errorMessage = msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _handleImportVault() async {
    setState(() => _errorMessage = null);
    try {
      final pickFile = ref.read(filePickerProvider);
      final bytes = await pickFile();
      if (bytes == null || !mounted) return;

      final password = await PasswordPromptDialog.show(
        context,
        title: 'Import Vault',
        message: 'Enter the password for the selected vault file:',
        confirmLabel: 'Import',
      );
      if (password == null || !mounted) return;

      await ref
          .read(vaultControllerProvider.notifier)
          .importInitialVault(bytes, password);
    } catch (e) {
      final msg = e is VaultException
          ? e.message
          : 'Failed to import vault: wrong password or corrupted file';
      setState(() => _errorMessage = msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _handleRestoreBackup() async {
    setState(() => _errorMessage = null);
    final password = await PasswordPromptDialog.show(
      context,
      title: 'Restore Backup',
      message: 'Enter the password for your backup vault (.bak):',
      confirmLabel: 'Restore',
    );
    if (password == null || !mounted) return;

    try {
      await ref.read(vaultControllerProvider.notifier).restoreBackup(password);
    } catch (e) {
      final msg = e is VaultException ? e.message : 'Failed to restore backup';
      setState(() => _errorMessage = msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(vaultControllerProvider);
    final isBusy = vaultState is VaultUnlocking;
    final hasBackup = vaultState is VaultNoVault && vaultState.hasBackup;
    final theme = Theme.of(context);

    return Scaffold(
      body: BusyOverlay(
        isBusy: isBusy,
        message: 'Deriving key and setting up vault...',
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
                      Icons.shield_outlined,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Offline 2FA',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your codes never leave this device',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_errorMessage != null) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    ObscuredTextField(
                      controller: _passwordController,
                      labelText: 'Master Password',
                      hintText: 'Minimum 8 characters',
                      errorText: _passwordError,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    ObscuredTextField(
                      controller: _confirmController,
                      labelText: 'Confirm Password',
                      errorText: _confirmError,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) {
                        if (_canCreateVault) {
                          _handleCreateVault();
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      value: _disclaimerAccepted,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        'I understand there is no way to recover a forgotten password',
                        style: theme.textTheme.bodyMedium,
                      ),
                      onChanged: isBusy
                          ? null
                          : (bool? val) {
                              setState(() {
                                _disclaimerAccepted = val ?? false;
                              });
                            },
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: (!isBusy && _canCreateVault)
                          ? _handleCreateVault
                          : null,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Create vault',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: <Widget>[
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'OR',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('Import existing vault'),
                      onPressed: isBusy ? null : _handleImportVault,
                    ),
                    if (hasBackup) ...<Widget>[
                      const SizedBox(height: 12),
                      TextButton.icon(
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
