import 'dart:async';

import 'package:flutter/services.dart';

/// Service that copies text to the clipboard and automatically clears it after a delay.
class ClipboardService {
  ClipboardService({this.defaultClearDelay = const Duration(seconds: 30)});

  final Duration defaultClearDelay;
  Timer? _clearTimer;
  String? _lastCopiedText;

  Future<void> copyWithAutoClear(String text, {Duration? clearDelay}) async {
    _clearTimer?.cancel();
    _lastCopiedText = text;
    await Clipboard.setData(ClipboardData(text: text));

    final Duration delay = clearDelay ?? defaultClearDelay;
    if (delay > Duration.zero) {
      _clearTimer = Timer(delay, () async {
        final ClipboardData? current = await Clipboard.getData(
          Clipboard.kTextPlain,
        );
        if (current?.text == _lastCopiedText) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      });
    }
  }

  void dispose() {
    _clearTimer?.cancel();
  }
}
