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
import 'package:offline2fa/core/vault/vault_errors.dart';
import 'package:offline2fa/core/vault/vault_payload.dart';
import 'package:offline2fa/data/prefs_repository.dart';
import 'package:offline2fa/data/vault_repository.dart';
import 'package:offline2fa/data/vault_storage.dart';
import 'package:offline2fa/features/entries/entries_screen.dart';
import 'package:offline2fa/shared/clipboard_service.dart';
import 'package:offline2fa/shared/widgets/code_text.dart';
import 'package:offline2fa/shared/widgets/countdown_ring.dart';
import 'package:offline2fa/shared/widgets/letter_avatar.dart';
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

  group('M5 Entries Feature & Widget Tests', () {
    late FakeVaultStorage storage;
    late VaultRepository repository;
    late SharedPreferences prefs;
    late String? lastCopied;
    late ClipboardService clipboardService;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      storage = FakeVaultStorage();
      repository = VaultRepository(
        storage: storage,
        defaultKdfParams: KdfParams.testFast,
      );
      lastCopied = null;
      clipboardService = ClipboardService(
        clipboardWriter: (data) async {
          lastCopied = data.text;
        },
        clipboardReader: (_) async =>
            lastCopied != null ? ClipboardData(text: lastCopied!) : null,
      );
    });

    tearDown(() {
      clipboardService.dispose();
    });

    Widget buildTestApp() {
      return ProviderScope(
        overrides: [
          vaultStorageProvider.overrideWithValue(storage),
          vaultRepositoryProvider.overrideWithValue(repository),
          sharedPreferencesProvider.overrideWithValue(prefs),
          clipboardServiceProvider.overrideWithValue(clipboardService),
        ],
        child: const Offline2faApp(),
      );
    }

    Future<void> setupViewportAndUnlock(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      if (find.text('Unlock Vault').evaluate().isNotEmpty) {
        await tester.enterText(find.byType(TextField).first, 'password123');
        await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
        await tester.pumpAndSettle();
      }
    }

    testWidgets(
      '1. Empty state displays illustration and navigates to Add Hub',
      (tester) async {
        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        // Home empty state
        expect(find.text('No accounts yet'), findsOneWidget);
        expect(
          find.text(
            'Add your first 2FA account to start generating offline codes.',
          ),
          findsOneWidget,
        );

        // Tap 'Add your first account'
        await tester.tap(
          find.widgetWithText(FilledButton, 'Add your first account'),
        );
        await tester.pumpAndSettle();

        // Lands on /add (AddHubScreen)
        expect(find.text('Add Account'), findsOneWidget);
        expect(find.text('Enter Manually'), findsOneWidget);

        // Tap 'Enter Manually'
        await tester.tap(find.widgetWithText(FilledButton, 'Enter Manually'));
        await tester.pumpAndSettle();

        // Lands on /add/manual (ManualEntryScreen)
        expect(find.text('New Account'), findsOneWidget);
      },
    );

    testWidgets(
      '2. ManualEntryScreen validation: prevents invalid save, previews valid code',
      (tester) async {
        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        // Navigate to /add/manual via FAB
        await tester.tap(find.byTooltip('Add account'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Enter Manually'));
        await tester.pumpAndSettle();

        // Try saving with everything empty
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Add Account'),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add Account'));
        await tester.pumpAndSettle();

        // Should show validation errors
        expect(
          find.text('Please enter either an issuer or account name'),
          findsAtLeastNWidgets(1),
        );
        expect(find.text('Secret is required'), findsOneWidget);

        // Enter issuer
        final textFields = find.byType(TextFormField);
        // textFields: 0: URI, 1: Issuer, 2: Account, 3: Secret
        await tester.enterText(textFields.at(1), 'GitHub');
        await tester.pumpAndSettle();

        // Enter invalid secret
        await tester.enterText(textFields.at(3), '12389!invalid');
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Add Account'),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add Account'));
        await tester.pumpAndSettle();
        expect(find.text('Invalid Base32 secret key'), findsOneWidget);
        expect(find.text('Live Code Preview'), findsNothing);

        // Enter valid secret
        await tester.enterText(textFields.at(3), 'JBSWY3DPEHPK3PXP');
        await tester.pumpAndSettle();

        // Live Code Preview should appear
        expect(find.text('Live Code Preview'), findsOneWidget);
        expect(find.byType(CodeText), findsOneWidget);
        expect(find.byType(CountdownRing), findsOneWidget);

        // Tap Add Account
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Add Account'),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add Account'));
        await tester.pumpAndSettle();

        // Returned to home screen, entry is now rendered
        expect(find.text('No accounts yet'), findsNothing);
        expect(find.text('GitHub'), findsOneWidget);
        expect(find.byType(EntryTile), findsOneWidget);
      },
    );

    testWidgets(
      '3. Pasting otpauth URI populates form, migration URI displays error',
      (tester) async {
        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        await tester.tap(find.byTooltip('Add account'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Enter Manually'));
        await tester.pumpAndSettle();

        final uriField = find.byType(TextFormField).first;

        // 1. Paste migration URI
        await tester.enterText(
          uriField,
          'otpauth-migration://offline2fa?data=CiMK',
        );
        await tester.pumpAndSettle();
        expect(find.text('Not supported yet'), findsOneWidget);

        // 2. Paste valid otpauth URI
        await tester.enterText(
          uriField,
          'otpauth://totp/GitLab:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitLab&algorithm=SHA256&digits=8&period=60',
        );
        await tester.pumpAndSettle();

        expect(find.text('URI parsed successfully!'), findsOneWidget);
        expect(find.text('GitLab'), findsOneWidget);
        expect(find.text('alice@example.com'), findsOneWidget);
        expect(find.text('Live Code Preview'), findsOneWidget);

        // Tap Add Account
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Add Account'),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add Account'));
        await tester.pumpAndSettle();

        expect(find.text('GitLab'), findsOneWidget);
        expect(find.text('alice@example.com'), findsOneWidget);
      },
    );

    testWidgets(
      '4. EntryTile renders grouped code, tap copies to clipboard with SnackBar',
      (tester) async {
        final payload = VaultPayload(
          createdAt: DateTime.now().toUtc(),
          modifiedAt: DateTime.now().toUtc(),
          entries: [
            OtpEntry(
              id: 'e1',
              type: OtpType.totp,
              issuer: 'Google',
              account: 'user@google.com',
              secret: 'JBSWY3DPEHPK3PXP',
              digits: 6,
              period: 30,
            ),
          ],
        );
        await repository.createVault('password123');
        await repository.unlock('password123');
        await repository.save(payload);

        await setupViewportAndUnlock(tester);

        // Verify tile elements
        expect(find.text('Google'), findsOneWidget);
        expect(find.text('user@google.com'), findsOneWidget);
        expect(find.byType(LetterAvatar), findsOneWidget);
        expect(find.byType(CountdownRing), findsOneWidget);

        final codeFinder = find.byType(CodeText).first;
        expect(codeFinder, findsOneWidget);
        final renderedCode = tester.widget<CodeText>(codeFinder).code;
        expect(renderedCode.length, 6);

        // Tap tile to copy
        await tester.tap(find.byType(EntryTile));
        await tester.pump();

        // Check clipboard was updated
        expect(lastCopied, renderedCode);

        // Check SnackBar message
        expect(find.text('Copied — clears in 30 s'), findsOneWidget);

        // Advance past clipboard clear timer
        await tester.pump(const Duration(seconds: 30));
        await tester.pumpAndSettle();
      },
    );

    testWidgets('5. HOTP entry displays refresh button and increments counter', (
      tester,
    ) async {
      final payload = VaultPayload(
        createdAt: DateTime.now().toUtc(),
        modifiedAt: DateTime.now().toUtc(),
        entries: [
          OtpEntry(
            id: 'hotp-1',
            type: OtpType.hotp,
            issuer: 'YubiKey',
            account: 'hw@test.com',
            secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', // 12345678901234567890
            counter: 0,
            digits: 6,
          ),
        ],
      );
      await repository.createVault('password123');
      await repository.unlock('password123');
      await repository.save(payload);

      await setupViewportAndUnlock(tester);

      // Counter 0 code for RFC 4226 test vector: 755224 -> formatted '755 224'
      expect(find.text('755 224'), findsOneWidget);
      expect(find.byTooltip('Next HOTP code'), findsOneWidget);

      // Tap refresh
      await tester.tap(find.byTooltip('Next HOTP code'));
      await tester.pumpAndSettle();

      // Counter 1 code for RFC 4226 test vector: 287082 -> formatted '287 082'
      expect(find.text('287 082'), findsOneWidget);
    });

    testWidgets(
      '6. Search query filters accounts, hides drag handles, and clears search',
      (tester) async {
        final payload = VaultPayload(
          createdAt: DateTime.now().toUtc(),
          modifiedAt: DateTime.now().toUtc(),
          entries: [
            OtpEntry(
              id: '1',
              type: OtpType.totp,
              issuer: 'GitHub',
              account: 'dev@github.com',
              secret: 'JBSWY3DPEHPK3PXP',
              sortOrder: 0,
            ),
            OtpEntry(
              id: '2',
              type: OtpType.totp,
              issuer: 'Amazon',
              account: 'buyer@amazon.com',
              secret: 'JBSWY3DPEHPK3PXP',
              sortOrder: 1,
            ),
          ],
        );
        await repository.createVault('password123');
        await repository.unlock('password123');
        await repository.save(payload);

        await setupViewportAndUnlock(tester);

        // Both entries visible
        expect(find.text('GitHub'), findsOneWidget);
        expect(find.text('Amazon'), findsOneWidget);

        // Reordering drag handles visible when search is empty
        expect(find.byType(ReorderableDragStartListener), findsNWidgets(2));

        // Open search
        await tester.tap(find.byTooltip('Search'));
        await tester.pumpAndSettle();

        // Enter search term
        await tester.enterText(find.byType(TextField), 'git');
        await tester.pumpAndSettle();

        // Only GitHub is shown
        expect(find.text('GitHub'), findsOneWidget);
        expect(find.text('Amazon'), findsNothing);

        // Drag handles are hidden while searching
        expect(find.byType(ReorderableDragStartListener), findsNothing);

        // Close search
        await tester.tap(find.byTooltip('Close search'));
        await tester.pumpAndSettle();

        // Both are back, drag handles restored
        expect(find.text('GitHub'), findsOneWidget);
        expect(find.text('Amazon'), findsOneWidget);
        expect(find.byType(ReorderableDragStartListener), findsNWidgets(2));
      },
    );

    testWidgets('7. Group filter chips filter list and hide drag handles', (
      tester,
    ) async {
      const group1 = Group(id: 'g1', name: 'Work', sortOrder: 0);
      final payload = VaultPayload(
        createdAt: DateTime.now().toUtc(),
        modifiedAt: DateTime.now().toUtc(),
        groups: [group1],
        entries: [
          OtpEntry(
            id: '1',
            type: OtpType.totp,
            issuer: 'WorkEmail',
            account: 'work@corp.com',
            secret: 'JBSWY3DPEHPK3PXP',
            groupIds: ['g1'],
          ),
          OtpEntry(
            id: '2',
            type: OtpType.totp,
            issuer: 'PersonalSteam',
            account: 'gamer',
            secret: 'JBSWY3DPEHPK3PXP',
          ),
        ],
      );
      await repository.createVault('password123');
      await repository.unlock('password123');
      await repository.save(payload);

      await setupViewportAndUnlock(tester);

      // Filter chips row
      expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Work'), findsOneWidget);

      // Both visible initially
      expect(find.text('WorkEmail'), findsOneWidget);
      expect(find.text('PersonalSteam'), findsOneWidget);

      // Select 'Work'
      await tester.tap(find.widgetWithText(ChoiceChip, 'Work'));
      await tester.pumpAndSettle();

      // Only WorkEmail shown
      expect(find.text('WorkEmail'), findsOneWidget);
      expect(find.text('PersonalSteam'), findsNothing);
      expect(find.byType(ReorderableDragStartListener), findsNothing);

      // Switch back to 'All'
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();

      expect(find.text('WorkEmail'), findsOneWidget);
      expect(find.text('PersonalSteam'), findsOneWidget);
      expect(find.byType(ReorderableDragStartListener), findsNWidgets(2));
    });

    testWidgets(
      '8. EntryDetailsScreen displays metadata, copies code, and deletes entry',
      (tester) async {
        final entry = OtpEntry(
          id: 'entry-details-test',
          type: OtpType.totp,
          issuer: 'ProtonMail',
          account: 'privacy@pm.me',
          secret: 'JBSWY3DPEHPK3PXP',
          digits: 6,
          period: 30,
          algorithm: OtpAlgorithm.sha256,
          note: 'Backup codes in vault note',
        );
        final payload = VaultPayload(
          createdAt: DateTime.now().toUtc(),
          modifiedAt: DateTime.now().toUtc(),
          entries: [entry],
        );
        await repository.createVault('password123');
        await repository.unlock('password123');
        await repository.save(payload);

        await setupViewportAndUnlock(tester);

        // Open details via more options menu
        await tester.tap(find.byTooltip('More options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Details'));
        await tester.pumpAndSettle();

        // Details screen elements
        expect(find.text('Account Details'), findsOneWidget);
        expect(find.text('ProtonMail'), findsOneWidget);
        expect(find.text('privacy@pm.me'), findsOneWidget);
        expect(find.text('SHA256'), findsOneWidget);
        expect(find.text('6 digits'), findsOneWidget);
        expect(find.text('30 seconds'), findsOneWidget);
        expect(find.text('Backup codes in vault note'), findsOneWidget);

        // Tap Copy button
        await tester.tap(find.byTooltip('Copy code'));
        await tester.pump();
        expect(find.text('Copied — clears in 30 s'), findsOneWidget);
        expect(lastCopied, isNotNull);

        // Tap Delete Account
        await tester.ensureVisible(
          find.widgetWithText(TextButton, 'Delete Account'),
        );
        await tester.tap(find.widgetWithText(TextButton, 'Delete Account'));
        await tester.pumpAndSettle();

        // Confirm dialog appears
        expect(find.text('Delete account'), findsOneWidget);
        expect(
          find.text(
            'Are you sure you want to delete "ProtonMail"? This action cannot be undone.',
          ),
          findsOneWidget,
        );

        // Confirm deletion
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await tester.pumpAndSettle();

        // Returned to home screen, entry is gone
        expect(find.text('No accounts yet'), findsOneWidget);

        // Advance past clipboard clear timer
        await tester.pump(const Duration(seconds: 30));
        await tester.pumpAndSettle();
      },
    );

    testWidgets('9. Edit existing entry preserves ID and updates fields', (
      tester,
    ) async {
      final entry = OtpEntry(
        id: 'entry-to-edit',
        type: OtpType.totp,
        issuer: 'OriginalIssuer',
        account: 'original@test.com',
        secret: 'JBSWY3DPEHPK3PXP',
      );
      final payload = VaultPayload(
        createdAt: DateTime.now().toUtc(),
        modifiedAt: DateTime.now().toUtc(),
        entries: [entry],
      );
      await repository.createVault('password123');
      await repository.unlock('password123');
      await repository.save(payload);

      await setupViewportAndUnlock(tester);

      // Open Edit from tile popup menu
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Account'), findsOneWidget);

      // Change issuer to 'UpdatedIssuer'
      final textFields = find.byType(TextFormField);
      // In edit mode: textFields: 0: Issuer, 1: Account, 2: Secret
      await tester.enterText(textFields.at(0), 'UpdatedIssuer');
      await tester.pumpAndSettle();

      // Save changes
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Save changes'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      // Home shows updated issuer
      expect(find.text('UpdatedIssuer'), findsOneWidget);
      expect(find.text('OriginalIssuer'), findsNothing);
    });
  });
}
