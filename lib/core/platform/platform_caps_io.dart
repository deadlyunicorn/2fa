import 'dart:io' show Platform;

/// Native platform detections using `dart:io`.
bool get isPlatformAndroid => Platform.isAndroid;
bool get isPlatformIOS => Platform.isIOS;
bool get isPlatformLinux => Platform.isLinux;
bool get isPlatformWindows => Platform.isWindows;
bool get isPlatformMacOS => Platform.isMacOS;
