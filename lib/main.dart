import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/prefs_repository.dart';
import 'data/vault_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );

  // Probe persistent storage and determine initial lock state (§4.1)
  await container.read(vaultControllerProvider.notifier).initialize();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const Offline2faApp(),
    ),
  );
}
