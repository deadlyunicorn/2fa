import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/shared/widgets/code_text.dart';
import 'package:offline2fa/shared/widgets/countdown_ring.dart';
import 'package:offline2fa/shared/widgets/letter_avatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrapInApp(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('LetterAvatar', () {
    testWidgets('renders first letter of issuer in uppercase', (tester) async {
      await tester.pumpWidget(
        wrapInApp(const LetterAvatar(issuer: 'github', account: 'alice')),
      );

      expect(find.text('G'), findsOneWidget);
      expect(find.bySemanticsLabel('Avatar for github'), findsOneWidget);
    });

    testWidgets('falls back to account if issuer is empty', (tester) async {
      await tester.pumpWidget(
        wrapInApp(const LetterAvatar(issuer: '', account: 'bob@example.com')),
      );

      expect(find.text('B'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Avatar for bob@example.com'),
        findsOneWidget,
      );
    });

    testWidgets('falls back to "?" if both issuer and account are empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapInApp(const LetterAvatar(issuer: '   ', account: '')),
      );

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('deterministic colors for same issuer', (tester) async {
      await tester.pumpWidget(
        wrapInApp(
          const Column(
            children: <Widget>[
              LetterAvatar(issuer: 'Google'),
              LetterAvatar(issuer: 'Google'),
            ],
          ),
        ),
      );

      final containers = tester.widgetList<Container>(find.byType(Container));
      final color1 = (containers.first.decoration as BoxDecoration).color;
      final color2 = (containers.last.decoration as BoxDecoration).color;
      expect(color1, isNotNull);
      expect(color1, equals(color2));
    });
  });

  group('CountdownRing', () {
    testWidgets('displays remaining seconds and uses primary color when > 5s', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapInApp(const CountdownRing(remainingSeconds: 25, period: 30)),
      );

      expect(find.text('25'), findsOneWidget);
      expect(find.bySemanticsLabel('25 seconds remaining'), findsOneWidget);

      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.value, closeTo(25 / 30, 0.001));

      final text = tester.widget<Text>(find.text('25'));
      // Text color is not error red when > 5
      expect(text.style?.color, isNot(equals(Colors.red)));
    });

    testWidgets('turns error color when remainingSeconds <= 5', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              error: Colors.red,
            ),
          ),
          home: const Scaffold(
            body: Center(child: CountdownRing(remainingSeconds: 4, period: 30)),
          ),
        ),
      );

      expect(find.text('4'), findsOneWidget);

      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.value, closeTo(4 / 30, 0.001));
      final colorAnimation =
          indicator.valueColor as AlwaysStoppedAnimation<Color>;
      expect(colorAnimation.value, Colors.red);

      final text = tester.widget<Text>(find.text('4'));
      expect(text.style?.color, Colors.red);
    });
  });

  group('CodeText', () {
    test('formatCode groups digits cleanly', () {
      expect(CodeText.formatCode('123456'), '123 456');
      expect(CodeText.formatCode('1234567'), '123 4567');
      expect(CodeText.formatCode('12345678'), '1234 5678');
      expect(CodeText.formatCode('1234'), '1234');
      expect(CodeText.formatCode('1234567890'), '12345 67890');
    });

    test('spellingLabel splits digits with spaces', () {
      expect(CodeText.spellingLabel('123456'), '1 2 3 4 5 6');
      expect(CodeText.spellingLabel('123 456'), '1 2 3 4 5 6');
    });

    testWidgets('renders monospace font and semantic label', (tester) async {
      await tester.pumpWidget(wrapInApp(const CodeText(code: '123456')));

      expect(find.text('123 456'), findsOneWidget);
      expect(find.bySemanticsLabel('1 2 3 4 5 6'), findsOneWidget);

      final text = tester.widget<Text>(find.text('123 456'));
      expect(text.style?.fontFamily, 'monospace');
      expect(text.style?.fontFeatures, isNotNull);
    });

    testWidgets('renders faint code with reduced opacity', (tester) async {
      await tester.pumpWidget(
        wrapInApp(const CodeText(code: '654321', isFaint: true)),
      );

      expect(find.text('654 321'), findsOneWidget);
      final text = tester.widget<Text>(find.text('654 321'));
      expect(text.style?.color?.a, closeTo(0.38, 0.05));
    });
  });
}
