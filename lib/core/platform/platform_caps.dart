import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

/// Test override for [supportsCamera]. Used in widget tests to simulate camera capabilities.
@visibleForTesting
bool? supportsCameraOverride;

/// Capabilities and runtime checks for platform-specific behavior.
bool get supportsCamera =>
    supportsCameraOverride ??
    (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

bool get isDesktop =>
    !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

bool get isWeb => kIsWeb;
