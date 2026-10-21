import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Capabilities and runtime checks for platform-specific behavior.
bool get supportsCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

bool get isDesktop =>
    !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

bool get isWeb => kIsWeb;
