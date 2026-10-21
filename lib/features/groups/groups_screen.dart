import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/group.dart';
import '../../data/vault_controller.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/responsive_wrapper.dart';

/// Opens a modal dialog for adding a new group with trimmed, case-insensitive duplicate validation (§7.1 #10).
Future<Group?> showAddGroupDialog(BuildContext context, WidgetRef ref) async {
  final vaultState = ref.read(vaultControllerProvider);
  final existingGroups = vaultState is VaultUnlocked
      ? vaultState.data.groups
      : const <Group>[];

  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();

  return showDialog<Group>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Add Group'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Group name',
              hintText: 'e.g. Work, Personal',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty) {
                return 'Group name cannot be empty';
              }
              final duplicate = existingGroups.any(
                (g) => g.name.trim().toLowerCase() == trimmed.toLowerCase(),
              );
              if (duplicate) {
                return 'A group with this name already exists';
              }
              return null;
            },
            onFieldSubmitted: (_) async {
              if (formKey.currentState!.validate()) {
                final newGroup = await ref
                    .read(vaultControllerProvider.notifier)
                    .addGroup(controller.text.trim());
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(newGroup);
                }
              }
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final newGroup = await ref
                    .read(vaultControllerProvider.notifier)
                    .addGroup(controller.text.trim());
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(newGroup);
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      );
    },
  );
}

/// Opens a modal dialog for renaming an existing group with duplicate validation (§7.1 #10).
Future<void> showRenameGroupDialog(
  BuildContext context,
  WidgetRef ref,
  Group group,
) async {
  final vaultState = ref.read(vaultControllerProvider);
  final existingGroups = vaultState is VaultUnlocked
      ? vaultState.data.groups
      : const <Group>[];

  final controller = TextEditingController(text: group.name);
  final formKey = GlobalKey<FormState>();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Rename Group'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Group name',
              hintText: 'e.g. Work, Personal',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty) {
                return 'Group name cannot be empty';
              }
              final duplicate = existingGroups.any(
                (g) =>
                    g.id != group.id &&
                    g.name.trim().toLowerCase() == trimmed.toLowerCase(),
              );
              if (duplicate) {
                return 'A group with this name already exists';
              }
              return null;
            },
            onFieldSubmitted: (_) async {
              if (formKey.currentState!.validate()) {
                final newName = controller.text.trim();
                if (newName != group.name) {
                  await ref
                      .read(vaultControllerProvider.notifier)
                      .renameGroup(group.id, newName);
                }
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              }
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final newName = controller.text.trim();
                if (newName != group.name) {
                  await ref
                      .read(vaultControllerProvider.notifier)
                      .renameGroup(group.id, newName);
                }
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}

/// Prompts confirmation to delete [group] and strips it from tagged entries (§7.1 #10).
Future<void> confirmDeleteGroup(
  BuildContext context,
  WidgetRef ref,
  Group group,
) async {
  final confirmed = await ConfirmDialog.show(
    context,
    title: 'Delete "${group.name}"?',
    message: 'Deleting this group will remove it from all accounts tagged with it. The accounts themselves will not be deleted.',
    confirmLabel: 'Delete group',
    isDestructive: true,
  );

  if (confirmed) {
    if (ref.read(selectedGroupIdProvider) == group.id) {
      ref.read(selectedGroupIdProvider.notifier).selectGroup(null);
    }
    await ref.read(vaultControllerProvider.notifier).deleteGroup(group.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Group "${group.name}" deleted'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

/// Screen for managing, renaming, deleting, and reordering entry groups (§7.1 #10, §9 M7).
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final vaultState = ref.watch(vaultControllerProvider);

    if (vaultState is! VaultUnlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Groups')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final data = vaultState.data;
    final groups = List<Group>.from(data.groups)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add group',
            onPressed: () => showAddGroupDialog(context, ref),
          ),
        ],
      ),
      body: ResponsiveContentWrapper(
        child: groups.isEmpty
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.folder_open_outlined,
                        size: 72,
                        color: theme.colorScheme.primary.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No groups yet',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create groups like Work or Personal to organize your accounts.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => showAddGroupDialog(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Group'),
                      ),
                    ],
                  ),
                ),
              )
            : ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                itemCount: groups.length,
                onReorderItem: (oldIndex, newIndex) {
                  ref
                      .read(vaultControllerProvider.notifier)
                      .reorderGroups(
                        oldIndex,
                        oldIndex < newIndex ? newIndex + 1 : newIndex,
                      );
                },
                itemBuilder: (context, index) {
                  final group = groups[index];
                  final count = data.entries
                      .where((e) => e.groupIds.contains(group.id))
                      .length;
                  final countText = count == 1
                      ? '1 account'
                      : '$count accounts';

                  return Card(
                    key: ValueKey(group.id),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 4.0,
                    ),
                    elevation: 0.5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    child: ListTile(
                      onTap: () => showRenameGroupDialog(context, ref, group),
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                        child: const Icon(Icons.folder_outlined),
                      ),
                      title: Text(
                        group.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(countText),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Rename group',
                            onPressed: () =>
                                showRenameGroupDialog(context, ref, group),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              color: theme.colorScheme.error,
                            ),
                            tooltip: 'Delete group',
                            onPressed: () =>
                                confirmDeleteGroup(context, ref, group),
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 4.0,
                                right: 8.0,
                              ),
                              child: Icon(
                                Icons.drag_handle,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add group',
        onPressed: () => showAddGroupDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}
