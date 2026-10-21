import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/shared/widgets/busy_overlay.dart';
import 'package:offline2fa/shared/widgets/confirm_dialog.dart';
import 'package:offline2fa/shared/widgets/obscured_text_field.dart';
import 'package:offline2fa/shared/widgets/password_prompt_dialog.dart';
import 'package:offline2fa/shared/widgets/responsive_wrapper.dart';

void main() {
  group('ObscuredTextField', () {
    testWidgets('toggles obscurity when eye icon is clicked', (
      WidgetTester tester,
    ) async {
      final controller = TextEditingController(text: 'SecretPass123');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ObscuredTextField(
              controller: controller,
              labelText: 'Password',
            ),
          ),
        ),
      );

      // Initially obscured
      final editableText = tester.widget<EditableText>(
        find.byType(EditableText),
      );
      expect(editableText.obscureText, isTrue);
      expect(find.byTooltip('Show password'), findsOneWidget);

      // Tap toggle to show password
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();

      final editableTextRevealed = tester.widget<EditableText>(
        find.byType(EditableText),
      );
      expect(editableTextRevealed.obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);

      // Tap toggle again to obscure
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();

      final editableTextObscured = tester.widget<EditableText>(
        find.byType(EditableText),
      );
      expect(editableTextObscured.obscureText, isTrue);
    });

    testWidgets('displays error text and hint text', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ObscuredTextField(
              labelText: 'Master Password',
              hintText: 'Enter 8+ characters',
              errorText: 'Password too short',
            ),
          ),
        ),
      );

      expect(find.text('Master Password'), findsOneWidget);
      expect(find.text('Password too short'), findsOneWidget);
    });
  });

  group('PasswordPromptDialog', () {
    testWidgets('returns entered password on confirm', (
      WidgetTester tester,
    ) async {
      String? enteredResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () async {
                  enteredResult = await PasswordPromptDialog.show(
                    context,
                    title: 'Prompt Title',
                    message: 'Enter your password below',
                  );
                },
                child: const Text('Open Dialog'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Prompt Title'), findsOneWidget);
      expect(find.text('Enter your password below'), findsOneWidget);

      // Entering password and confirming
      await tester.enterText(find.byType(TextField), 'my-secret-password');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(enteredResult, equals('my-secret-password'));
    });

    testWidgets('returns null on cancel', (WidgetTester tester) async {
      String? enteredResult = 'initial';

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () async {
                  enteredResult = await PasswordPromptDialog.show(
                    context,
                    title: 'Prompt',
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(enteredResult, isNull);
    });

    testWidgets('validates non-empty password by default', (
      WidgetTester tester,
    ) async {
      String? enteredResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () async {
                  enteredResult = await PasswordPromptDialog.show(
                    context,
                    title: 'Prompt',
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap confirm with empty text
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('Password cannot be empty'), findsOneWidget);
      expect(enteredResult, isNull);
    });
  });

  group('ConfirmDialog', () {
    testWidgets('confirms normal confirmation without required text', (
      WidgetTester tester,
    ) async {
      bool? confirmed;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () async {
                  confirmed = await ConfirmDialog.show(
                    context,
                    title: 'Confirm Action',
                    message: 'Are you sure?',
                  );
                },
                child: const Text('Open Dialog'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Action'), findsOneWidget);
      expect(find.text('Are you sure?'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(confirmed, isTrue);
    });

    testWidgets(
      'enforces exact matching text when requiredConfirmationText is set',
      (WidgetTester tester) async {
        bool? confirmed;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (BuildContext context) {
                return ElevatedButton(
                  onPressed: () async {
                    confirmed = await ConfirmDialog.show(
                      context,
                      title: 'Delete Vault',
                      message: 'This will delete everything.',
                      requiredConfirmationText: 'DELETE',
                      isDestructive: true,
                      confirmLabel: 'Delete',
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        final buttonFinder = find.widgetWithText(FilledButton, 'Delete');
        expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNull);

        // Enter wrong text
        await tester.enterText(find.byType(TextField), 'del');
        await tester.pump();
        expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNull);

        // Enter exact matching text
        await tester.enterText(find.byType(TextField), 'DELETE');
        await tester.pump();
        expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNotNull);

        await tester.tap(buttonFinder);
        await tester.pumpAndSettle();

        expect(confirmed, isTrue);
      },
    );
  });

  group('BusyOverlay & ResponsiveContentWrapper', () {
    testWidgets('BusyOverlay displays spinner and message when busy', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BusyOverlay(
              isBusy: true,
              message: 'Generating key...',
              child: Text('Underlying Content'),
            ),
          ),
        ),
      );

      expect(find.text('Underlying Content'), findsOneWidget);
      expect(find.text('Generating key...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets(
      'ResponsiveContentWrapper constrains maxWidth on wide screens',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ResponsiveContentWrapper(child: Text('Responsive Child')),
            ),
          ),
        );

        final constrainedBoxFinder = find.descendant(
          of: find.byType(ResponsiveContentWrapper),
          matching: find.byType(ConstrainedBox),
        );
        expect(constrainedBoxFinder, findsOneWidget);
        final box = tester.widget<ConstrainedBox>(constrainedBoxFinder);
        expect(box.constraints.maxWidth, equals(720.0));
      },
    );
  });
}
