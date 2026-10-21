import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/app.dart';
import 'package:offline2fa/core/crypto/kdf.dart';
import 'package:offline2fa/core/models/group.dart';
import 'package:offline2fa/core/models/otp_algorithm.dart';
import 'package:offline2fa/core/models/otp_entry.dart';
import 'package:offline2fa/core/models/otp_type.dart';
import 'package:offline2fa/core/vault/vault_codec.dart';
import 'package:offline2fa/core/vault/vault_errors.dart';
import 'package:offline2fa/core/vault/vault_payload.dart';
import 'package:offline2fa/router.dart';
import 'package:offline2fa/data/prefs_repository.dart';
import 'package:offline2fa/data/vault_controller.dart';
import 'package:offline2fa/data/vault_repository.dart';
import 'package:offline2fa/data/vault_storage.dart';
import 'package:offline2fa/features/backup/backup_screen.dart';
import 'package:offline2fa/shared/clipboard_service.dart';
import 'package:offline2fa/shared/file_picker_service.dart';
import 'package:offline2fa/shared/widgets/obscured_text_field.dart';
import 'package:qr_flutter/qr_flutter.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone M8 — Backup, Password Change & Reveal Tests', () {
    late FakeVaultStorage storage;
    late VaultRepository repository;
    late SharedPreferences prefs;
    late ProviderContainer container;
    late ClipboardService clipboardService;

    String? lastCopied;
    String? savedFileName;
    Uint8List? savedBytes;
    bool saverShouldSucceed = true;
    Uint8List? fileToPick;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'prefs_auto_lock_timeout': 0, // Never auto-lock during widget tests
        'prefs_lock_on_background': false,
      });
      prefs = await SharedPreferences.getInstance();
      storage = FakeVaultStorage();
      repository = VaultRepository(
        storage: storage,
        defaultKdfParams: KdfParams.testFast,
      );

      lastCopied = null;
      savedFileName = null;
      savedBytes = null;
      saverShouldSucceed = true;
      fileToPick = null;

      clipboardService = ClipboardService(
        clipboardWriter: (data) async {
          lastCopied = data.text;
        },
        clipboardReader: (_) async =>
            lastCopied != null ? ClipboardData(text: lastCopied!) : null,
      );

      Future<bool> fakeSaveVaultFile({
        required String fileName,
        required Uint8List bytes,
      }) async {
        if (!saverShouldSucceed) return false;
        savedFileName = fileName;
        savedBytes = bytes;
        return true;
      }

      Future<Uint8List?> fakePickVaultFile() async {
        return fileToPick;
      }

      container = ProviderContainer(
        overrides: [
          vaultStorageProvider.overrideWithValue(storage),
          vaultRepositoryProvider.overrideWithValue(repository),
          sharedPreferencesProvider.overrideWithValue(prefs),
          clipboardServiceProvider.overrideWithValue(clipboardService),
          saveVaultFileProvider.overrideWithValue(fakeSaveVaultFile),
          filePickerProvider.overrideWithValue(fakePickVaultFile),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      clipboardService.dispose();
    });

    Widget buildTestApp() {
      return UncontrolledProviderScope(
        container: container,
        child: const Offline2faApp(),
      );
    }

    Future<void> setupViewportAndUnlock(
      WidgetTester tester, {
      String password = 'password123',
    }) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      if (find.text('Unlock Vault').evaluate().isNotEmpty) {
        await tester.enterText(find.byType(TextField).first, password);
        await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
        await tester.pumpAndSettle();
      }
    }

    testWidgets(
      '1. Export flow: calls saveVaultFileProvider with valid .2favault bytes and YYYYMMDD-HHmm filename',
      (tester) async {
        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        // Add a sample entry to ensure exported bytes contain entries
        final testEntry = OtpEntry(
          id: 'test-totp-1',
          type: OtpType.totp,
          issuer: 'ExportService',
          account: 'user@export.test',
          secret: 'JBSWY3DPEHPK3PXP',
          algorithm: OtpAlgorithm.sha1,
          digits: 6,
          period: 30,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );
        await container
            .read(vaultControllerProvider.notifier)
            .addEntry(testEntry);
        await tester.pumpAndSettle();

        // Navigate to /backup via menu
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Backup'));
        await tester.pumpAndSettle();

        expect(find.text('Backup & Restore'), findsOneWidget);
        expect(
          find.text(
            'The file is encrypted with your current master password. Keep both safe.',
          ),
          findsOneWidget,
        );

        // Tap Export Vault button
        await tester.tap(find.widgetWithText(FilledButton, 'Export Vault'));
        await tester.pumpAndSettle();

        // Verify saveVaultFileProvider was called
        expect(savedFileName, isNotNull);
        final fileNameRegex = RegExp(
          r'^offline2fa-backup-\d{8}-\d{4}\.2favault$',
        );
        expect(fileNameRegex.hasMatch(savedFileName!), isTrue);

        expect(savedBytes, isNotNull);
        expect(savedBytes!.length, greaterThan(47));

        // Decrypt the exported bytes using the master password to verify validity
        final decrypted = await VaultCodec.decryptWithPassword(
          bytes: savedBytes!,
          password: 'password123',
        );
        expect(decrypted.payload.entries.length, equals(1));
        expect(decrypted.payload.entries.first.issuer, equals('ExportService'));

        // Success SnackBar is displayed
        expect(find.text('Vault exported successfully'), findsOneWidget);

        // Dismiss previous SnackBar before testing cancel
        ScaffoldMessenger.of(
          tester.element(find.text('Vault exported successfully')),
        ).hideCurrentSnackBar();
        await tester.pumpAndSettle();

        // Test cancel in saver does not show success SnackBar
        saverShouldSucceed = false;
        await tester.tap(find.widgetWithText(FilledButton, 'Export Vault'));
        await tester.pumpAndSettle();
        expect(find.text('Vault exported successfully'), findsNothing);
      },
    );

    testWidgets(
      '2. Import & Merge flow: prompts for file password, handles wrong password, and merges entries with MergeReport dialog',
      (tester) async {
        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        // Verify that the golden fixture v1_sample.2favault exists on disk
        final fixtureFile = File('test/fixtures/v1_sample.2favault');
        expect(
          fixtureFile.existsSync(),
          isTrue,
          reason: 'v1_sample.2favault must exist',
        );

        // Generate test vault bytes using testFast KDF parameters so decryption
        // runs synchronously in fakeAsync widget tests (§10)
        final fixturePayload = VaultPayload(
          schemaVersion: 1,
          createdAt: DateTime.now().toUtc(),
          modifiedAt: DateTime.now().toUtc(),
          groups: [
            const Group(
              id: '00000000-0000-4000-8000-000000000001',
              name: 'Work',
              sortOrder: 0,
            ),
            const Group(
              id: '00000000-0000-4000-8000-000000000002',
              name: 'Personal',
              sortOrder: 1,
            ),
          ],
          entries: [
            OtpEntry(
              id: '10000000-0000-4000-8000-000000000001',
              type: OtpType.totp,
              issuer: 'GitHub',
              account: 'alice@example.com',
              secret: 'JBSWY3DPEHPK3PXP',
              algorithm: OtpAlgorithm.sha1,
              digits: 6,
              period: 30,
              groupIds: const ['00000000-0000-4000-8000-000000000001'],
              createdAt: DateTime.now().toUtc(),
              updatedAt: DateTime.now().toUtc(),
            ),
            OtpEntry(
              id: '10000000-0000-4000-8000-000000000002',
              type: OtpType.hotp,
              issuer: 'Acme Corp',
              account: 'alice@acme.corp',
              secret: 'KRSXG5CTMVRXEZLU',
              algorithm: OtpAlgorithm.sha256,
              digits: 8,
              counter: 42,
              groupIds: const ['00000000-0000-4000-8000-000000000002'],
              createdAt: DateTime.now().toUtc(),
              updatedAt: DateTime.now().toUtc(),
            ),
          ],
        );

        final fixtureResult = await VaultCodec.encryptWithPassword(
          payload: fixturePayload,
          password: 'correct horse battery staple',
          kdfParams: KdfParams.testFast,
        );
        fileToPick = fixtureResult.bytes;

        // Navigate to /backup
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Backup'));
        await tester.pumpAndSettle();

        // Tap Import & Merge Vault
        await tester.tap(
          find.widgetWithText(FilledButton, 'Import & Merge Vault'),
        );
        await tester.pumpAndSettle();

        // Password prompt dialog for imported file
        expect(find.text('Unlock Imported Vault'), findsOneWidget);

        // 2a. Enter wrong password
        final passwordField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(passwordField, 'wrong-imported-password');
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Import & Merge'),
          ),
        );
        await tester.pumpAndSettle();

        // Error SnackBar displayed
        expect(find.text('Wrong password or corrupted file'), findsOneWidget);

        // 2b. Enter correct password "correct horse battery staple"
        await tester.tap(
          find.widgetWithText(FilledButton, 'Import & Merge Vault'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Unlock Imported Vault'), findsOneWidget);

        final passwordField2 = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(passwordField2, 'correct horse battery staple');
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Import & Merge'),
          ),
        );
        await tester.pumpAndSettle();

        // MergeReport dialog is displayed
        expect(find.byType(MergeReportDialog), findsOneWidget);
        expect(find.text('Import Summary'), findsOneWidget);
        expect(find.text('Accounts added: 2'), findsOneWidget);
        expect(find.text('Duplicates skipped: 0'), findsOneWidget);
        expect(find.text('HOTP counters updated: 0'), findsOneWidget);
        expect(find.text('Groups created: 2'), findsOneWidget);
        expect(find.text('Invalid entries skipped: 0'), findsOneWidget);

        // Tap OK on the dialog
        await tester.tap(find.widgetWithText(TextButton, 'OK'));
        await tester.pumpAndSettle();
        expect(find.byType(MergeReportDialog), findsNothing);

        // 2c. Re-importing same vault skips duplicates
        await tester.tap(
          find.widgetWithText(FilledButton, 'Import & Merge Vault'),
        );
        await tester.pumpAndSettle();

        final passwordField3 = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(passwordField3, 'correct horse battery staple');
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Import & Merge'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(MergeReportDialog), findsOneWidget);
        expect(find.text('Accounts added: 0'), findsOneWidget);
        expect(find.text('Duplicates skipped: 2'), findsOneWidget);
        expect(find.text('Groups created: 0'), findsOneWidget);

        await tester.tap(find.widgetWithText(TextButton, 'OK'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      '3. Change Master Password flow: validates current password, rotates encryption, and updates unlock credentials',
      (tester) async {
        await repository.createVault('oldPassword123');
        await setupViewportAndUnlock(tester, password: 'oldPassword123');

        // Navigate to /settings
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('Change Master Password'), findsOneWidget);

        // Tap Change Master Password tile
        await tester.tap(find.text('Change Master Password'));
        await tester.pumpAndSettle();

        expect(find.text('Change Master Password'), findsWidgets);
        expect(
          find.text(
            'There is NO password recovery. If you forget your new master password, your vault cannot be recovered.',
          ),
          findsOneWidget,
        );

        final textFields = find.byType(TextFormField);
        expect(textFields, findsNWidgets(3));

        // 3a. Form validation (min 8 chars, mismatch)
        final currentField = textFields.at(0);
        final newField = textFields.at(1);
        final confirmField = textFields.at(2);

        await tester.enterText(currentField, 'wrongPassword');
        await tester.enterText(newField, 'short');
        await tester.enterText(confirmField, 'short2');
        await tester.pumpAndSettle();

        expect(
          find.text('New password must be at least 8 characters'),
          findsOneWidget,
        );
        expect(find.text('Passwords do not match'), findsOneWidget);

        // Submit button should be disabled
        final changeButton = find.widgetWithText(
          FilledButton,
          'Change Password',
        );
        final buttonWidget = tester.widget<FilledButton>(changeButton);
        expect(buttonWidget.onPressed, isNull);

        // 3b. Wrong current password
        await tester.enterText(newField, 'brandNewPassword123');
        await tester.enterText(confirmField, 'brandNewPassword123');
        await tester.pumpAndSettle();

        expect(tester.widget<FilledButton>(changeButton).onPressed, isNotNull);
        await tester.tap(changeButton);
        await tester.pumpAndSettle();

        expect(find.text('Current password is incorrect'), findsWidgets);

        // 3c. Valid password change
        await tester.enterText(currentField, 'oldPassword123');
        await tester.pumpAndSettle();
        await tester.tap(changeButton);
        await tester.pumpAndSettle();

        // Successful change pops back to /settings and shows SnackBar
        expect(
          find.text('Master password changed successfully'),
          findsOneWidget,
        );
        expect(find.text('Settings'), findsOneWidget);

        // 3d. Verify lock and subsequent unlock requires the new password
        await container.read(vaultControllerProvider.notifier).lock();
        await tester.pumpAndSettle();

        expect(find.text('Unlock Vault'), findsOneWidget);

        // Unlock with old password fails
        await tester.enterText(find.byType(TextField).first, 'oldPassword123');
        await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
        await tester.pumpAndSettle();

        expect(find.text('Wrong password or corrupted file'), findsOneWidget);

        // Unlock with new password succeeds
        await tester.enterText(
          find.byType(TextField).first,
          'brandNewPassword123',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
        await tester.pumpAndSettle();

        expect(find.text('Unlock Vault'), findsNothing);
      },
    );

    testWidgets(
      '4. Reveal Screen flow: gated by master password, obscured secret/URI by default, toggles eye, copies with auto-clear, reveals QR code',
      (tester) async {
        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        // Add entry with known credentials
        const entryId = 'reveal-test-entry-1';
        final entry = OtpEntry(
          id: entryId,
          type: OtpType.totp,
          issuer: 'GitHub',
          account: 'alice@example.com',
          secret: 'JBSWY3DPEHPK3PXP',
          algorithm: OtpAlgorithm.sha1,
          digits: 6,
          period: 30,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );
        await container.read(vaultControllerProvider.notifier).addEntry(entry);
        await tester.pumpAndSettle();

        // Open entry reveal screen via entry tile popup menu
        await tester.tap(find.byTooltip('More options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reveal secret'));
        await tester.pumpAndSettle();

        // Step 1: Password Gate (must NOT render secret, URI, or QR)
        expect(find.text('Re-enter Master Password'), findsOneWidget);
        expect(
          find.text(
            'Please re-enter your master password to reveal sensitive account details.',
          ),
          findsOneWidget,
        );
        expect(find.text('JBSWY3DPEHPK3PXP'), findsNothing);
        expect(find.textContaining('otpauth://'), findsNothing);
        expect(find.text('Tap to show QR'), findsNothing);
        expect(find.byType(QrImageView), findsNothing);

        // 4a. Wrong password attempt
        final passwordField = find.byType(TextFormField);
        await tester.enterText(passwordField, 'wrongpass');
        await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
        await tester.pumpAndSettle();

        expect(find.text('Incorrect master password'), findsOneWidget);
        expect(find.text('JBSWY3DPEHPK3PXP'), findsNothing);

        // 4b. Correct password verification
        await tester.enterText(passwordField, 'password123');
        await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
        await tester.pumpAndSettle();

        // Step 2: Revealed View
        expect(
          find.text('Anyone with this QR or secret can generate your codes.'),
          findsOneWidget,
        );

        // Both Secret and URI fields are present and obscured by default
        final obscuredFields = tester.widgetList<ObscuredTextField>(
          find.byType(ObscuredTextField),
        );
        expect(obscuredFields.length, equals(2));
        for (final field in obscuredFields) {
          expect(field.readOnly, isTrue);
          expect(field.obscureByDefault, isTrue);
        }

        final editableTexts = tester.widgetList<EditableText>(
          find.byType(EditableText),
        );
        expect(editableTexts.length, equals(2));
        for (final et in editableTexts) {
          expect(et.obscureText, isTrue);
        }

        // Tap eye toggle on Secret to reveal
        final eyeButtons = find.byTooltip('Show password');
        expect(eyeButtons, findsNWidgets(2));
        await tester.tap(eyeButtons.first);
        await tester.pumpAndSettle();

        final updatedEditableTexts = tester.widgetList<EditableText>(
          find.byType(EditableText),
        );
        expect(updatedEditableTexts.first.obscureText, isFalse);
        expect(updatedEditableTexts.last.obscureText, isTrue);

        // Tap Copy secret
        final copySecretButton = find.byTooltip('Copy secret');
        expect(copySecretButton, findsOneWidget);
        await tester.tap(copySecretButton);
        await tester.pumpAndSettle();

        expect(lastCopied, equals('JBSWY3DPEHPK3PXP'));
        expect(find.text('Copied — clears in 30 s'), findsOneWidget);

        // Tap Copy URI
        final copyUriButton = find.byTooltip('Copy URI');
        expect(copyUriButton, findsOneWidget);
        await tester.tap(copyUriButton);
        await tester.pumpAndSettle();

        expect(
          lastCopied,
          contains(
            'otpauth://totp/GitHub:alice%40example.com?secret=JBSWY3DPEHPK3PXP',
          ),
        );

        // QR Code is hidden behind "Tap to show QR"
        expect(find.text('Tap to show QR'), findsOneWidget);
        expect(find.byType(QrImageView), findsNothing);

        // Tap to reveal QR code
        await tester.tap(find.text('Tap to show QR'));
        await tester.pumpAndSettle();

        expect(find.byType(QrImageView), findsOneWidget);
        final qrWidget = tester.widget<QrImageView>(find.byType(QrImageView));
        expect(qrWidget.size, equals(220));
        expect(qrWidget.backgroundColor, equals(Colors.white));

        // Tap "Hide QR"
        expect(find.text('Hide QR'), findsOneWidget);
        await tester.tap(find.text('Hide QR'));
        await tester.pumpAndSettle();

        expect(find.byType(QrImageView), findsNothing);
        expect(find.text('Tap to show QR'), findsOneWidget);

        // 4c. Leaving the screen discards verified state
        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.text('GitHub'), findsOneWidget);

        // Return to reveal screen: must prompt for password again!
        await tester.tap(find.byTooltip('More options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reveal secret'));
        await tester.pumpAndSettle();

        expect(find.text('Re-enter Master Password'), findsOneWidget);
        expect(find.text('JBSWY3DPEHPK3PXP'), findsNothing);
        expect(find.byType(QrImageView), findsNothing);

        // Advance past clipboard auto-clear timer
        await tester.pump(const Duration(seconds: 31));
      },
    );

    test('generateVaultBackupFileName correctly zero-pads date and time (§7.1 #11)', () {
      final dt = DateTime(2026, 4, 5, 8, 9);
      expect(
        generateVaultBackupFileName(dt),
        equals('offline2fa-backup-20260405-0809.2favault'),
      );
    });

    testWidgets(
      'RevealScreen displays "Account not found" when entry does not exist',
      (tester) async {
        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        // Open reveal screen for non-existent entry id
        final router = container.read(routerProvider);
        router.go('/entry/non-existent-id/reveal');
        await tester.pumpAndSettle();

        expect(find.text('Account not found'), findsOneWidget);
      },
    );

    testWidgets(
      'F-02: Export flow: lifecycle paused/resumed while saveVaultFile awaits does not lock the vault',
      (tester) async {
        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        final saveCompleter = Completer<bool>();
        container.updateOverrides([
          vaultStorageProvider.overrideWithValue(storage),
          vaultRepositoryProvider.overrideWithValue(repository),
          sharedPreferencesProvider.overrideWithValue(prefs),
          clipboardServiceProvider.overrideWithValue(clipboardService),
          saveVaultFileProvider.overrideWithValue(({
            required String fileName,
            required Uint8List bytes,
          }) async {
            return saveCompleter.future;
          }),
          filePickerProvider.overrideWithValue(() async => null),
        ]);

        final router = container.read(routerProvider);
        router.go('/backup');
        await tester.pumpAndSettle();

        // Tap Export Vault button
        await tester.tap(find.widgetWithText(FilledButton, 'Export Vault'));
        await tester.pump();

        // Simulate app paused and then resumed while picker is open
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(container.read(vaultControllerProvider), isA<VaultUnlocked>());

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(container.read(vaultControllerProvider), isA<VaultUnlocked>());

        saveCompleter.complete(true);
        await tester.pumpAndSettle();

        expect(find.text('Vault exported successfully'), findsOneWidget);
        expect(container.read(vaultControllerProvider), isA<VaultUnlocked>());
      },
    );

    testWidgets(
      'F-02: Import flow: lifecycle paused/resumed while filePicker awaits does not lock the vault',
      (tester) async {
        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        final pickCompleter = Completer<Uint8List?>();
        container.updateOverrides([
          vaultStorageProvider.overrideWithValue(storage),
          vaultRepositoryProvider.overrideWithValue(repository),
          sharedPreferencesProvider.overrideWithValue(prefs),
          clipboardServiceProvider.overrideWithValue(clipboardService),
          saveVaultFileProvider.overrideWithValue(
            ({required String fileName, required Uint8List bytes}) async =>
                true,
          ),
          filePickerProvider.overrideWithValue(() => pickCompleter.future),
        ]);

        final router = container.read(routerProvider);
        router.go('/backup');
        await tester.pumpAndSettle();

        await tester.tap(
          find.widgetWithText(FilledButton, 'Import & Merge Vault'),
        );
        await tester.pump();

        // Simulate picker opening (lifecycle paused then resumed)
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(container.read(vaultControllerProvider), isA<VaultUnlocked>());

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(container.read(vaultControllerProvider), isA<VaultUnlocked>());

        final importedBytes = (await VaultCodec.encryptWithPassword(
          payload: VaultPayload.empty(),
          password: 'pass',
          kdfParams: KdfParams.testFast,
        )).bytes;
        pickCompleter.complete(importedBytes);
        await tester.pumpAndSettle();

        // Password prompt should appear since BackupScreen remained mounted
        expect(find.text('Unlock Imported Vault'), findsOneWidget);
      },
    );
  });
}
