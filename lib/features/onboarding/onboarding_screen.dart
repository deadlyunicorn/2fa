import 'package:flutter/material.dart';

/// Screen displayed when no vault file exists, allowing vault creation or import.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Create or Import Vault')));
  }
}
