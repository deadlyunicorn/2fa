import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/prefs_repository.dart';
import 'data/vault_controller.dart';
import 'router.dart';
import 'shared/auto_lock_service.dart';

/// Root application widget configuring Material 3 theme, Riverpod state, and routing (§4.2, §7).
class Offline2faApp extends ConsumerStatefulWidget {
  const Offline2faApp({super.key, this.routerConfig});

  final RouterConfig<Object>? routerConfig;

  @override
  ConsumerState<Offline2faApp> createState() => _Offline2faAppState();
}

class _Offline2faAppState extends ConsumerState<Offline2faApp> {
  @override
  void initState() {
    super.initState();
    // Auto-initialize vault state on launch if still in initial state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(vaultControllerProvider) is VaultInitial) {
        ref.read(vaultControllerProvider.notifier).initialize();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(prefsProvider);
    final router = widget.routerConfig ?? ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Offline 2FA',
      debugShowCheckedModeBanner: false,
      themeMode: prefs.themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: router,
      builder: (BuildContext context, Widget? child) {
        return AutoLockListener(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
