import 'package:flutter/material.dart';

/// Screen displayed when the vault exists but is currently locked.
class LockScreen extends StatelessWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Unlock Vault')));
  }
}
