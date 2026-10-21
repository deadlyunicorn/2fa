import 'package:flutter/material.dart';

/// Screen for displaying sensitive secret keys, URIs, and QR codes behind password re-entry (§7.1 #9).
class RevealScreen extends StatelessWidget {
  const RevealScreen({required this.id, super.key});

  final String id;
  String get entryId => id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reveal Secret')),
      body: Center(child: Text('Reveal Secret: $id')),
    );
  }
}
