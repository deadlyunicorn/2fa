import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/app.dart';
import 'package:offline2fa/core/crypto/kdf.dart';
import 'package:offline2fa/core/vault/vault_errors.dart';
import 'package:offline2fa/data/prefs_repository.dart';
import 'package:offline2fa/data/vault_repository.dart';
import 'package:offline2fa/data/vault_storage.dart';
import 'package:offline2fa/shared/file_picker_service.dart';
import 'package:offline2fa/shared/widgets/obscured_text_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeVaultStorage implements VaultStorage {
  Uint8List? _main;
  Uint8List? _bak;

  @override
  Future<bool> exists() async => _main != null;

  @override
  Future<bool> backupExists() async => _bak != null;

  @override
  Future<Uint8List> read() async {
    if (_main == null) {
      throw const VaultFileNotFound('Main vault not found');
    }
    return Uint8List.fromList(_main!);
  }

  @override
  Future<Uint8List> readBackup() async {
    if (_bak == null) {
      throw const VaultFileNotFound('Backup vault not found');
    }
    return Uint8List.fromList(_bak!);
  }

  @override
  Future<void> writeAtomic(Uint8List bytes) async {
    if (_main != null) {
      _bak = Uint8List.fromList(_main!);
    }
    _main = Uint8List.fromList(bytes);
  }

  @override
  Future<void> restoreBackup() async {
    if (_bak == null) {
      throw const VaultFileNotFound('No backup available');
    }
    _main = Uint8List.fromList(_bak!);
  }

  @override
  Future<void> delete() async {
    _main = null;
    _bak = null;
  }
}

void main() {
  group('M4 Onboarding & Lock Widget Tests', () {
    late FakeVaultStorage storage;
    late VaultRepository repository;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      storage = FakeVaultStorage();
      repository = VaultRepository(
        storage: storage,
        defaultKdfParams: KdfParams.testFast,
      );
    });

    Widget buildTestApp({
      FilePickerFn? filePicker,
      SharedPreferences? customPrefs,
    }) {
      return ProviderScope(
        overrides: [
          vaultStorageProvider.overrideWithValue(storage),
          vaultRepositoryProvider.overrideWithValue(repository),
          sharedPreferencesProvider.overrideWithValue(customPrefs ?? prefs),
          if (filePicker != null)
            filePickerProvider.overrideWithValue(filePicker),
        ],
        child: const Offline2faApp(),
      );
    }

    testWidgets(
      '1. Create vault flow: validation, disclaimer, creation, redirect to home',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        // 1. Starts on /onboarding
        expect(find.text('Create or Import Vault'), findsNothing);
        expect(find.text('Your codes never leave this device'), findsOneWidget);
        expect(find.text('Create vault'), findsOneWidget);

        final createButtonFinder = find.widgetWithText(
          FilledButton,
          'Create vault',
        );
        expect(
          tester.widget<FilledButton>(createButtonFinder).onPressed,
          isNull,
        );

        // Enter password shorter than 8 chars
        final passwordFields = find.byType(ObscuredTextField);
        expect(passwordFields, findsNWidgets(2));

        final passwordField = passwordFields.at(0);
        final confirmField = passwordFields.at(1);

        await tester.enterText(passwordField, 'short');
        await tester.pump();
        expect(
          find.text('Password must be at least 8 characters'),
          findsOneWidget,
        );

        // Enter valid password in field 1, mismatching in field 2
        await tester.enterText(passwordField, 'correct-horse-1');
        await tester.enterText(confirmField, 'mismatching-pass');
        await tester.pump();
        expect(find.text('Passwords do not match'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(createButtonFinder).onPressed,
          isNull,
        );

        // Fix confirm password to match
        await tester.enterText(confirmField, 'correct-horse-1');
        await tester.pump();
        expect(find.text('Passwords do not match'), findsNothing);

        // Checkbox must be ticked
        expect(
          tester.widget<FilledButton>(createButtonFinder).onPressed,
          isNull,
        );
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();

        // Button should now be enabled
        expect(
          tester.widget<FilledButton>(createButtonFinder).onPressed,
          isNotNull,
        );

        // Tap Create vault
        await tester.tap(createButtonFinder);
        await tester.pumpAndSettle();

        // Should land on home screen (/)
        expect(find.text('Offline 2FA'), findsOneWidget);
        expect(find.byTooltip('Lock vault'), findsOneWidget);
      },
    );

    testWidgets('2. Lock returns to unlock screen and clears stack', (
      WidgetTester tester,
    ) async {
      // Create vault beforehand
      await repository.createVault('password123');

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Starts on unlock screen
      expect(find.text('Unlock Vault'), findsOneWidget);
      await tester.enterText(find.byType(ObscuredTextField), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle();

      // Now on home screen
      expect(find.text('Offline 2FA'), findsOneWidget);
      expect(find.byTooltip('Lock vault'), findsOneWidget);

      // Tap lock button
      await tester.tap(find.byTooltip('Lock vault'));
      await tester.pumpAndSettle();

      // Now back on /unlock
      expect(find.text('Unlock Vault'), findsOneWidget);
      expect(find.text('Master Password'), findsOneWidget);
    });

    testWidgets(
      '3. Wrong password shows error, then correct password unlocks to home',
      (WidgetTester tester) async {
        // Setup vault with password
        await repository.createVault('correct-password-8');
        repository.lock();

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        // On unlock screen
        expect(find.text('Unlock Vault'), findsOneWidget);

        final passwordField = find.byType(ObscuredTextField);
        final unlockButton = find.widgetWithText(FilledButton, 'Unlock');

        // Enter wrong password
        await tester.enterText(passwordField, 'wrong-password-8');
        await tester.tap(unlockButton);
        await tester.pumpAndSettle();

        // Shows error text
        expect(find.text('Wrong password or corrupted file'), findsOneWidget);

        // Enter correct password
        await tester.enterText(passwordField, 'correct-password-8');
        await tester.tap(unlockButton);
        await tester.pumpAndSettle();

        // Redirects to home
        expect(find.text('Offline 2FA Entries'), findsOneWidget);
      },
    );

    testWidgets(
      '4. Reset app flow: menu -> confirmation dialog with DELETE -> redirects to onboarding',
      (WidgetTester tester) async {
        await repository.createVault('vault-pass-123');
        repository.lock();

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        // On /unlock
        expect(find.text('Unlock Vault'), findsOneWidget);

        // Open overflow menu
        await tester.tap(find.byTooltip('More options'));
        await tester.pumpAndSettle();

        // Select reset
        await tester.tap(find.text('Reset app (delete vault)'));
        await tester.pumpAndSettle();

        // Dialog appears
        expect(find.text('Reset App (Delete Vault)'), findsOneWidget);
        final deleteButtonFinder = find.widgetWithText(
          FilledButton,
          'Delete Vault',
        );
        expect(
          tester.widget<FilledButton>(deleteButtonFinder).onPressed,
          isNull,
        );

        // Type DELETE to confirm
        final dialogTextField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(dialogTextField, 'DELETE');
        await tester.pump();
        expect(
          tester.widget<FilledButton>(deleteButtonFinder).onPressed,
          isNotNull,
        );

        await tester.tap(deleteButtonFinder);
        await tester.pumpAndSettle();

        // Should have deleted vault and redirected to /onboarding
        expect(find.text('Your codes never leave this device'), findsOneWidget);
        expect(await storage.exists(), isFalse);
      },
    );

    testWidgets('5. Auto-lock on background lifecycle event', (
      WidgetTester tester,
    ) async {
      await repository.createVault('password123');

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Unlock first
      await tester.enterText(find.byType(ObscuredTextField), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle();

      // On home screen
      expect(find.text('Offline 2FA Entries'), findsOneWidget);

      // Simulate app going to background (paused / hidden) and returning
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Should automatically lock and redirect to /unlock
      expect(find.text('Unlock Vault'), findsOneWidget);
    });

    testWidgets('6. Auto-lock on inactivity timer expiration', (
      WidgetTester tester,
    ) async {
      // Set short auto-lock timeout (30 seconds) in prefs
      SharedPreferences.setMockInitialValues(<String, Object>{
        'prefs_auto_lock_timeout': 30,
      });
      final customPrefs = await SharedPreferences.getInstance();

      await repository.createVault('password123');

      await tester.pumpWidget(buildTestApp(customPrefs: customPrefs));
      await tester.pumpAndSettle();

      // Unlock first
      await tester.enterText(find.byType(ObscuredTextField), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle();

      // On home screen
      expect(find.text('Offline 2FA Entries'), findsOneWidget);

      // Advance time by 31 seconds
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();

      // Should lock and redirect to /unlock
      expect(find.text('Unlock Vault'), findsOneWidget);
    });

    testWidgets('7. Import existing vault flow during onboarding', (
      WidgetTester tester,
    ) async {
      // Prepare exportable vault bytes
      final tempRepo = VaultRepository(
        storage: FakeVaultStorage(),
        defaultKdfParams: KdfParams.testFast,
      );
      final payload = await tempRepo.createVault('external-pass');
      final exportBytes = await tempRepo.exportBytes(payload);

      await tester.pumpWidget(
        buildTestApp(filePicker: () async => exportBytes),
      );
      await tester.pumpAndSettle();

      // On onboarding screen
      expect(find.text('Import existing vault'), findsOneWidget);

      await tester.tap(find.text('Import existing vault'));
      await tester.pumpAndSettle();

      // Password prompt dialog appears
      expect(find.text('Import Vault'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'external-pass',
      );
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      // Unlocks and lands on home screen
      expect(find.text('Offline 2FA Entries'), findsOneWidget);
    });

    testWidgets('8. Restore from backup flow during unlock', (
      WidgetTester tester,
    ) async {
      // Set up storage with main and backup
      await repository.createVault('initial-pass');
      storage._bak = storage._main;
      repository.lock();

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Unlock Vault'), findsOneWidget);

      // Open overflow menu
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();

      expect(find.text('Restore from backup (.bak)'), findsOneWidget);
      await tester.tap(find.text('Restore from backup (.bak)'));
      await tester.pumpAndSettle();

      // Prompt for backup password
      expect(find.text('Restore Backup'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'initial-pass',
      );
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      // Successfully restored and unlocked
      expect(find.text('Offline 2FA Entries'), findsOneWidget);
    });

    testWidgets('9. User pointer activity resets inactivity timer', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'prefs_auto_lock_timeout': 30,
      });
      final customPrefs = await SharedPreferences.getInstance();

      await repository.createVault('password123');

      await tester.pumpWidget(buildTestApp(customPrefs: customPrefs));
      await tester.pumpAndSettle();

      // Unlock first
      await tester.enterText(find.byType(ObscuredTextField), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('Offline 2FA Entries'), findsOneWidget);

      // Advance 20 seconds
      await tester.pump(const Duration(seconds: 20));
      // User interacts: tap center of screen to reset timer
      await tester.tap(find.text('Offline 2FA Entries'));
      await tester.pump();

      // Advance another 20 seconds (total 40s from start, but only 20s from tap)
      await tester.pump(const Duration(seconds: 20));
      expect(find.text('Offline 2FA Entries'), findsOneWidget);

      // Advance another 15 seconds (35s from tap) -> timer fires
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();

      expect(find.text('Unlock Vault'), findsOneWidget);
    });

    testWidgets(
      '10. Throttle lockout display appears after 5 failed attempts',
      (WidgetTester tester) async {
        await repository.createVault('correct-pass-1');
        repository.lock();

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        final passwordField = find.byType(ObscuredTextField);
        final unlockButton = find.widgetWithText(FilledButton, 'Unlock');

        // Attempt 1 to 4: wrong password
        for (int i = 1; i <= 4; i++) {
          await tester.enterText(passwordField, 'wrong-pass');
          await tester.tap(unlockButton);
          await tester.pumpAndSettle();
          expect(find.text('Wrong password or corrupted file'), findsOneWidget);
          expect(find.textContaining('Too many attempts'), findsNothing);
        }

        // Attempt 5: triggers 1-second throttle
        await tester.enterText(passwordField, 'wrong-pass');
        await tester.tap(unlockButton);
        await tester.pumpAndSettle();

        expect(find.textContaining('Too many attempts'), findsOneWidget);
        // Unlock button is disabled while locked out
        expect(tester.widget<FilledButton>(unlockButton).onPressed, isNull);

        // Wait for 1.1 real seconds outside fakeAsync zone so DateTime.now() passes lockoutUntil
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 1100));
        });
        // Pump fakeAsync timer so Timer.periodic fires and setState triggers rebuild
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        // Lockout cleared, unlock button is enabled again
        expect(tester.widget<FilledButton>(unlockButton).onPressed, isNotNull);

        // Entering correct password successfully unlocks to home
        await tester.enterText(passwordField, 'correct-pass-1');
        await tester.tap(unlockButton);
        await tester.pumpAndSettle();

        expect(find.text('Offline 2FA Entries'), findsOneWidget);
      },
    );
  });
}
