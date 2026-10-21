import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/prefs_repository.dart';
import '../data/vault_controller.dart';

/// Pure service managing inactivity timeouts (§5.7).
class AutoLockService {
  AutoLockService({
    required this.onLock,
    this.inactivityTimeout = const Duration(minutes: 1),
  });

  final VoidCallback onLock;
  Duration inactivityTimeout;
  Timer? _inactivityTimer;

  void resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (inactivityTimeout > Duration.zero) {
      _inactivityTimer = Timer(inactivityTimeout, onLock);
    }
  }

  void stop() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }
}

/// Manages temporary suppression of auto-lock during external system picker interactions (§5.7).
class AutoLockSuppressNotifier extends Notifier<int> {
  DateTime? _graceUntil;

  @override
  int build() => 0;

  /// Returns true if auto-lock is currently suppressed or within the post-picker grace window.
  bool get isSuppressed {
    if (state > 0) return true;
    if (_graceUntil != null && DateTime.now().isBefore(_graceUntil!)) {
      return true;
    }
    return false;
  }

  /// Runs [action] while incrementing the suppression counter and setting a post-completion grace window.
  Future<T> runSuppressed<T>(Future<T> Function() action) async {
    state = state + 1;
    try {
      return await action();
    } finally {
      state = (state - 1).clamp(0, 999999);
      _graceUntil = DateTime.now().add(const Duration(seconds: 1));
    }
  }
}

/// Provider managing auto-lock suppression counter.
final autoLockSuppressProvider =
    NotifierProvider<AutoLockSuppressNotifier, int>(
      AutoLockSuppressNotifier.new,
    );

/// Global widget listening to user activity (pointer + keyboard) and lifecycle states
/// to enforce auto-lock and background lock runtime protections (§5.7, §9 M4).
class AutoLockListener extends ConsumerStatefulWidget {
  const AutoLockListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AutoLockListener> createState() => _AutoLockListenerState();
}

class _AutoLockListenerState extends ConsumerState<AutoLockListener>
    with WidgetsBindingObserver {
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetInactivityTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelInactivityTimer();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final suppressor = ref.read(autoLockSuppressProvider.notifier);
    if (suppressor.isSuppressed) {
      if (state == AppLifecycleState.resumed) {
        _resetInactivityTimer();
      }
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      final prefs = ref.read(prefsProvider);
      final vaultState = ref.read(vaultControllerProvider);
      if (prefs.lockOnBackground && vaultState is VaultUnlocked) {
        ref.read(vaultControllerProvider.notifier).lock();
      }
    } else if (state == AppLifecycleState.resumed) {
      _resetInactivityTimer();
    }
  }

  void _cancelInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  void _resetInactivityTimer() {
    _cancelInactivityTimer();

    final vaultState = ref.read(vaultControllerProvider);
    if (vaultState is! VaultUnlocked) return;

    final prefs = ref.read(prefsProvider);
    final timeoutSeconds = prefs.autoLockTimeoutSeconds;
    if (timeoutSeconds <= 0) return; // 0 = Never

    _inactivityTimer = Timer(Duration(seconds: timeoutSeconds), () {
      final currentVaultState = ref.read(vaultControllerProvider);
      if (currentVaultState is VaultUnlocked) {
        ref.read(vaultControllerProvider.notifier).lock();
      }
    });
  }

  void _onUserActivity() {
    _resetInactivityTimer();
  }

  @override
  Widget build(BuildContext context) {
    // React to vault transitions (unlocking starts timer, locking cancels)
    ref.listen<VaultState>(vaultControllerProvider, (previous, next) {
      if (next is VaultUnlocked) {
        _resetInactivityTimer();
      } else {
        _cancelInactivityTimer();
      }
    });

    // React to preference changes
    ref.listen<AppPrefs>(prefsProvider, (previous, next) {
      _resetInactivityTimer();
    });

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onUserActivity(),
      onPointerMove: (_) => _onUserActivity(),
      onPointerSignal: (_) => _onUserActivity(),
      child: Focus(
        onKeyEvent: (FocusNode node, KeyEvent event) {
          _onUserActivity();
          return KeyEventResult.ignored;
        },
        child: widget.child,
      ),
    );
  }
}
