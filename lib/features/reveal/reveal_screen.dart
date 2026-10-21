import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/models/otp_entry.dart';
import '../../core/otp/otpauth_uri.dart';
import '../../data/prefs_repository.dart';
import '../../data/vault_controller.dart';
import '../../shared/clipboard_service.dart';
import '../../shared/widgets/busy_overlay.dart';
import '../../shared/widgets/obscured_text_field.dart';
import '../../shared/widgets/responsive_wrapper.dart';

/// Screen for displaying sensitive secret keys, URIs, and QR codes behind password re-entry (§1.1 #6, §7.1 #9, §9 M8).
class RevealScreen extends ConsumerStatefulWidget {
  const RevealScreen({required this.id, super.key});

  final String id;

  @override
  ConsumerState<RevealScreen> createState() => _RevealScreenState();
}

class _RevealScreenState extends ConsumerState<RevealScreen> {
  bool _isVerified = false;
  bool _isVerifying = false;
  String? _passwordError;
  late final TextEditingController _passwordController;
  TextEditingController? _secretController;
  TextEditingController? _uriController;
  bool _isQrRevealed = false;

  @override
  void initState() {
    super.initState();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _secretController?.dispose();
    _uriController?.dispose();
    super.dispose();
  }

  Future<void> _handleVerifyPassword() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _passwordError = 'Password cannot be empty');
      return;
    }

    setState(() {
      _isVerifying = true;
      _passwordError = null;
    });

    try {
      final isValid = await ref
          .read(vaultControllerProvider.notifier)
          .verifyPassword(password);
      if (!mounted) return;
      if (isValid) {
        setState(() {
          _isVerifying = false;
          _isVerified = true;
          _passwordController.clear();
        });
      } else {
        setState(() {
          _isVerifying = false;
          _passwordError = 'Incorrect master password';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _passwordError = 'Incorrect master password';
      });
    }
  }

  Future<void> _copyText(String text) async {
    final prefs = ref.read(prefsProvider);
    final clipboard = ref.read(clipboardServiceProvider);
    final message = await clipboard.copyCode(
      text,
      clearAfterSeconds: prefs.clipboardClearSeconds,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vaultState = ref.watch(vaultControllerProvider);

    if (vaultState is! VaultUnlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reveal Secret')),
        body: const Center(child: Text('Vault is locked')),
      );
    }

    final entry = vaultState.data.entries.cast<OtpEntry?>().firstWhere(
      (e) => e?.id == widget.id,
      orElse: () => null,
    );

    if (entry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reveal Secret')),
        body: const Center(child: Text('Account not found')),
      );
    }

    final title = entry.issuer.isNotEmpty ? entry.issuer : entry.account;

    // Step 1: Password Re-entry Gate
    if (!_isVerified) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: BusyOverlay(
          isBusy: _isVerifying,
          message: 'Verifying master password...',
          child: ResponsiveContentWrapper(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 16),
                  Icon(
                    Icons.lock_outline,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Re-enter Master Password',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please re-enter your master password to reveal sensitive account details.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ObscuredTextField(
                    controller: _passwordController,
                    autofocus: true,
                    labelText: 'Master Password',
                    errorText: _passwordError,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _handleVerifyPassword(),
                    onChanged: (_) {
                      if (_passwordError != null) {
                        setState(() => _passwordError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isVerifying ? null : _handleVerifyPassword,
                    child: const Text('Verify'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Step 2: Revealed View (once verified for this screen session)
    final uriString = OtpAuthUri.serialize(entry);
    _secretController ??= TextEditingController(text: entry.secret);
    _uriController ??= TextEditingController(text: uriString);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ResponsiveContentWrapper(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Warning banner at top: "Anyone with this QR or secret can generate your codes."
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
                          'Anyone with this QR or secret can generate your codes.',
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
              // Secret Key Field
              Text(
                'Secret Key',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ObscuredTextField(
                controller: _secretController,
                labelText: 'Secret',
                readOnly: true,
                obscureByDefault: true,
                suffixActions: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy secret',
                    onPressed: () => _copyText(entry.secret),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // otpauth:// URI Field
              Text(
                'otpauth:// URI',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ObscuredTextField(
                controller: _uriController,
                labelText: 'URI',
                readOnly: true,
                obscureByDefault: true,
                suffixActions: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy URI',
                    onPressed: () => _copyText(uriString),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // QR Code Section
              Text(
                'QR Code',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: !_isQrRevealed
                    ? Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => setState(() => _isQrRevealed = true),
                          child: Container(
                            width: 240,
                            height: 240,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(
                                  Icons.qr_code_2,
                                  size: 56,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Tap to show QR',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Hidden for privacy',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => setState(() => _isQrRevealed = false),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: <Widget>[
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: QrImageView(
                                    data: uriString,
                                    size: 220,
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  icon: const Icon(
                                    Icons.visibility_off_outlined,
                                  ),
                                  label: const Text('Hide QR'),
                                  onPressed: () =>
                                      setState(() => _isQrRevealed = false),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
