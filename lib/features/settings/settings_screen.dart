import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/prefs_repository.dart';
import '../../shared/widgets/responsive_wrapper.dart';
export 'change_password_screen.dart';

/// Screen for application preferences, master password change, and about info (§7.1 #12, §9 M9).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final prefs = ref.watch(prefsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ResponsiveContentWrapper(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: <Widget>[
            // --- Appearance ---
            _buildSectionHeader(context, 'Appearance'),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 4.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Theme',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      key: const Key('settings_theme_segmented'),
                      segments: const [
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.system,
                          label: Text('System'),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.light,
                          label: Text('Light'),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {prefs.themeMode},
                      onSelectionChanged: (Set<ThemeMode> newSelection) {
                        ref
                            .read(prefsProvider.notifier)
                            .setThemeMode(newSelection.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),

            // --- Security & Privacy ---
            _buildSectionHeader(context, 'Security & Privacy'),
            ListTile(
              key: const Key('settings_auto_lock_tile'),
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Auto-lock timeout'),
              subtitle: Text(prefs.autoLockTimeout.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  _showAutoLockDialog(context, ref, prefs.autoLockTimeout),
            ),
            SwitchListTile(
              key: const Key('settings_lock_on_background_tile'),
              secondary: const Icon(Icons.phonelink_lock_outlined),
              title: const Text('Lock when app goes to background'),
              subtitle: const Text(
                'Require master password when returning to the app',
              ),
              value: prefs.lockOnBackground,
              onChanged: (bool value) {
                ref.read(prefsProvider.notifier).setLockOnBackground(value);
              },
            ),
            ListTile(
              key: const Key('settings_clipboard_clear_tile'),
              leading: const Icon(Icons.content_paste_go_outlined),
              title: const Text('Clipboard auto-clear delay'),
              subtitle: Text(prefs.clipboardClearDelay.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showClipboardClearDialog(
                context,
                ref,
                prefs.clipboardClearDelay,
              ),
            ),
            ListTile(
              key: const Key('settings_change_password_tile'),
              leading: const Icon(Icons.password_outlined),
              title: const Text('Change Master Password'),
              subtitle: const Text(
                'Update the encryption password for your vault',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/change-password'),
            ),
            ListTile(
              key: const Key('settings_backup_tile'),
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Backup & Restore'),
              subtitle: const Text('Export or import encrypted vaults'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/backup'),
            ),
            const Divider(height: 24),

            // --- About ---
            _buildSectionHeader(context, 'About'),
            Card(
              key: const Key('settings_no_internet_banner'),
              margin: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              elevation: 0,
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.wifi_off_outlined,
                      size: 28,
                      semanticLabel: 'No internet',
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'This app has no internet access. Your 2FA secrets never leave your device.',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const ListTile(
              key: Key('settings_app_info_tile'),
              leading: Icon(Icons.shield_outlined),
              title: Text('Offline 2FA'),
              subtitle: Text('Version 0.1.0+1 • License: GPL-3.0-only'),
            ),
            ListTile(
              key: const Key('settings_licenses_tile'),
              leading: const Icon(Icons.description_outlined),
              title: const Text('Open-source licenses'),
              subtitle: const Text('View licenses of third-party packages'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                showLicensePage(
                  context: context,
                  applicationName: 'Offline 2FA',
                  applicationVersion: '0.1.0',
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _showAutoLockDialog(
    BuildContext context,
    WidgetRef ref,
    AutoLockTimeout current,
  ) async {
    final selected = await showDialog<AutoLockTimeout>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Auto-lock timeout'),
          children: [
            RadioGroup<AutoLockTimeout>(
              groupValue: current,
              onChanged: (val) {
                if (val != null) {
                  Navigator.of(dialogContext).pop(val);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: AutoLockTimeout.values.map((timeout) {
                  return RadioListTile<AutoLockTimeout>(
                    key: Key('autolock_option_${timeout.seconds}'),
                    title: Text(timeout.label),
                    value: timeout,
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );

    if (selected != null) {
      await ref
          .read(prefsProvider.notifier)
          .setAutoLockTimeoutSeconds(selected.seconds);
    }
  }

  Future<void> _showClipboardClearDialog(
    BuildContext context,
    WidgetRef ref,
    ClipboardClearDelay current,
  ) async {
    final selected = await showDialog<ClipboardClearDelay>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Clipboard auto-clear delay'),
          children: [
            RadioGroup<ClipboardClearDelay>(
              groupValue: current,
              onChanged: (val) {
                if (val != null) {
                  Navigator.of(dialogContext).pop(val);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: ClipboardClearDelay.values.map((delay) {
                  return RadioListTile<ClipboardClearDelay>(
                    key: Key('clipboard_option_${delay.seconds}'),
                    title: Text(delay.label),
                    value: delay,
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );

    if (selected != null) {
      await ref
          .read(prefsProvider.notifier)
          .setClipboardClearSeconds(selected.seconds);
    }
  }
}
