import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/vault/vault_errors.dart';
import '../../data/vault_controller.dart';
import '../../shared/widgets/busy_overlay.dart';
import '../../shared/widgets/obscured_text_field.dart';
import '../../shared/widgets/responsive_wrapper.dart';

/// Screen allowing the user to rotate the vault's master password (§1.1 #8, §5.2, §7.1 #12, §9 M8).
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isBusy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _isCurrentEntered => _currentPasswordController.text.isNotEmpty;
  bool get _isNewValid => _newPasswordController.text.length >= 8;
  bool get _doPasswordsMatch =>
      _newPasswordController.text == _confirmPasswordController.text;

  bool get _canSubmit => _isCurrentEntered && _isNewValid && _doPasswordsMatch;

  String? get _newPasswordError {
    if (_newPasswordController.text.isNotEmpty && !_isNewValid) {
      return 'New password must be at least 8 characters';
    }
    return null;
  }

  String? get _confirmPasswordError {
    if (_confirmPasswordController.text.isNotEmpty && !_doPasswordsMatch) {
      return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _handleChangePassword() async {
    if (!_canSubmit) return;

    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(vaultControllerProvider.notifier)
          .changePassword(
            _currentPasswordController.text,
            _newPasswordController.text,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Master password changed successfully'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop();
    } on WrongPasswordOrCorrupted {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Current password is incorrect';
      });
    } on VaultException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to change password: $e';
      });
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
      appBar: AppBar(title: const Text('Change Master Password')),
      body: BusyOverlay(
        isBusy: _isBusy,
        message: 'Deriving key and re-encrypting vault...',
        child: ResponsiveContentWrapper(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Warning Banner
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.warning_amber_rounded,
                          color: theme.colorScheme.onErrorContainer,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'There is NO password recovery. If you forget your new master password, your vault cannot be recovered.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Error Display if present
                if (_errorMessage != null) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.error_outline,
                          color: theme.colorScheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Current Master Password
                ObscuredTextField(
                  controller: _currentPasswordController,
                  labelText: 'Current master password',
                  errorText:
                      _errorMessage != null &&
                          _errorMessage == 'Current password is incorrect'
                      ? 'Current password is incorrect'
                      : null,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_errorMessage != null) {
                      setState(() => _errorMessage = null);
                    } else {
                      setState(() {});
                    }
                  },
                ),
                const SizedBox(height: 16),
                // New Master Password
                ObscuredTextField(
                  controller: _newPasswordController,
                  labelText: 'New master password',
                  helperText: 'Minimum 8 characters',
                  errorText: _newPasswordError,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                // Confirm New Master Password
                ObscuredTextField(
                  controller: _confirmPasswordController,
                  labelText: 'Confirm new master password',
                  errorText: _confirmPasswordError,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (_canSubmit) {
                      _handleChangePassword();
                    }
                  },
                ),
                const SizedBox(height: 32),
                // Submit Button
                FilledButton(
                  onPressed: _canSubmit && !_isBusy
                      ? _handleChangePassword
                      : null,
                  child: const Text('Change Password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
