import 'dart:async';

import 'package:flutter/foundation.dart';

/// Service managing inactivity timeouts and app lifecycle lock triggers.
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
  }
}
