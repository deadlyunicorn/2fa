import 'package:flutter/material.dart';

/// Screen offering account addition via camera, image QR, or manual entry (§7.1 #4).
class AddHubScreen extends StatelessWidget {
  const AddHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Account')),
      body: const Center(child: Text('Add Account')),
    );
  }
}

/// Screen for manual OTP entry input (§7.1 #5).
class ManualEntryScreen extends StatelessWidget {
  const ManualEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manual Entry')),
      body: const Center(child: Text('Manual Entry')),
    );
  }
}

/// Screen for QR code scanning with camera (§7.1 #6).
class ScanQrScreen extends StatelessWidget {
  const ScanQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: const Center(child: Text('Scan QR Code')),
    );
  }
}

/// Screen showing OTP entry details (§7.1 #8).
class EntryDetailsScreen extends StatelessWidget {
  const EntryDetailsScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entry Details')),
      body: Center(child: Text('Entry Details for $id')),
    );
  }
}

/// Screen for editing an existing OTP entry (§7.1 #5).
class EntryEditScreen extends StatelessWidget {
  const EntryEditScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Entry')),
      body: Center(child: Text('Edit Entry $id')),
    );
  }
}

/// Backward-compatible alias for [AddHubScreen].
typedef AddEntryScreen = AddHubScreen;
