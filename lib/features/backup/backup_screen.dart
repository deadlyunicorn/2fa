import 'package:flutter/material.dart';

/// Screen for exporting encrypted vault and importing/merging external vaults (§7.1 #11).
class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: const Center(child: Text('Backup & Restore')),
    );
  }
}
