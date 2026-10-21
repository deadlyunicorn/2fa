import 'dart:math';

import 'package:uuid/uuid.dart';

import '../models/group.dart';
import '../models/otp_entry.dart';
import '../models/otp_type.dart';
import '../otp/base32.dart';
import 'vault_payload.dart';

/// Report summarizing the result of merging an imported vault (§6.4).
class MergeReport {
  const MergeReport({
    this.added = 0,
    this.skippedDuplicates = 0,
    this.updated = 0,
    this.invalid = 0,
    this.groupsCreated = 0,
  });

  /// Count of newly imported non-duplicate entries added.
  final int added;

  /// Count of identical duplicate entries skipped.
  final int skippedDuplicates;

  /// Count of HOTP entries updated with a higher/different counter.
  final int updated;

  /// Count of skipped malformed or invalid entries from the imported vault.
  final int invalid;

  /// Count of new groups created during merge.
  final int groupsCreated;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MergeReport &&
          runtimeType == other.runtimeType &&
          added == other.added &&
          skippedDuplicates == other.skippedDuplicates &&
          updated == other.updated &&
          invalid == other.invalid &&
          groupsCreated == other.groupsCreated;

  @override
  int get hashCode =>
      Object.hash(added, skippedDuplicates, updated, invalid, groupsCreated);

  @override
  String toString() =>
      'MergeReport(added: $added, skippedDuplicates: $skippedDuplicates, updated: $updated, invalid: $invalid, groupsCreated: $groupsCreated)';
}

/// Computes the normalized deduplication key for an entry (§6.4 item 2).
String _entryDedupeKey(String secret, String issuer, String account) {
  String normalizedSecret;
  try {
    normalizedSecret = Base32Codec.normalize(secret);
  } catch (_) {
    normalizedSecret = secret.trim().toUpperCase();
  }
  return '$normalizedSecret|${issuer.trim().toLowerCase()}|${account.trim().toLowerCase()}';
}

/// Pure merge algorithm for importing another vault into the current vault (§6.4).
({VaultPayload merged, MergeReport report}) mergeVaults({
  required VaultPayload local,
  required VaultPayload imported,
  Uuid? uuid,
  DateTime? now,
}) {
  final effectiveUuid = uuid ?? const Uuid();
  final effectiveNow = now ?? DateTime.now().toUtc();

  // ---------------------------------------------------------------------------
  // 1. Groups (§6.4 item 1)
  // Match by name, case-insensitive and trimmed. Reuse existing local group id
  // or create a new group with a new uuid v4.
  // ---------------------------------------------------------------------------
  final mergedGroups = List<Group>.from(local.groups);
  final localGroupByName = <String, Group>{};
  for (final g in local.groups) {
    localGroupByName[g.name.trim().toLowerCase()] = g;
  }

  int nextGroupSortOrder = local.groups.isEmpty
      ? 0
      : local.groups.map((g) => g.sortOrder).reduce(max) + 1;

  final importedGroupIdToLocalGroupId = <String, String>{};
  int groupsCreated = 0;

  for (final importedGroup in imported.groups) {
    final key = importedGroup.name.trim().toLowerCase();
    final existingLocal = localGroupByName[key];
    if (existingLocal != null) {
      importedGroupIdToLocalGroupId[importedGroup.id] = existingLocal.id;
    } else {
      final newGroupId = effectiveUuid.v4();
      final newGroup = Group(
        id: newGroupId,
        name: importedGroup.name,
        sortOrder: nextGroupSortOrder++,
      );
      mergedGroups.add(newGroup);
      localGroupByName[key] = newGroup;
      importedGroupIdToLocalGroupId[importedGroup.id] = newGroupId;
      groupsCreated++;
    }
  }

  // ---------------------------------------------------------------------------
  // 2. Entries (§6.4 items 2-4)
  // Deduplicate by normalizedSecret + trimmed lowercase issuer + trimmed lowercase account.
  // ---------------------------------------------------------------------------
  final mergedEntries = List<OtpEntry>.from(local.entries);
  final entryKeyToIndex = <String, int>{};

  for (var i = 0; i < local.entries.length; i++) {
    final e = local.entries[i];
    final key = _entryDedupeKey(e.secret, e.issuer, e.account);
    entryKeyToIndex[key] = i;
  }

  int nextEntrySortOrder = local.entries.isEmpty
      ? 0
      : local.entries.map((e) => e.sortOrder).reduce(max) + 1;

  int added = 0;
  int skippedDuplicates = 0;
  int updated = 0;

  // Sort imported entries by their original sortOrder to preserve relative order (§6.4 item 3)
  final sortedImportedEntries = List<OtpEntry>.from(imported.entries)
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  for (final importedEntry in sortedImportedEntries) {
    final key = _entryDedupeKey(
      importedEntry.secret,
      importedEntry.issuer,
      importedEntry.account,
    );

    if (entryKeyToIndex.containsKey(key)) {
      final existingIndex = entryKeyToIndex[key]!;
      final existingEntry = mergedEntries[existingIndex];

      if (existingEntry.type == OtpType.hotp &&
          importedEntry.type == OtpType.hotp) {
        if (importedEntry.counter != existingEntry.counter) {
          // HOTP duplicate with a different counter: keep local entry, set counter = max(local, imported).
          final newCounter = max(existingEntry.counter, importedEntry.counter);
          mergedEntries[existingIndex] = existingEntry.copyWith(
            counter: newCounter,
            updatedAt: effectiveNow,
          );
          updated++;
        } else {
          skippedDuplicates++;
        }
      } else {
        // TOTP duplicate or non-matching OTP types: skip
        skippedDuplicates++;
      }
    } else {
      // Non-duplicate: assign new uuid v4, remap groupIds, assign appended sortOrder
      final newId = effectiveUuid.v4();
      final remappedGroupIds = <String>[];
      for (final gid in importedEntry.groupIds) {
        final remapped = importedGroupIdToLocalGroupId[gid];
        if (remapped != null && !remappedGroupIds.contains(remapped)) {
          remappedGroupIds.add(remapped);
        }
      }

      final newEntry = importedEntry.copyWith(
        id: newId,
        groupIds: remappedGroupIds,
        sortOrder: nextEntrySortOrder++,
      );

      mergedEntries.add(newEntry);
      entryKeyToIndex[key] = mergedEntries.length - 1;
      added++;
    }
  }

  final report = MergeReport(
    added: added,
    skippedDuplicates: skippedDuplicates,
    updated: updated,
    invalid: imported.invalidEntriesSkipped,
    groupsCreated: groupsCreated,
  );

  final bool hasChanges = added > 0 || updated > 0 || groupsCreated > 0;
  final mergedPayload = local.copyWith(
    modifiedAt: hasChanges ? effectiveNow : local.modifiedAt,
    groups: mergedGroups,
    entries: mergedEntries,
    invalidEntriesSkipped: 0,
  );

  return (merged: mergedPayload, report: report);
}

/// Pure merge algorithm namespace wrapper for importing another vault.
class VaultMerge {
  const VaultMerge._();

  /// Merges [imported] into [local] (or [current]) per §6.4.
  static ({VaultPayload merged, MergeReport report}) merge({
    VaultPayload? local,
    VaultPayload? current,
    required VaultPayload imported,
    Uuid? uuid,
    DateTime? now,
  }) {
    final effectiveLocal = local ?? current;
    if (effectiveLocal == null) {
      throw ArgumentError('Either local or current must be provided');
    }
    return mergeVaults(
      local: effectiveLocal,
      imported: imported,
      uuid: uuid,
      now: now,
    );
  }
}
