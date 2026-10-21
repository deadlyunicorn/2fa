import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Service that copies text to the system clipboard and optionally auto-clears
/// it after a configured duration (§5.7).
class ClipboardService {
  ClipboardService({
    Future<void> Function(ClipboardData)? clipboardWriter,
    Future<ClipboardData?> Function(String)? clipboardReader,
  }) : _clipboardWriter = clipboardWriter ?? Clipboard.setData,
       _clipboardReader = clipboardReader ?? Clipboard.getData;

  final Future<void> Function(ClipboardData) _clipboardWriter;
  final Future<ClipboardData?> Function(String) _clipboardReader;

  Timer? _clearTimer;
  String? _lastCopiedText;

  /// Returns whether a clear timer is currently active.
  bool get hasActiveClearTimer => _clearTimer != null && _clearTimer!.isActive;

  /// Copies [code] to the clipboard and starts an auto-clear timer if [clearAfterSeconds] > 0.
  ///
  /// Returns a user-facing status message appropriate for a SnackBar:
  /// - `"Copied — clears in {N} s"` when [clearAfterSeconds] > 0
  /// - `"Copied to clipboard"` when [clearAfterSeconds] <= 0
  Future<String> copyCode(String code, {required int clearAfterSeconds}) async {
    _clearTimer?.cancel();
    _lastCopiedText = code;
    await _clipboardWriter(ClipboardData(text: code));

    if (clearAfterSeconds > 0) {
      _clearTimer = Timer(Duration(seconds: clearAfterSeconds), () async {
        final current = await _clipboardReader(Clipboard.kTextPlain);
        // Only clear if the clipboard still contains the exact text we copied (§5.7)
        if (current?.text == _lastCopiedText) {
          await _clipboardWriter(const ClipboardData(text: ''));
        }
      });
      return 'Copied — clears in $clearAfterSeconds s';
    } else {
      return 'Copied to clipboard';
    }
  }

  /// Backward-compatible helper using [Duration].
  Future<void> copyWithAutoClear(String text, {Duration? clearDelay}) async {
    final seconds = clearDelay?.inSeconds ?? 30;
    await copyCode(text, clearAfterSeconds: seconds);
  }

  /// Cancels any active auto-clear timer.
  void dispose() {
    _clearTimer?.cancel();
    _clearTimer = null;
  }
}

/// Global provider for [ClipboardService].
final clipboardServiceProvider = Provider<ClipboardService>((ref) {
  final service = ClipboardService();
  ref.onDispose(service.dispose);
  return service;
});
