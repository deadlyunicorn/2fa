import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/group.dart';
import '../../core/models/otp_algorithm.dart';
import '../../core/models/otp_entry.dart';
import '../../core/models/otp_type.dart';
import '../../core/otp/base32.dart';
import '../../core/otp/hotp.dart';
import '../../core/otp/otpauth_uri.dart';
import '../../core/otp/totp.dart';
import '../../data/vault_controller.dart';
import '../../shared/widgets/code_text.dart';
import '../../shared/widgets/countdown_ring.dart';
import '../../shared/widgets/letter_avatar.dart';
import '../../shared/widgets/obscured_text_field.dart';
import '../../shared/widgets/responsive_wrapper.dart';
import '../groups/groups_screen.dart';

/// Screen for creating or editing an OTP account entry (§7.1 #5).
class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key, this.entryId, this.initialEntry});

  /// Existing entry ID when opened in edit mode.
  final String? entryId;

  /// Optional pre-filled entry (e.g. from scanned URI).
  final OtpEntry? initialEntry;

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _uriController;
  late final TextEditingController _issuerController;
  late final TextEditingController _accountController;
  late final TextEditingController _secretController;
  late final TextEditingController _periodController;
  late final TextEditingController _counterController;
  late final TextEditingController _noteController;

  OtpType _selectedType = OtpType.totp;
  OtpAlgorithm _selectedAlgorithm = OtpAlgorithm.sha1;
  int _selectedDigits = 6;
  Set<String> _selectedGroupIds = <String>{};

  String? _uriError;
  String? _uriFeedback;
  OtpEntry? _existingEntry;
  bool _initializedFromVault = false;

  @override
  void initState() {
    super.initState();
    _uriController = TextEditingController();
    _issuerController = TextEditingController();
    _accountController = TextEditingController();
    _secretController = TextEditingController();
    _periodController = TextEditingController(text: '30');
    _counterController = TextEditingController(text: '0');
    _noteController = TextEditingController();

    if (widget.initialEntry != null) {
      _applyEntry(widget.initialEntry!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedFromVault && widget.entryId != null) {
      _initializedFromVault = true;
      final vaultState = ref.read(vaultControllerProvider);
      if (vaultState is VaultUnlocked) {
        try {
          final entry = vaultState.data.entries.firstWhere(
            (e) => e.id == widget.entryId,
          );
          _existingEntry = entry;
          _applyEntry(entry);
        } catch (_) {}
      }
    }
  }

  void _applyEntry(OtpEntry entry) {
    _issuerController.text = entry.issuer;
    _accountController.text = entry.account;
    _secretController.text = entry.secret;
    _selectedType = entry.type;
    _selectedAlgorithm = entry.algorithm;
    _selectedDigits = entry.digits;
    _periodController.text = entry.period.toString();
    _counterController.text = entry.counter.toString();
    _selectedGroupIds = Set<String>.from(entry.groupIds);
    _noteController.text = entry.note;
  }

  @override
  void dispose() {
    _uriController.dispose();
    _issuerController.dispose();
    _accountController.dispose();
    _secretController.dispose();
    _periodController.dispose();
    _counterController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onUriChanged(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _uriError = null;
        _uriFeedback = null;
      });
      return;
    }

    if (trimmed.toLowerCase().startsWith('otpauth-migration:')) {
      setState(() {
        _uriError = 'Not supported yet';
        _uriFeedback = null;
      });
      return;
    }

    try {
      final parsed = OtpAuthUri.parse(trimmed);
      setState(() {
        _issuerController.text = parsed.issuer;
        _accountController.text = parsed.account;
        _secretController.text = parsed.secret;
        _selectedType = parsed.type;
        _selectedAlgorithm = parsed.algorithm;
        _selectedDigits = parsed.digits;
        _periodController.text = parsed.period.toString();
        _counterController.text = parsed.counter.toString();
        _uriFeedback = 'URI parsed successfully!';
        _uriError = null;
      });
    } on MigrationNotSupportedException {
      setState(() {
        _uriError = 'Not supported yet';
        _uriFeedback = null;
      });
    } catch (_) {
      setState(() {
        _uriError = 'Invalid otpauth:// URI';
        _uriFeedback = null;
      });
    }
  }

  Future<void> _saveEntry() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final normalizedSecret = Base32Codec.normalize(_secretController.text);
    final period = int.tryParse(_periodController.text) ?? 30;
    final counter = int.tryParse(_counterController.text) ?? 0;

    final vaultController = ref.read(vaultControllerProvider.notifier);

    if (_existingEntry != null) {
      final updated = OtpEntry(
        id: _existingEntry!.id,
        type: _selectedType,
        issuer: _issuerController.text.trim(),
        account: _accountController.text.trim(),
        secret: normalizedSecret,
        algorithm: _selectedAlgorithm,
        digits: _selectedDigits,
        period: period,
        counter: counter,
        groupIds: _selectedGroupIds.toList(),
        note: _noteController.text.trim(),
        sortOrder: _existingEntry!.sortOrder,
        createdAt: _existingEntry!.createdAt,
        updatedAt: DateTime.now().toUtc(),
      );
      await vaultController.updateEntry(updated);
    } else {
      final newEntry = OtpEntry(
        id: const Uuid().v4(),
        type: _selectedType,
        issuer: _issuerController.text.trim(),
        account: _accountController.text.trim(),
        secret: normalizedSecret,
        algorithm: _selectedAlgorithm,
        digits: _selectedDigits,
        period: period,
        counter: counter,
        groupIds: _selectedGroupIds.toList(),
        note: _noteController.text.trim(),
      );
      await vaultController.addEntry(newEntry);
    }

    if (mounted) {
      context.go('/');
    }
  }

  Future<void> _handleCreateGroup() async {
    final newGroup = await showAddGroupDialog(context, ref);
    if (newGroup != null && mounted) {
      setState(() {
        _selectedGroupIds.add(newGroup.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.entryId != null || _existingEntry != null;
    final title = isEditing ? 'Edit Account' : 'New Account';
    final saveButtonLabel = isEditing ? 'Save changes' : 'Add Account';

    final vaultState = ref.watch(vaultControllerProvider);
    final groups = vaultState is VaultUnlocked
        ? (List<Group>.from(vaultState.data.groups)
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
        : const <Group>[];

    // Live code preview calculations
    final rawSecret = _secretController.text.trim();
    final isValidBase32 = Base32Codec.isValid(rawSecret);
    Uint8List? previewSecretBytes;
    String? previewCode;
    int previewRem = 0;

    if (isValidBase32) {
      try {
        previewSecretBytes = Base32Codec.decode(rawSecret);
        if (_selectedType == OtpType.totp) {
          final period = int.tryParse(_periodController.text) ?? 30;
          final validPeriod = period >= 1 && period <= 300 ? period : 30;
          final epochSeconds =
              ref.watch(tickerProvider).value ??
              (DateTime.now().millisecondsSinceEpoch ~/ 1000);
          previewRem = remainingSeconds(epochSeconds, period: validPeriod);
          previewCode = totp(
            previewSecretBytes,
            epochSeconds,
            period: validPeriod,
            digits: _selectedDigits,
            algorithm: _selectedAlgorithm,
          );
        } else {
          final counter = int.tryParse(_counterController.text) ?? 0;
          final validCounter = counter >= 0 ? counter : 0;
          previewCode = hotp(
            previewSecretBytes,
            validCounter,
            digits: _selectedDigits,
            algorithm: _selectedAlgorithm,
          );
        }
      } catch (_) {
        previewCode = null;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ResponsiveContentWrapper(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (!isEditing) ...<Widget>[
                  TextFormField(
                    controller: _uriController,
                    decoration: InputDecoration(
                      labelText: 'Paste otpauth:// URI',
                      hintText: 'otpauth://totp/Example:alice?secret=...',
                      prefixIcon: const Icon(Icons.link),
                      border: const OutlineInputBorder(),
                      errorText: _uriError,
                      helperText: _uriFeedback,
                      helperStyle: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      suffixIcon: _uriController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _uriController.clear();
                                _onUriChanged('');
                              },
                            )
                          : null,
                    ),
                    onChanged: _onUriChanged,
                  ),
                  const SizedBox(height: 16.0),
                  const Divider(),
                  const SizedBox(height: 8.0),
                ],
                TextFormField(
                  controller: _issuerController,
                  decoration: const InputDecoration(
                    labelText: 'Issuer',
                    hintText: 'e.g. GitHub, Google',
                    prefixIcon: Icon(Icons.business_outlined),
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  validator: (_) {
                    if (_issuerController.text.trim().isEmpty &&
                        _accountController.text.trim().isEmpty) {
                      return 'Please enter either an issuer or account name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: _accountController,
                  decoration: const InputDecoration(
                    labelText: 'Account / Username',
                    hintText: 'e.g. user@example.com',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (_) {
                    if (_issuerController.text.trim().isEmpty &&
                        _accountController.text.trim().isEmpty) {
                      return 'Please enter either an issuer or account name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16.0),
                ObscuredTextField(
                  controller: _secretController,
                  labelText: 'Secret key',
                  hintText: 'Base32 secret (e.g. JBSWY3DPEHPK3PXP)',
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  onChanged: (_) => setState(() {}),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Secret is required';
                    }
                    if (!Base32Codec.isValid(val)) {
                      return 'Invalid Base32 secret key';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16.0),
                SegmentedButton<OtpType>(
                  segments: const <ButtonSegment<OtpType>>[
                    ButtonSegment<OtpType>(
                      value: OtpType.totp,
                      label: Text('TOTP (Time-based)'),
                      icon: Icon(Icons.timer_outlined),
                    ),
                    ButtonSegment<OtpType>(
                      value: OtpType.hotp,
                      label: Text('HOTP (Counter-based)'),
                      icon: Icon(Icons.pin_outlined),
                    ),
                  ],
                  selected: <OtpType>{_selectedType},
                  onSelectionChanged: (Set<OtpType> selected) {
                    setState(() {
                      _selectedType = selected.first;
                    });
                  },
                ),
                const SizedBox(height: 16.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      'Groups',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New group'),
                      onPressed: _handleCreateGroup,
                    ),
                  ],
                ),
                const SizedBox(height: 8.0),
                if (groups.isEmpty)
                  Text(
                    'No groups created yet. Tap "New group" to organize accounts.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: <Widget>[
                      for (final group in groups)
                        FilterChip(
                          label: Text(group.name),
                          selected: _selectedGroupIds.contains(group.id),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedGroupIds.add(group.id);
                              } else {
                                _selectedGroupIds.remove(group.id);
                              }
                            });
                          },
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: const Text('New group'),
                        tooltip: 'Create new group',
                        onPressed: _handleCreateGroup,
                      ),
                    ],
                  ),
                const SizedBox(height: 16.0),
                ExpansionTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Advanced options'),
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 8.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const Text(
                            'Algorithm',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8.0),
                          SegmentedButton<OtpAlgorithm>(
                            segments: const <ButtonSegment<OtpAlgorithm>>[
                              ButtonSegment<OtpAlgorithm>(
                                value: OtpAlgorithm.sha1,
                                label: Text('SHA1'),
                              ),
                              ButtonSegment<OtpAlgorithm>(
                                value: OtpAlgorithm.sha256,
                                label: Text('SHA256'),
                              ),
                              ButtonSegment<OtpAlgorithm>(
                                value: OtpAlgorithm.sha512,
                                label: Text('SHA512'),
                              ),
                            ],
                            selected: <OtpAlgorithm>{_selectedAlgorithm},
                            onSelectionChanged: (Set<OtpAlgorithm> selected) {
                              setState(() {
                                _selectedAlgorithm = selected.first;
                              });
                            },
                          ),
                          const SizedBox(height: 16.0),
                          const Text(
                            'Digits',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8.0),
                          SegmentedButton<int>(
                            segments: const <ButtonSegment<int>>[
                              ButtonSegment<int>(
                                value: 6,
                                label: Text('6 digits'),
                              ),
                              ButtonSegment<int>(
                                value: 7,
                                label: Text('7 digits'),
                              ),
                              ButtonSegment<int>(
                                value: 8,
                                label: Text('8 digits'),
                              ),
                            ],
                            selected: <int>{_selectedDigits},
                            onSelectionChanged: (Set<int> selected) {
                              setState(() {
                                _selectedDigits = selected.first;
                              });
                            },
                          ),
                          const SizedBox(height: 16.0),
                          if (_selectedType == OtpType.totp)
                            TextFormField(
                              controller: _periodController,
                              decoration: const InputDecoration(
                                labelText: 'Period (seconds)',
                                hintText: '30',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Period is required';
                                }
                                final p = int.tryParse(val.trim());
                                if (p == null || p < 1 || p > 300) {
                                  return 'Period must be between 1 and 300 seconds';
                                }
                                return null;
                              },
                            )
                          else
                            TextFormField(
                              controller: _counterController,
                              decoration: const InputDecoration(
                                labelText: 'Counter',
                                hintText: '0',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Counter is required';
                                }
                                final c = int.tryParse(val.trim());
                                if (c == null || c < 0) {
                                  return 'Counter must be non-negative';
                                }
                                return null;
                              },
                            ),
                          const SizedBox(height: 16.0),
                          TextFormField(
                            controller: _noteController,
                            decoration: const InputDecoration(
                              labelText: 'Note (optional)',
                              hintText: 'Additional details or backup codes',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24.0),
                if (previewCode != null) ...<Widget>[
                  Card(
                    color: theme.colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Live Code Preview',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12.0),
                          Row(
                            children: <Widget>[
                              LetterAvatar(
                                issuer: _issuerController.text,
                                account: _accountController.text,
                                size: 40.0,
                              ),
                              const SizedBox(width: 14.0),
                              Expanded(
                                child: CodeText(
                                  code: previewCode,
                                  fontSize: 24.0,
                                ),
                              ),
                              if (_selectedType == OtpType.totp)
                                CountdownRing(
                                  remainingSeconds: previewRem,
                                  period:
                                      int.tryParse(_periodController.text) ??
                                      30,
                                  size: 32.0,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24.0),
                ],
                FilledButton.icon(
                  onPressed: _saveEntry,
                  icon: const Icon(Icons.check),
                  label: Text(saveButtonLabel),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14.0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
