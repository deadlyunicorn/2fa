import 'package:flutter/material.dart';

/// Screen for displaying sensitive secret keys, URIs, and QR codes behind password re-entry.
class RevealScreen extends StatelessWidget {
  const RevealScreen({required this.entryId, super.key});

  final String entryId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text('Reveal Secret: $entryId')));
  }
}
