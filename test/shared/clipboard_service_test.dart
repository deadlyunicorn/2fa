import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/shared/clipboard_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClipboardService', () {
    test(
      'copies code and returns message with countdown when delay > 0',
      () async {
        String? currentClipboard;
        final service = ClipboardService(
          clipboardWriter: (data) async {
            currentClipboard = data.text;
          },
          clipboardReader: (_) async => currentClipboard != null
              ? ClipboardData(text: currentClipboard!)
              : null,
        );

        final msg = await service.copyCode('123456', clearAfterSeconds: 30);
        expect(msg, 'Copied — clears in 30 s');
        expect(currentClipboard, '123456');
        expect(service.hasActiveClearTimer, isTrue);

        service.dispose();
      },
    );

    test('copies code without countdown when delay <= 0', () async {
      String? currentClipboard;
      final service = ClipboardService(
        clipboardWriter: (data) async {
          currentClipboard = data.text;
        },
        clipboardReader: (_) async => currentClipboard != null
            ? ClipboardData(text: currentClipboard!)
            : null,
      );

      final msg = await service.copyCode('123456', clearAfterSeconds: 0);
      expect(msg, 'Copied to clipboard');
      expect(currentClipboard, '123456');
      expect(service.hasActiveClearTimer, isFalse);

      service.dispose();
    });

    testWidgets('clears clipboard after N seconds if text matches', (
      tester,
    ) async {
      String? currentClipboard;
      final service = ClipboardService(
        clipboardWriter: (data) async {
          currentClipboard = data.text;
        },
        clipboardReader: (_) async => currentClipboard != null
            ? ClipboardData(text: currentClipboard!)
            : null,
      );

      await service.copyCode('654321', clearAfterSeconds: 15);
      expect(currentClipboard, '654321');
      expect(service.hasActiveClearTimer, isTrue);

      await tester.pump(const Duration(seconds: 14));
      expect(currentClipboard, '654321');

      await tester.pump(const Duration(seconds: 1));
      expect(currentClipboard, '');
      expect(service.hasActiveClearTimer, isFalse);
    });

    testWidgets(
      'does NOT clear clipboard if contents changed in the meantime',
      (tester) async {
        String? currentClipboard;
        final service = ClipboardService(
          clipboardWriter: (data) async {
            currentClipboard = data.text;
          },
          clipboardReader: (_) async => currentClipboard != null
              ? ClipboardData(text: currentClipboard!)
              : null,
        );

        await service.copyCode('654321', clearAfterSeconds: 30);
        expect(currentClipboard, '654321');

        // External change to clipboard
        await tester.pump(const Duration(seconds: 10));
        currentClipboard = 'user-copied-other-text';

        await tester.pump(const Duration(seconds: 20));
        // Clipboard should remain untouched
        expect(currentClipboard, 'user-copied-other-text');
      },
    );

    testWidgets('subsequent copy cancels prior timer', (tester) async {
      String? currentClipboard;
      final service = ClipboardService(
        clipboardWriter: (data) async {
          currentClipboard = data.text;
        },
        clipboardReader: (_) async => currentClipboard != null
            ? ClipboardData(text: currentClipboard!)
            : null,
      );

      await service.copyCode('code1', clearAfterSeconds: 20);
      await tester.pump(const Duration(seconds: 10));

      // Second copy
      await service.copyCode('code2', clearAfterSeconds: 20);
      expect(currentClipboard, 'code2');

      // Elapse past first timer (total 20s from start, but only 10s from second copy)
      await tester.pump(const Duration(seconds: 10));
      expect(currentClipboard, 'code2');

      // Elapse remaining 10s of second timer
      await tester.pump(const Duration(seconds: 10));
      expect(currentClipboard, '');
    });

    testWidgets('dispose cancels active timer', (tester) async {
      String? currentClipboard;
      final service = ClipboardService(
        clipboardWriter: (data) async {
          currentClipboard = data.text;
        },
        clipboardReader: (_) async => currentClipboard != null
            ? ClipboardData(text: currentClipboard!)
            : null,
      );

      await service.copyCode('code1', clearAfterSeconds: 20);
      expect(service.hasActiveClearTimer, isTrue);

      service.dispose();
      expect(service.hasActiveClearTimer, isFalse);

      await tester.pump(const Duration(seconds: 25));
      expect(currentClipboard, 'code1');
    });

    testWidgets('copyWithAutoClear delegates with duration correctly', (
      tester,
    ) async {
      String? currentClipboard;
      final service = ClipboardService(
        clipboardWriter: (data) async {
          currentClipboard = data.text;
        },
        clipboardReader: (_) async => currentClipboard != null
            ? ClipboardData(text: currentClipboard!)
            : null,
      );

      await service.copyWithAutoClear(
        'durationCode',
        clearDelay: const Duration(seconds: 5),
      );
      expect(currentClipboard, 'durationCode');

      await tester.pump(const Duration(seconds: 5));
      expect(currentClipboard, '');
    });
  });
}
