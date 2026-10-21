import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/models/otp_entry.dart';
import 'core/otp/otpauth_uri.dart';
import 'core/platform/platform_caps.dart';
import 'data/vault_controller.dart';
import 'features/add_entry/add_entry_screen.dart';
import 'features/backup/backup_screen.dart';
import 'features/entries/entries_screen.dart';
import 'features/groups/groups_screen.dart';
import 'features/lock/unlock_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/reveal/reveal_screen.dart';
import 'features/settings/settings_screen.dart';

/// Notifier that triggers GoRouter redirect re-evaluation whenever [VaultState] changes (§4.2).
class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(this._ref) {
    _subscription = _ref.listen<VaultState>(vaultControllerProvider, (
      VaultState? previous,
      VaultState next,
    ) {
      notifyListeners();
    });
  }

  final Ref _ref;
  ProviderSubscription<VaultState>? _subscription;

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }
}

/// Provider for [RouterRefreshNotifier].
final routerRefreshNotifierProvider = Provider<RouterRefreshNotifier>((
  Ref ref,
) {
  final notifier = RouterRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// Creates a [GoRouter] configured with all application routes and redirect guards (§4.2).
GoRouter createRouter(Ref ref) {
  final refreshNotifier = ref.watch(routerRefreshNotifierProvider);

  return GoRouter(
    refreshListenable: refreshNotifier,
    initialLocation: '/',
    redirect: (BuildContext context, GoRouterState state) {
      final vaultState = ref.read(vaultControllerProvider);
      final loc = state.matchedLocation;

      // While initial storage check is pending, allow router to settle
      if (vaultState is VaultInitial) {
        return null;
      }

      final isOnboarding = loc == '/onboarding';
      final isUnlock = loc == '/unlock';

      // If no vault exists, route all traffic to /onboarding
      if (vaultState is VaultNoVault) {
        return isOnboarding ? null : '/onboarding';
      }

      // If locked or unlocking, lock clears stack to /unlock
      if (vaultState is VaultLocked || vaultState is VaultUnlocking) {
        if (vaultState is VaultUnlocking && vaultState.fromOnboarding) {
          return isOnboarding ? null : '/onboarding';
        }
        return isUnlock ? null : '/unlock';
      }

      // If unlocked, leave onboarding/unlock and navigate to home
      if (vaultState is VaultUnlocked) {
        if (isOnboarding || isUnlock) {
          return '/';
        }
        return null;
      }

      // Error state fallback to unlock
      if (vaultState is VaultError) {
        return isUnlock ? null : '/unlock';
      }

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/onboarding',
        builder: (BuildContext context, GoRouterState state) =>
            const OnboardingScreen(),
      ),
      GoRoute(
        path: '/unlock',
        builder: (BuildContext context, GoRouterState state) =>
            const UnlockScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            const EntriesListScreen(),
      ),
      GoRoute(
        path: '/add',
        builder: (BuildContext context, GoRouterState state) =>
            const AddHubScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'manual',
            builder: (BuildContext context, GoRouterState state) {
              OtpEntry? initialEntry;
              if (state.extra is OtpEntry) {
                initialEntry = state.extra as OtpEntry;
              } else if (state.extra is String) {
                try {
                  initialEntry = OtpAuthUri.parse(state.extra as String);
                } catch (_) {}
              } else if (state.uri.queryParameters.containsKey('uri')) {
                try {
                  initialEntry = OtpAuthUri.parse(
                    state.uri.queryParameters['uri']!,
                  );
                } catch (_) {}
              }
              return ManualEntryScreen(initialEntry: initialEntry);
            },
          ),
          GoRoute(
            path: 'scan',
            redirect: (BuildContext context, GoRouterState state) {
              if (!supportsCamera) {
                return '/add/manual';
              }
              return null;
            },
            builder: (BuildContext context, GoRouterState state) {
              final builder = state.extra is ScannerBuilder
                  ? state.extra as ScannerBuilder
                  : null;
              return ScanQrScreen(scannerBuilder: builder);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/entry/:id',
        builder: (BuildContext context, GoRouterState state) =>
            EntryDetailsScreen(id: state.pathParameters['id'] ?? ''),
        routes: <RouteBase>[
          GoRoute(
            path: 'edit',
            builder: (BuildContext context, GoRouterState state) =>
                EntryEditScreen(id: state.pathParameters['id'] ?? ''),
          ),
          GoRoute(
            path: 'reveal',
            builder: (BuildContext context, GoRouterState state) =>
                RevealScreen(id: state.pathParameters['id'] ?? ''),
          ),
        ],
      ),
      GoRoute(
        path: '/groups',
        builder: (BuildContext context, GoRouterState state) =>
            const GroupsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (BuildContext context, GoRouterState state) =>
            const SettingsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'change-password',
            builder: (BuildContext context, GoRouterState state) =>
                const ChangePasswordScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/backup',
        builder: (BuildContext context, GoRouterState state) =>
            const BackupScreen(),
      ),
    ],
  );
}

/// Global Riverpod provider for application routing (§4.2).
final routerProvider = Provider<GoRouter>((Ref ref) {
  final router = createRouter(ref);
  ref.onDispose(router.dispose);
  return router;
});
