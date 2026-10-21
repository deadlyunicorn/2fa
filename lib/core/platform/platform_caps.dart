import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import 'platform_caps_stub.dart'
    if (dart.library.io) 'platform_caps_io.dart'
    as impl;

/// Test override for [supportsCamera]. Used in widget tests to simulate camera capabilities.
@visibleForTesting
bool? supportsCameraOverride;

/// Capabilities and runtime checks for platform-specific behavior (§8).
bool get supportsCamera =>
    supportsCameraOverride ??
    (!kIsWeb && (impl.isPlatformAndroid || impl.isPlatformIOS));

bool get isDesktop =>
    !kIsWeb &&
    (impl.isPlatformLinux || impl.isPlatformWindows || impl.isPlatformMacOS);

bool get isWeb => kIsWeb;
