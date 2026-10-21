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
import 'package:offline2fa/features/backup/backup_screen.dart';
import 'package:offline2fa/shared/file_picker_service.dart';
import 'package:offline2fa/shared/widgets/code_text.dart';
import 'package:offline2fa/shared/widgets/obscured_text_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InMemoryVaultStorage implements VaultStorage {
  Uint8List? _main;
  Uint8List? _bak;

  @override
  Future<bool> exists() async => _main != null;

  @override
  Future<bool> backupExists() async => _bak != null;

  @override
  Future<Uint8List> read() async {
    if (_main == null) {
      throw const VaultFileNotFound('Vault file not found');
    }
    return Uint8List.fromList(_main!);
  }

  @override
  Future<Uint8List> readBackup() async {
    if (_bak == null) {
      throw const VaultFileNotFound('Backup file not found');
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone M9 — Full End-to-End Application Flow Test (§9 M9, §10)', () {
    late InMemoryVaultStorage storage;
    late VaultRepository repository;
    late SharedPreferences prefs;

    Uint8List? exportedVaultBytes;
    Uint8List? fileBytesToPick;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'prefs_auto_lock_timeout': 0, // Never auto-lock during flow test
        'prefs_lock_on_background': false,
      });
      prefs = await SharedPreferences.getInstance();
      storage = InMemoryVaultStorage();
      repository = VaultRepository(
        storage: storage,
        defaultKdfParams: KdfParams.testFast,
      );

      exportedVaultBytes = null;
      fileBytesToPick = null;
    });

    Widget createTestApp() {
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          vaultStorageProvider.overrideWithValue(storage),
          vaultRepositoryProvider.overrideWithValue(repository),
          saveVaultFileProvider.overrideWithValue(({
            required String fileName,
            required Uint8List bytes,
          }) async {
            exportedVaultBytes = Uint8List.fromList(bytes);
            return true;
          }),
          filePickerProvider.overrideWithValue(() async {
            return fileBytesToPick;
          }),
        ],
        child: const Offline2faApp(),
      );
    }

    testWidgets(
      'Full lifecycle: create vault -> add manual TOTP -> lock -> unlock -> export -> reset -> import merge',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // ---------------------------------------------------------------------
        // STEP 1: CREATE VAULT
        // ---------------------------------------------------------------------
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();

        // Starts on /onboarding
        expect(find.text('Offline 2FA'), findsOneWidget);
        expect(find.text('Your codes never leave this device'), findsOneWidget);

        // Enter master password & confirmation
        final passwordFields = find.byType(ObscuredTextField);
        expect(passwordFields, findsNWidgets(2));
        await tester.enterText(passwordFields.at(0), 'Password123!');
        await tester.enterText(passwordFields.at(1), 'Password123!');
        await tester.pump();

        // Accept disclaimer checkbox
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();

        // Tap Create vault
        final createVaultBtn = find.widgetWithText(
          FilledButton,
          'Create vault',
        );
        expect(createVaultBtn, findsOneWidget);
        await tester.tap(createVaultBtn);
        await tester.pumpAndSettle();

        // Lands on / (Home entries list)
        expect(find.text('No accounts yet'), findsOneWidget);

        // ---------------------------------------------------------------------
        // STEP 2: ADD MANUAL TOTP
        // ---------------------------------------------------------------------
        await tester.tap(
          find.widgetWithText(FilledButton, 'Add your first account'),
        );
        await tester.pumpAndSettle();

        // Lands on /add
        expect(find.text('Add Account'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Enter Manually'));
        await tester.pumpAndSettle();

        // Lands on /add/manual
        expect(find.text('New Account'), findsOneWidget);

        // Fill form: Issuer, Account, Secret
        await tester.enterText(
          find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Issuer',
          ),
          'GitHub',
        );
        await tester.enterText(
          find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.decoration?.labelText == 'Account / Username',
          ),
          'user@example.com',
        );

        final manualSecretField = find.byWidgetPredicate(
          (w) => w is ObscuredTextField && w.labelText == 'Secret key',
        );
        await tester.enterText(manualSecretField, 'JBSWY3DPEHPK3PXP');
        await tester.pumpAndSettle();

        // Save entry
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Add Account'),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add Account'));
        await tester.pumpAndSettle();

        // Back on /
        expect(find.text('GitHub'), findsOneWidget);
        expect(find.text('user@example.com'), findsOneWidget);

        final codeTextFinder = find.byWidgetPredicate(
          (w) => w is CodeText && !w.isFaint,
        );
        expect(codeTextFinder, findsOneWidget);
        final initialCodeWidget = tester.widget<CodeText>(codeTextFinder);
        final generatedCode = initialCodeWidget.code;
        expect(generatedCode.length, equals(6));

        // ---------------------------------------------------------------------
        // STEP 3: LOCK VAULT
        // ---------------------------------------------------------------------
        await tester.tap(find.byTooltip('Lock vault'));
        await tester.pumpAndSettle();

        // Lands on /unlock
        expect(find.text('Unlock Vault'), findsOneWidget);
        expect(
          find.text('Enter your master password to unlock'),
          findsOneWidget,
        );

        // ---------------------------------------------------------------------
        // STEP 4: UNLOCK VAULT
        // ---------------------------------------------------------------------
        final unlockPasswordField = find.byType(ObscuredTextField);
        await tester.enterText(unlockPasswordField, 'Password123!');
        await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
        await tester.pumpAndSettle();

        // Back on /
        expect(find.text('GitHub'), findsOneWidget);
        expect(find.text('user@example.com'), findsOneWidget);

        // ---------------------------------------------------------------------
        // STEP 5: EXPORT VAULT
        // ---------------------------------------------------------------------
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Backup'));
        await tester.pumpAndSettle();

        // Lands on /backup
        expect(find.text('Backup & Restore'), findsOneWidget);
        expect(find.text('Export Encrypted Vault'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Export Vault'));
        await tester.pumpAndSettle();

        expect(exportedVaultBytes, isNotNull);
        expect(exportedVaultBytes!.length, greaterThan(47));
        expect(find.text('Vault exported successfully'), findsOneWidget);

        // ---------------------------------------------------------------------
        // STEP 6: RESET APP (DELETE VAULT)
        // ---------------------------------------------------------------------
        // Pop back to /
        tester.state<NavigatorState>(find.byType(Navigator).last).pop();
        await tester.pumpAndSettle();

        // Lock vault
        await tester.tap(find.byTooltip('Lock vault'));
        await tester.pumpAndSettle();
        expect(find.text('Unlock Vault'), findsOneWidget);

        // On /unlock, open menu -> Reset app (delete vault)
        await tester.tap(find.byTooltip('More options'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Reset app (delete vault)'));
        await tester.pumpAndSettle();

        // Confirm dialog: type 'DELETE'
        final deleteConfirmField = find.byType(TextField).last;
        await tester.enterText(deleteConfirmField, 'DELETE');
        await tester.pump();

        await tester.tap(find.widgetWithText(FilledButton, 'Delete Vault'));
        await tester.pumpAndSettle();

        // Redirected to /onboarding
        expect(find.text('Offline 2FA'), findsOneWidget);
        expect(find.text('Create vault'), findsOneWidget);
        expect(await storage.exists(), isFalse);

        // ---------------------------------------------------------------------
        // STEP 7: IMPORT & MERGE EXPORTED VAULT
        // ---------------------------------------------------------------------
        // Create a new vault with a different password
        final newPasswordFields = find.byType(ObscuredTextField);
        await tester.enterText(
          newPasswordFields.at(0),
          'DifferentPassword456!',
        );
        await tester.enterText(
          newPasswordFields.at(1),
          'DifferentPassword456!',
        );
        await tester.pump();

        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();

        await tester.tap(find.widgetWithText(FilledButton, 'Create vault'));
        await tester.pumpAndSettle();

        // Lands on / with new empty vault
        expect(find.text('No accounts yet'), findsOneWidget);

        // Navigate to /backup to merge the exported vault
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Backup'));
        await tester.pumpAndSettle();

        // Set picker to return our previously exported bytes
        fileBytesToPick = exportedVaultBytes;

        // Tap Import & Merge
        await tester.tap(
          find.widgetWithText(FilledButton, 'Import & Merge Vault'),
        );
        await tester.pumpAndSettle();

        // Password prompt appears for the imported file
        expect(find.text('Unlock Imported Vault'), findsOneWidget);
        final importPasswordField = find.byType(ObscuredTextField);
        // Enter the password of the exported file
        await tester.enterText(importPasswordField, 'Password123!');
        await tester.tap(find.widgetWithText(FilledButton, 'Import & Merge'));
        await tester.pumpAndSettle();

        // Merge report dialog appears
        expect(find.byType(MergeReportDialog), findsOneWidget);
        expect(find.text('Import Summary'), findsOneWidget);
        expect(find.text('Accounts added: 1'), findsOneWidget);

        // Dismiss dialog
        await tester.tap(find.widgetWithText(TextButton, 'OK'));
        await tester.pumpAndSettle();

        // Pop back to /
        tester.state<NavigatorState>(find.byType(Navigator).last).pop();
        await tester.pumpAndSettle();

        // Verify GitHub account restored and code matches
        expect(find.text('GitHub'), findsOneWidget);
        expect(find.text('user@example.com'), findsOneWidget);

        final restoredCodeWidget = tester.widget<CodeText>(
          find.byWidgetPredicate((w) => w is CodeText && !w.isFaint),
        );
        expect(restoredCodeWidget.code, equals(generatedCode));
      },
    );
  });
}
