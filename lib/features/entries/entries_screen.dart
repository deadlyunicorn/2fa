import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/group.dart';
import '../../data/vault_controller.dart';
import '../../shared/widgets/responsive_wrapper.dart';
import 'entry_tile.dart';

export 'entry_details_screen.dart';
export 'entry_tile.dart';

/// Home screen displaying OTP entries with search, group filtering, and reordering (§7.1 #3).
class EntriesListScreen extends ConsumerStatefulWidget {
  const EntriesListScreen({super.key});

  @override
  ConsumerState<EntriesListScreen> createState() => _EntriesListScreenState();
}

class _EntriesListScreenState extends ConsumerState<EntriesListScreen> {
  bool _isSearching = false;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() {
      _isSearching = true;
    });
  }

  void _closeSearch() {
    _searchController.clear();
    ref.read(searchQueryProvider.notifier).clear();
    setState(() {
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vaultState = ref.watch(vaultControllerProvider);
    final filteredEntries = ref.watch(filteredEntriesProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final selectedGroupId = ref.watch(selectedGroupIdProvider);

    final totalEntriesCount = vaultState is VaultUnlocked
        ? vaultState.data.entries.length
        : 0;
    final groups = vaultState is VaultUnlocked
        ? (List<Group>.from(vaultState.data.groups)
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
        : const <Group>[];

    final effectiveSelectedGroupId =
        (selectedGroupId != null && groups.any((g) => g.id == selectedGroupId))
        ? selectedGroupId
        : null;

    final canReorder = searchQuery.isEmpty && effectiveSelectedGroupId == null;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search accounts...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                style: TextStyle(color: theme.colorScheme.onSurface),
                onChanged: (value) {
                  ref.read(searchQueryProvider.notifier).setQuery(value);
                },
              )
            : const Text('Offline 2FA'),
        actions: <Widget>[
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close search',
              onPressed: _closeSearch,
            )
          else ...<Widget>[
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search',
              onPressed: _openSearch,
            ),
            IconButton(
              icon: const Icon(Icons.lock_outline),
              tooltip: 'Lock vault',
              onPressed: () {
                ref.read(vaultControllerProvider.notifier).lock();
              },
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (value) {
                switch (value) {
                  case 'groups':
                    context.push('/groups');
                  case 'backup':
                    context.push('/backup');
                  case 'settings':
                    context.push('/settings');
                }
              },
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                const PopupMenuItem(
                  value: 'groups',
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.folder_outlined),
                      SizedBox(width: 12),
                      Text('Groups'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'backup',
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.backup_outlined),
                      SizedBox(width: 12),
                      Text('Backup'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.settings_outlined),
                      SizedBox(width: 12),
                      Text('Settings'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: ResponsiveContentWrapper(
        child: totalEntriesCount == 0
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.shield_outlined,
                        size: 72,
                        color: theme.colorScheme.primary.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No accounts yet',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add your first 2FA account to start generating offline codes.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => context.push('/add'),
                        icon: const Icon(Icons.add),
                        label: const Text('Add your first account'),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: <Widget>[
                  if (groups.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ChoiceChip(
                              label: const Text('All'),
                              selected: effectiveSelectedGroupId == null,
                              onSelected: (_) {
                                ref
                                    .read(selectedGroupIdProvider.notifier)
                                    .selectGroup(null);
                              },
                            ),
                          ),
                          for (final group in groups)
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ChoiceChip(
                                label: Text(group.name),
                                selected: effectiveSelectedGroupId == group.id,
                                onSelected: (selected) {
                                  ref
                                      .read(selectedGroupIdProvider.notifier)
                                      .selectGroup(selected ? group.id : null);
                                },
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ActionChip(
                              avatar: const Icon(
                                Icons.settings_outlined,
                                size: 16,
                              ),
                              label: const Text('Manage'),
                              tooltip: 'Manage groups',
                              onPressed: () => context.push('/groups'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Expanded(
                    child: filteredEntries.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Icon(
                                    Icons.search_off,
                                    size: 64,
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No matching accounts',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Try adjusting your search query or group filter.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : canReorder
                        ? ReorderableListView.builder(
                            buildDefaultDragHandles: false,
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            itemCount: filteredEntries.length,
                            onReorderItem: (oldIndex, newIndex) {
                              ref
                                  .read(vaultControllerProvider.notifier)
                                  .reorderEntries(
                                    oldIndex,
                                    oldIndex < newIndex
                                        ? newIndex + 1
                                        : newIndex,
                                  );
                            },
                            itemBuilder: (context, index) {
                              final entry = filteredEntries[index];
                              return EntryTile(
                                key: ValueKey(entry.id),
                                entry: entry,
                                index: index,
                                canReorder: true,
                              );
                            },
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            itemCount: filteredEntries.length,
                            itemBuilder: (context, index) {
                              final entry = filteredEntries[index];
                              return EntryTile(
                                key: ValueKey(entry.id),
                                entry: entry,
                                index: index,
                                canReorder: false,
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add account',
        onPressed: () => context.push('/add'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Backward-compatible alias for [EntriesListScreen].
typedef EntriesScreen = EntriesListScreen;
