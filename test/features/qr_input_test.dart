import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:offline2fa/app.dart';
import 'package:offline2fa/core/crypto/kdf.dart';
import 'package:offline2fa/core/platform/platform_caps.dart';
import 'package:offline2fa/core/vault/vault_errors.dart';
import 'package:offline2fa/data/prefs_repository.dart';
import 'package:offline2fa/data/vault_repository.dart';
import 'package:offline2fa/data/vault_storage.dart';
import 'package:offline2fa/features/add_entry/add_entry_screen.dart';
import 'package:offline2fa/features/entries/entries_screen.dart';
import 'package:offline2fa/shared/clipboard_service.dart';
import 'package:offline2fa/shared/file_picker_service.dart';
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

  group('M6 QR Input Feature & Widget Tests', () {
    late FakeVaultStorage storage;
    late VaultRepository repository;
    late SharedPreferences prefs;
    late ClipboardService clipboardService;

    late Uint8List validTotpPngBytes;
    late Uint8List noQrPngBytes;

    Uint8List? mockPickedImageBytes;
    String? Function(Uint8List bytes)? mockQrDecoderOverride;

    setUpAll(() {
      validTotpPngBytes = File('test/fixtures/qr/valid_totp.png')
          .readAsBytesSync();
      noQrPngBytes = File('test/fixtures/qr/no_qr.png').readAsBytesSync();
    });

    setUp(() async {
      supportsCameraOverride = null;
      mockPickedImageBytes = null;
      mockQrDecoderOverride = null;

      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      storage = FakeVaultStorage();
      repository = VaultRepository(
        storage: storage,
        defaultKdfParams: KdfParams.testFast,
      );
      clipboardService = ClipboardService(
        clipboardWriter: (_) async {},
        clipboardReader: (_) async => null,
      );
    });

    tearDown(() {
      supportsCameraOverride = null;
      clipboardService.dispose();
    });

    Widget buildTestApp() {
      return ProviderScope(
        overrides: [
          vaultStorageProvider.overrideWithValue(storage),
          vaultRepositoryProvider.overrideWithValue(repository),
          sharedPreferencesProvider.overrideWithValue(prefs),
          clipboardServiceProvider.overrideWithValue(clipboardService),
          imagePickerProvider.overrideWithValue(
            () async => mockPickedImageBytes,
          ),
          qrImageDecoderProvider.overrideWithValue((bytes) async {
            if (mockQrDecoderOverride != null) {
              return mockQrDecoderOverride!(bytes);
            }
            return decodeQrFromImageBytesSync(bytes);
          }),
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
      '1. Desktop Add Hub prioritizes manual entry and excludes camera',
      (tester) async {
        // By default on Linux, supportsCamera is false
        expect(supportsCamera, isFalse);

        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        // Navigate to Add Hub
        await tester.tap(find.byTooltip('Add account'));
        await tester.pumpAndSettle();

        // On desktop:
        // "Enter Manually" is the primary button
        expect(
          find.widgetWithText(FilledButton, 'Enter Manually'),
          findsOneWidget,
        );
        // "Load QR from Image File" is secondary
        expect(
          find.widgetWithText(OutlinedButton, 'Load QR from Image File'),
          findsOneWidget,
        );
        // "Scan QR Code" is NOT shown
        expect(find.text('Scan QR Code'), findsNothing);
        expect(find.byType(MobileScanner), findsNothing);

        // Direct navigation to /add/scan on desktop redirects to /add/manual
        final navContext = tester.element(find.byType(AddHubScreen));
        GoRouter.of(navContext).go('/add/scan');
        await tester.pumpAndSettle();

        // Should have redirected to manual entry
        expect(find.byType(ManualEntryScreen), findsOneWidget);
        expect(find.byType(MobileScanner), findsNothing);
      },
    );

    testWidgets(
      '2. ScanQrScreen on desktop renders fallback without MobileScanner',
      (tester) async {
        expect(supportsCamera, isFalse);

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ScanQrScreen())),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Camera scanning is not supported on this platform.'),
          findsOneWidget,
        );
        expect(find.byType(MobileScanner), findsNothing);
      },
    );

    testWidgets('3. Mobile Add Hub prioritizes camera scan when supported', (
      tester,
    ) async {
      supportsCameraOverride = true;
      expect(supportsCamera, isTrue);

      await repository.createVault('password123');
      await setupViewportAndUnlock(tester);

      // Navigate to Add Hub
      await tester.tap(find.byTooltip('Add account'));
      await tester.pumpAndSettle();

      // On mobile:
      // "Scan QR Code" is the primary button
      expect(find.widgetWithText(FilledButton, 'Scan QR Code'), findsOneWidget);
      // "Enter Manually" is secondary
      expect(
        find.widgetWithText(OutlinedButton, 'Enter Manually'),
        findsOneWidget,
      );
      // "Import QR from Image" is tertiary
      expect(
        find.widgetWithText(OutlinedButton, 'Import QR from Image'),
        findsOneWidget,
      );
    });

    testWidgets('4. Image import from Add Hub pre-fills form with valid QR', (
      tester,
    ) async {
      mockPickedImageBytes = validTotpPngBytes;

      await repository.createVault('password123');
      await setupViewportAndUnlock(tester);

      await tester.tap(find.byTooltip('Add account'));
      await tester.pumpAndSettle();

      // Tap Load QR from Image File
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Load QR from Image File'),
      );
      await tester.pumpAndSettle();

      // Should have decoded valid_totp.png and navigated to ManualEntryScreen pre-filled!
      expect(find.byType(ManualEntryScreen), findsOneWidget);
      expect(find.widgetWithText(TextField, 'GitHub'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'alice@example.com'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextField, 'JBSWY3DPEHPK3PXP'),
        findsOneWidget,
      );
    });

    testWidgets('5. Image import shows SnackBar when no QR code found', (
      tester,
    ) async {
      mockPickedImageBytes = noQrPngBytes;

      await repository.createVault('password123');
      await setupViewportAndUnlock(tester);

      await tester.tap(find.byTooltip('Add account'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Load QR from Image File'),
      );
      await tester.pumpAndSettle();

      expect(find.text('No QR code found in image'), findsOneWidget);
      expect(find.byType(AddHubScreen), findsOneWidget);
    });

    testWidgets('6. Image import shows SnackBar on otpauth-migration scheme', (
      tester,
    ) async {
      mockPickedImageBytes = Uint8List.fromList(<int>[1, 2, 3]);
      mockQrDecoderOverride = (_) =>
          'otpauth-migration://offline2fa?data=CiMK...';

      await repository.createVault('password123');
      await setupViewportAndUnlock(tester);

      await tester.tap(find.byTooltip('Add account'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Load QR from Image File'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not supported yet'), findsOneWidget);
      expect(find.byType(AddHubScreen), findsOneWidget);
    });

    testWidgets('7. Image import shows SnackBar on invalid URI', (
      tester,
    ) async {
      mockPickedImageBytes = Uint8List.fromList(<int>[1, 2, 3]);
      mockQrDecoderOverride = (_) => 'https://example.com/not-2fa';

      await repository.createVault('password123');
      await setupViewportAndUnlock(tester);

      await tester.tap(find.byTooltip('Add account'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Load QR from Image File'),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Unsupported URI scheme'), findsOneWidget);
      expect(find.byType(AddHubScreen), findsOneWidget);
    });

    testWidgets(
      '8. ScanQrScreen barcode detection: valid URI navigates to manual pre-filled',
      (tester) async {
        supportsCameraOverride = true;
        late void Function(BarcodeCapture) testDetector;

        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        final navContext = tester.element(find.byType(EntriesListScreen));
        unawaited(
          GoRouter.of(navContext).push(
            '/add/scan',
            extra:
                (BuildContext context, void Function(BarcodeCapture) onDetect) {
                  testDetector = onDetect;
                  return const Center(child: Text('Custom Scanner View'));
                },
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Custom Scanner View'), findsOneWidget);

        // Simulate camera detecting a valid TOTP barcode
        const validUri =
            'otpauth://totp/AcmeCorp:charlie@acme.com?secret=JBSWY3DPEHPK3PXP&issuer=AcmeCorp';
        testDetector(
          const BarcodeCapture(
            barcodes: <Barcode>[Barcode(rawValue: validUri)],
          ),
        );
        await tester.pumpAndSettle();

        // Verified: navigated to manual form pre-filled with AcmeCorp and charlie@acme.com!
        expect(find.byType(ManualEntryScreen), findsOneWidget);
        expect(find.widgetWithText(TextField, 'AcmeCorp'), findsOneWidget);
        expect(
          find.widgetWithText(TextField, 'charlie@acme.com'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(TextField, 'JBSWY3DPEHPK3PXP'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '9. ScanQrScreen barcode detection: migration URI shows SnackBar and stays',
      (tester) async {
        supportsCameraOverride = true;
        late void Function(BarcodeCapture) testDetector;

        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        final navContext = tester.element(find.byType(EntriesListScreen));
        unawaited(
          GoRouter.of(navContext).push(
            '/add/scan',
            extra:
                (BuildContext context, void Function(BarcodeCapture) onDetect) {
                  testDetector = onDetect;
                  return const Center(child: Text('Custom Scanner View'));
                },
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Custom Scanner View'), findsOneWidget);

        // Simulate detecting migration QR
        testDetector(
          const BarcodeCapture(
            barcodes: <Barcode>[
              Barcode(rawValue: 'otpauth-migration://offline2fa?data=abc'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Not supported yet'), findsOneWidget);
        expect(find.text('Custom Scanner View'), findsOneWidget);
      },
    );

    testWidgets('10. ScanQrScreen gallery button imports image and navigates', (
      tester,
    ) async {
      supportsCameraOverride = true;
      mockPickedImageBytes = validTotpPngBytes;

      await repository.createVault('password123');
      await setupViewportAndUnlock(tester);

      final navContext = tester.element(find.byType(EntriesListScreen));
      unawaited(
        GoRouter.of(navContext).push(
          '/add/scan',
          extra:
              (BuildContext context, void Function(BarcodeCapture) onDetect) {
                return const Center(child: Text('Custom Scanner View'));
              },
        ),
      );
      await tester.pumpAndSettle();

      // Tap gallery button in AppBar
      await tester.tap(find.byTooltip('Import QR from image'));
      await tester.pumpAndSettle();

      // Pre-filled on manual entry screen
      expect(find.byType(ManualEntryScreen), findsOneWidget);
      expect(find.widgetWithText(TextField, 'GitHub'), findsOneWidget);
    });
  });
}
