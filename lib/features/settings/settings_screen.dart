import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/responsive_wrapper.dart';
export 'change_password_screen.dart';

/// Screen for application preferences, master password change, and about info (§7.1 #12).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ResponsiveContentWrapper(
        child: ListView(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: const Text('Change Master Password'),
              subtitle: const Text(
                'Update the encryption password for your vault',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/change-password'),
            ),
          ],
        ),
      ),
    );
  }
}
