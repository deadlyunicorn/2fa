import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/vault_controller.dart';
import '../../shared/widgets/responsive_wrapper.dart';

/// Home screen displaying OTP entries with search, group filters, and lock controls (§7.1 #3).
class EntriesListScreen extends ConsumerWidget {
  const EntriesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline 2FA'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Lock vault',
            onPressed: () {
              ref.read(vaultControllerProvider.notifier).lock();
            },
          ),
        ],
      ),
      body: const ResponsiveContentWrapper(
        child: Center(child: Text('Offline 2FA Entries')),
      ),
    );
  }
}

/// Backward-compatible alias for [EntriesListScreen].
typedef EntriesScreen = EntriesListScreen;
