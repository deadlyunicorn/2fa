import 'package:flutter/material.dart';

/// Screen for application preferences, master password change, and about info (§7.1 #12).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Settings')),
    );
  }
}

/// Screen or view for changing the master password (§7.1 #12).
class ChangePasswordScreen extends StatelessWidget {
  const ChangePasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: const Center(child: Text('Change Password')),
    );
  }
}
