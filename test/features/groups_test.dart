import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/app.dart';
import 'package:offline2fa/core/crypto/kdf.dart';
import 'package:offline2fa/core/models/group.dart';
import 'package:offline2fa/core/models/otp_entry.dart';
import 'package:offline2fa/core/models/otp_type.dart';
import 'package:offline2fa/core/vault/vault_errors.dart';
import 'package:offline2fa/data/prefs_repository.dart';
import 'package:offline2fa/data/vault_controller.dart';
import 'package:offline2fa/data/vault_repository.dart';
import 'package:offline2fa/data/vault_storage.dart';
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

  group('M7 Groups Feature & Widget Tests', () {
    late FakeVaultStorage storage;
    late VaultRepository repository;
    late SharedPreferences prefs;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      storage = FakeVaultStorage();
      repository = VaultRepository(
        storage: storage,
        defaultKdfParams: KdfParams.testFast,
      );
      container = ProviderContainer(
        overrides: [
          vaultStorageProvider.overrideWithValue(storage),
          vaultRepositoryProvider.overrideWithValue(repository),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    Widget buildTestApp() {
      return UncontrolledProviderScope(
        container: container,
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

    Future<void> navigateToGroups(WidgetTester tester) async {
      final manageFinder = find.widgetWithText(ActionChip, 'Manage');
      if (manageFinder.evaluate().isNotEmpty) {
        await tester.tap(manageFinder);
      } else {
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Groups'));
      }
      await tester.pumpAndSettle();
    }

    testWidgets(
      '1. GroupsScreen: empty state -> add groups -> validates non-empty and case-insensitive duplicate',
      (tester) async {
        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        // Navigate to /groups
        await navigateToGroups(tester);
        expect(find.text('Groups'), findsOneWidget);
        expect(find.text('No groups yet'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Add Group'), findsOneWidget);

        // Tap Add Group button
        await tester.tap(find.widgetWithText(FilledButton, 'Add Group'));
        await tester.pumpAndSettle();

        expect(find.text('Add Group'), findsWidgets);
        final dialogAddButton = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Add'),
        );
        final dialogTextField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        );

        // 1. Try empty submission
        await tester.tap(dialogAddButton);
        await tester.pumpAndSettle();
        expect(find.text('Group name cannot be empty'), findsOneWidget);

        // 2. Try whitespace-only submission
        await tester.enterText(dialogTextField, '    ');
        await tester.tap(dialogAddButton);
        await tester.pumpAndSettle();
        expect(find.text('Group name cannot be empty'), findsOneWidget);

        // 3. Add valid group "Work"
        await tester.enterText(dialogTextField, 'Work');
        await tester.tap(dialogAddButton);
        await tester.pumpAndSettle();

        // Verify "Work" group tile appears with "0 accounts"
        expect(find.text('Work'), findsOneWidget);
        expect(find.text('0 accounts'), findsOneWidget);

        // 4. Try adding duplicate group with different casing "work" via FAB
        await tester.tap(find.byTooltip('Add group').first);
        await tester.pumpAndSettle();

        final dialogTextField2 = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        );
        final dialogAddButton2 = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Add'),
        );

        await tester.enterText(dialogTextField2, '  work  ');
        await tester.tap(dialogAddButton2);
        await tester.pumpAndSettle();
        expect(
          find.text('A group with this name already exists'),
          findsOneWidget,
        );

        // Cancel dialog
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(TextButton, 'Cancel'),
          ),
        );
        await tester.pumpAndSettle();

        // 5. Add second valid group "Personal" via AppBar action
        await tester.tap(find.byTooltip('Add group').first);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextFormField),
          ),
          'Personal',
        );
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Add'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Work'), findsOneWidget);
        expect(find.text('Personal'), findsOneWidget);

        // Verify vault state in container
        final state = container.read(vaultControllerProvider);
        expect(state, isA<VaultUnlocked>());
        final groups = (state as VaultUnlocked).data.groups;
        expect(groups.length, equals(2));
        expect(groups.map((g) => g.name), containsAll(['Work', 'Personal']));
      },
    );

    testWidgets(
      '2. Rename group: validates empty & duplicate names, updates vault and UI',
      (tester) async {
        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        // Add 2 groups via controller
        final controller = container.read(vaultControllerProvider.notifier);
        await controller.addGroup('Work');
        await controller.addGroup('Personal');
        await tester.pumpAndSettle();

        await navigateToGroups(tester);
        expect(find.text('Work'), findsOneWidget);
        expect(find.text('Personal'), findsOneWidget);

        // Tap edit button on the first group tile
        final editButtons = find.byTooltip('Rename group');
        expect(editButtons, findsNWidgets(2));
        await tester.tap(editButtons.first);
        await tester.pumpAndSettle();

        expect(find.text('Rename Group'), findsOneWidget);
        final renameField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        );
        final saveButton = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Save'),
        );

        // 1. Try empty name
        await tester.enterText(renameField, '   ');
        await tester.tap(saveButton);
        await tester.pumpAndSettle();
        expect(find.text('Group name cannot be empty'), findsOneWidget);

        // 2. Try duplicate colliding with other group (Personal)
        await tester.enterText(renameField, 'personal');
        await tester.tap(saveButton);
        await tester.pumpAndSettle();
        expect(
          find.text('A group with this name already exists'),
          findsOneWidget,
        );

        // 3. Rename to "Company"
        await tester.enterText(renameField, 'Company');
        await tester.tap(saveButton);
        await tester.pumpAndSettle();

        expect(find.text('Company'), findsOneWidget);
        expect(find.text('Work'), findsNothing);

        // Verify updated in vault repository/state
        final state = container.read(vaultControllerProvider) as VaultUnlocked;
        expect(state.data.groups.any((g) => g.name == 'Company'), isTrue);
        expect(state.data.groups.any((g) => g.name == 'Work'), isFalse);
      },
    );

    testWidgets(
      '3. Reorder groups: updates sortOrder in vault and reflects in UI',
      (tester) async {
        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        final controller = container.read(vaultControllerProvider.notifier);
        await controller.addGroup('Alpha');
        await controller.addGroup('Beta');
        await controller.addGroup('Gamma');
        await tester.pumpAndSettle();

        await navigateToGroups(tester);
        expect(find.byType(ReorderableListView), findsOneWidget);
        expect(find.byType(ReorderableDragStartListener), findsNWidgets(3));

        // Initial sort order check
        var state = container.read(vaultControllerProvider) as VaultUnlocked;
        var sortedGroups = List<Group>.from(state.data.groups)
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        expect(sortedGroups.map((g) => g.name).toList(), [
          'Alpha',
          'Beta',
          'Gamma',
        ]);

        // Reorder via controller (Alpha index 0 moved down to index 2 in ReorderableListView)
        await controller.reorderGroups(0, 2);
        await tester.pumpAndSettle();

        state = container.read(vaultControllerProvider) as VaultUnlocked;
        sortedGroups = List<Group>.from(state.data.groups)
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        expect(sortedGroups.map((g) => g.name).toList(), [
          'Beta',
          'Alpha',
          'Gamma',
        ]);
        expect(sortedGroups[0].sortOrder, equals(0));
        expect(sortedGroups[1].sortOrder, equals(1));
        expect(sortedGroups[2].sortOrder, equals(2));
      },
    );

    testWidgets(
      '4. Delete group: shows confirmation dialog, removes group ID from accounts without deleting accounts, and resets selectedGroupIdProvider',
      (tester) async {
        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        final controller = container.read(vaultControllerProvider.notifier);
        final workGroup = await controller.addGroup('Work');
        final personalGroup = await controller.addGroup('Personal');

        // Add 2 entries: one tagged with Work, one tagged with Personal
        await controller.addEntry(
          OtpEntry(
            id: 'e-work',
            issuer: 'GitHub',
            account: 'work@example.com',
            secret: 'JBSWY3DPEHPK3PXP',
            type: OtpType.totp,
            groupIds: [workGroup.id],
          ),
        );
        await controller.addEntry(
          OtpEntry(
            id: 'e-personal',
            issuer: 'Google',
            account: 'me@example.com',
            secret: 'JBSWY3DPEHPK3PXP',
            type: OtpType.totp,
            groupIds: [personalGroup.id],
          ),
        );

        // Select Work group as active filter
        container
            .read(selectedGroupIdProvider.notifier)
            .selectGroup(workGroup.id);
        await tester.pumpAndSettle();
        expect(container.read(selectedGroupIdProvider), equals(workGroup.id));

        // Navigate to GroupsScreen
        await navigateToGroups(tester);
        // Work group should show subtitle "1 account"
        expect(find.text('1 account'), findsNWidgets(2));

        // Tap delete on Work group
        final deleteButtons = find.byTooltip('Delete group');
        await tester.tap(deleteButtons.first);
        await tester.pumpAndSettle();

        // Confirmation dialog appears
        expect(find.text('Delete "${workGroup.name}"?'), findsOneWidget);
        expect(
          find.text(
            'Deleting this group will remove it from all accounts tagged with it. The accounts themselves will not be deleted.',
          ),
          findsOneWidget,
        );

        // Cancel first
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(container.read(selectedGroupIdProvider), equals(workGroup.id));

        // Tap delete again and confirm
        await tester.tap(deleteButtons.first);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Delete group'));
        await tester.pumpAndSettle();

        // Group deleted from UI
        expect(find.text('Work'), findsNothing);
        expect(find.text('Personal'), findsOneWidget);

        // Selected group reset to null
        expect(container.read(selectedGroupIdProvider), isNull);

        // Verify vault payload: Work group removed, entries still exist
        final state = container.read(vaultControllerProvider) as VaultUnlocked;
        expect(state.data.groups.length, equals(1));
        expect(state.data.groups.first.id, equals(personalGroup.id));

        expect(state.data.entries.length, equals(2));
        final workEntry = state.data.entries.firstWhere(
          (e) => e.id == 'e-work',
        );
        expect(workEntry.groupIds, isEmpty);
        final personalEntry = state.data.entries.firstWhere(
          (e) => e.id == 'e-personal',
        );
        expect(personalEntry.groupIds, equals([personalGroup.id]));
      },
    );

    testWidgets(
      '5. ManualEntryScreen: groups multi-select visible on main form and inline group creation works',
      (tester) async {
        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        final controller = container.read(vaultControllerProvider.notifier);
        await controller.addGroup('Work');
        await controller.addGroup('Finance');
        await tester.pumpAndSettle();

        // Navigate to Add Manual
        await tester.tap(find.byTooltip('Add account'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Enter Manually'));
        await tester.pumpAndSettle();

        // Verify Groups section is visible without expanding Advanced options
        expect(find.text('Groups'), findsOneWidget);
        expect(find.widgetWithText(FilterChip, 'Work'), findsOneWidget);
        expect(find.widgetWithText(FilterChip, 'Finance'), findsOneWidget);

        // Select Work filter chip
        await tester.tap(find.widgetWithText(FilterChip, 'Work'));
        await tester.pumpAndSettle();

        // Create a new group inline via ActionChip "New group"
        final newGroupChips = find.widgetWithText(ActionChip, 'New group');
        await tester.tap(newGroupChips.first);
        await tester.pumpAndSettle();

        expect(find.text('Add Group'), findsOneWidget);
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextFormField),
          ),
          'Social',
        );
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Add'),
          ),
        );
        await tester.pumpAndSettle();

        // The new group chip "Social" should be visible and automatically selected
        expect(find.widgetWithText(FilterChip, 'Social'), findsOneWidget);

        // Fill required fields to save entry
        final textFields = find.byType(TextFormField);
        await tester.enterText(textFields.at(1), 'Twitter');
        await tester.enterText(textFields.at(2), 'alice');
        await tester.enterText(textFields.at(3), 'JBSWY3DPEHPK3PXP');
        await tester.pumpAndSettle();

        // Tap Add Account
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Add Account'),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add Account'));
        await tester.pumpAndSettle();

        // Lands back on home screen
        expect(find.text('Twitter'), findsOneWidget);

        // Verify the saved entry has both Work and Social group IDs
        final state = container.read(vaultControllerProvider) as VaultUnlocked;
        final entry = state.data.entries.firstWhere(
          (e) => e.issuer == 'Twitter',
        );
        final workId = state.data.groups.firstWhere((g) => g.name == 'Work').id;
        final socialId = state.data.groups
            .firstWhere((g) => g.name == 'Social')
            .id;
        expect(entry.groupIds, containsAll([workId, socialId]));
      },
    );

    testWidgets(
      '6. EntriesListScreen: group filter chips filter entries, hide reorder drag handles, and "All" restores them',
      (tester) async {
        await repository.createVault('password123');
        await setupViewportAndUnlock(tester);

        final controller = container.read(vaultControllerProvider.notifier);
        final workGroup = await controller.addGroup('Work');
        final personalGroup = await controller.addGroup('Personal');

        await controller.addEntry(
          OtpEntry(
            id: 'e1',
            issuer: 'GitHub Work',
            account: 'work@corp.com',
            secret: 'JBSWY3DPEHPK3PXP',
            type: OtpType.totp,
            groupIds: [workGroup.id],
            sortOrder: 0,
          ),
        );
        await controller.addEntry(
          OtpEntry(
            id: 'e2',
            issuer: 'Google Personal',
            account: 'me@gmail.com',
            secret: 'JBSWY3DPEHPK3PXP',
            type: OtpType.totp,
            groupIds: [personalGroup.id],
            sortOrder: 1,
          ),
        );
        await tester.pumpAndSettle();

        // Both accounts visible on Home
        expect(find.text('GitHub Work'), findsOneWidget);
        expect(find.text('Google Personal'), findsOneWidget);

        // Filter chips row has "All", "Work", "Personal", and "Manage"
        expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Work'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Personal'), findsOneWidget);
        expect(find.widgetWithText(ActionChip, 'Manage'), findsOneWidget);

        // Drag handles visible when "All" is active
        expect(find.byType(ReorderableDragStartListener), findsNWidgets(2));

        // Tap "Work" filter chip
        await tester.tap(find.widgetWithText(ChoiceChip, 'Work'));
        await tester.pumpAndSettle();

        // Only "GitHub Work" should be visible
        expect(find.text('GitHub Work'), findsOneWidget);
        expect(find.text('Google Personal'), findsNothing);

        // Drag handles must be hidden when filtered to a specific group
        expect(find.byType(ReorderableDragStartListener), findsNothing);

        // Tap "All" filter chip
        await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
        await tester.pumpAndSettle();

        // Both entries visible again
        expect(find.text('GitHub Work'), findsOneWidget);
        expect(find.text('Google Personal'), findsOneWidget);

        // Drag handles restored
        expect(find.byType(ReorderableDragStartListener), findsNWidgets(2));

        // Tap "Manage" action chip -> navigates to /groups
        await tester.tap(find.widgetWithText(ActionChip, 'Manage'));
        await tester.pumpAndSettle();

        expect(find.text('Groups'), findsOneWidget);
        expect(find.text('Work'), findsOneWidget);
        expect(find.text('Personal'), findsOneWidget);
      },
    );
  });
}
