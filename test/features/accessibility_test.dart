import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/crypto/kdf.dart';
import 'package:offline2fa/core/models/group.dart';
import 'package:offline2fa/core/models/otp_algorithm.dart';
import 'package:offline2fa/core/models/otp_entry.dart';
import 'package:offline2fa/core/models/otp_type.dart';
import 'package:offline2fa/core/vault/vault_payload.dart';
import 'package:offline2fa/data/prefs_repository.dart';
import 'package:offline2fa/data/vault_controller.dart';
import 'package:offline2fa/data/vault_repository.dart';
import 'package:offline2fa/data/vault_storage.dart';
import 'package:offline2fa/features/add_entry/add_entry_screen.dart';
import 'package:offline2fa/features/backup/backup_screen.dart';
import 'package:offline2fa/features/entries/entries_screen.dart';
import 'package:offline2fa/features/lock/unlock_screen.dart';
import 'package:offline2fa/features/onboarding/onboarding_screen.dart';
import 'package:offline2fa/features/settings/settings_screen.dart';
import 'package:offline2fa/shared/widgets/code_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InMemoryVaultStorage implements VaultStorage {
  Uint8List? _bytes;

  @override
  Future<bool> exists() async => _bytes != null;

  @override
  Future<bool> backupExists() async => false;

  @override
  Future<Uint8List> read() async => _bytes ?? Uint8List(0);

  @override
  Future<Uint8List> readBackup() async => Uint8List(0);

  @override
  Future<void> writeAtomic(Uint8List bytes) async {
    _bytes = Uint8List.fromList(bytes);
  }

  @override
  Future<void> restoreBackup() async {}

  @override
  Future<void> delete() async {
    _bytes = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone M9 — Accessibility & Large Font Scaling (2.0x)', () {
    late SharedPreferences prefs;
    late InMemoryVaultStorage storage;
    late VaultRepository repository;

    final entry1 = OtpEntry(
      id: 'entry-1',
      type: OtpType.totp,
      issuer: 'GitHub',
      account: 'user@example.com',
      secret: 'JBSWY3DPEHPK3PXP',
      period: 30,
      digits: 6,
      algorithm: OtpAlgorithm.sha1,
      sortOrder: 0,
    );

    final entry2 = OtpEntry(
      id: 'entry-2',
      type: OtpType.hotp,
      issuer: 'Amazon AWS',
      account: 'admin@corp.internal',
      secret: 'JBSWY3DPEHPK3PXP',
      digits: 8,
      counter: 42,
      algorithm: OtpAlgorithm.sha256,
      sortOrder: 1,
    );

    const group1 = Group(id: 'g-1', name: 'Work', sortOrder: 0);
    const group2 = Group(id: 'g-2', name: 'Personal', sortOrder: 1);

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'prefs_theme_mode': 'system',
        'prefs_auto_lock_timeout': 60,
        'prefs_lock_on_background': true,
        'prefs_clipboard_clear_delay': 30,
      });
      prefs = await SharedPreferences.getInstance();
      storage = InMemoryVaultStorage();
      repository = VaultRepository(
        storage: storage,
        defaultKdfParams: KdfParams.testFast,
      );
    });

    Widget wrapWithLargeFont({
      required Widget child,
      required ProviderContainer container,
    }) {
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          builder: (context, widget) {
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2.0)),
              child: widget!,
            );
          },
          home: child,
        ),
      );
    }

    testWidgets('OnboardingScreen scales to 2.0x without overflow', (
      WidgetTester tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          vaultRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        wrapWithLargeFont(
          container: container,
          child: const OnboardingScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Offline 2FA'), findsOneWidget);
      expect(find.text('Create vault'), findsOneWidget);
    });

    testWidgets('UnlockScreen scales to 2.0x without overflow', (
      WidgetTester tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          vaultRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        wrapWithLargeFont(container: container, child: const UnlockScreen()),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Unlock Vault'), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);
    });

    testWidgets('EntriesListScreen scales to 2.0x without overflow', (
      WidgetTester tester,
    ) async {
      final payload = VaultPayload(
        createdAt: DateTime.now().toUtc(),
        modifiedAt: DateTime.now().toUtc(),
        entries: [entry1, entry2],
        groups: [group1, group2],
      );
      await repository.createVault('password123');
      await repository.unlock('password123');
      await repository.save(payload);

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          vaultRepositoryProvider.overrideWithValue(repository),
          vaultStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(vaultControllerProvider.notifier)
          .unlock('password123');

      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        wrapWithLargeFont(
          container: container,
          child: const EntriesListScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Amazon AWS'), findsOneWidget);
    });

    testWidgets('EntryDetailsScreen scales to 2.0x without overflow', (
      WidgetTester tester,
    ) async {
      final payload = VaultPayload(
        createdAt: DateTime.now().toUtc(),
        modifiedAt: DateTime.now().toUtc(),
        entries: [entry1],
      );
      await repository.createVault('password123');
      await repository.unlock('password123');
      await repository.save(payload);

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          vaultRepositoryProvider.overrideWithValue(repository),
          vaultStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(vaultControllerProvider.notifier)
          .unlock('password123');

      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        wrapWithLargeFont(
          container: container,
          child: EntryDetailsScreen(id: entry1.id),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('GitHub'), findsWidgets);
      expect(find.text('Account Details'), findsOneWidget);
    });

    testWidgets('SettingsScreen scales to 2.0x without overflow', (
      WidgetTester tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          vaultRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        wrapWithLargeFont(container: container, child: const SettingsScreen()),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
    });

    testWidgets(
      'AddHubScreen and ManualEntryScreen scale to 2.0x without overflow',
      (WidgetTester tester) async {
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            vaultRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);

        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          wrapWithLargeFont(container: container, child: const AddHubScreen()),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Add Account'), findsOneWidget);

        await tester.pumpWidget(
          wrapWithLargeFont(
            container: container,
            child: const ManualEntryScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Add Account'), findsOneWidget);
      },
    );

    testWidgets(
      'ChangePasswordScreen and BackupScreen scale to 2.0x without overflow',
      (WidgetTester tester) async {
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            vaultRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);

        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          wrapWithLargeFont(
            container: container,
            child: const ChangePasswordScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Change Master Password'), findsOneWidget);

        await tester.pumpWidget(
          wrapWithLargeFont(container: container, child: const BackupScreen()),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Backup & Restore'), findsOneWidget);
      },
    );

    testWidgets(
      'CodeText widget provides spelled-out accessibility semantics',
      (WidgetTester tester) async {
        const testCode = '755224';
        final spelling = CodeText.spellingLabel(testCode);
        expect(spelling, equals('7 5 5 2 2 4'));

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: CodeText(code: testCode)),
          ),
        );
        await tester.pumpAndSettle();

        final semantics = tester.getSemantics(find.byType(CodeText));
        expect(semantics.label, contains('7 5 5 2 2 4'));
      },
    );
  });
}
