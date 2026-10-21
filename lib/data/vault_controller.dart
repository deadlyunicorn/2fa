import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/models/group.dart';
import '../core/models/otp_entry.dart';
import '../core/models/otp_type.dart';
import '../core/vault/vault_errors.dart';
import '../core/vault/vault_merge.dart';
import '../core/vault/vault_payload.dart';
import 'vault_repository.dart';

/// Represents the top-level lock and authentication state of the vault (§4.1).
@immutable
sealed class VaultState {
  const VaultState();
}

/// Initial uninitialized state before storage check.
class VaultInitial extends VaultState {
  const VaultInitial();

  @override
  bool operator ==(Object other) => other is VaultInitial;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'VaultInitial()';
}

/// State when no vault file exists on device (§4.1, §4.2).
class VaultNoVault extends VaultState {
  const VaultNoVault({this.hasBackup = false});

  final bool hasBackup;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultNoVault &&
          runtimeType == other.runtimeType &&
          hasBackup == other.hasBackup;

  @override
  int get hashCode => Object.hash(runtimeType, hasBackup);

  @override
  String toString() => 'VaultNoVault(hasBackup: $hasBackup)';
}

/// State when a vault file exists on device and is currently locked (§4.1).
class VaultLocked extends VaultState {
  const VaultLocked({
    this.errorMessage,
    this.failedAttempts = 0,
    this.lockoutUntil,
    this.hasBackup = false,
  });

  final String? errorMessage;
  final int failedAttempts;
  final DateTime? lockoutUntil;
  final bool hasBackup;

  bool get isLockedOut =>
      lockoutUntil != null && DateTime.now().isBefore(lockoutUntil!);

  int get remainingLockoutSeconds {
    if (lockoutUntil == null) return 0;
    final diff = lockoutUntil!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  VaultLocked copyWith({
    String? errorMessage,
    int? failedAttempts,
    DateTime? lockoutUntil,
    bool? hasBackup,
  }) {
    return VaultLocked(
      errorMessage: errorMessage ?? this.errorMessage,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockoutUntil: lockoutUntil ?? this.lockoutUntil,
      hasBackup: hasBackup ?? this.hasBackup,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultLocked &&
          runtimeType == other.runtimeType &&
          errorMessage == other.errorMessage &&
          failedAttempts == other.failedAttempts &&
          lockoutUntil == other.lockoutUntil &&
          hasBackup == other.hasBackup;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    errorMessage,
    failedAttempts,
    lockoutUntil,
    hasBackup,
  );

  @override
  String toString() =>
      'VaultLocked(errorMessage: $errorMessage, failedAttempts: $failedAttempts, lockoutUntil: $lockoutUntil, hasBackup: $hasBackup)';
}

/// Transient state while key derivation and decryption run in the background.
class VaultUnlocking extends VaultState {
  const VaultUnlocking({this.fromOnboarding = false});

  final bool fromOnboarding;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultUnlocking &&
          runtimeType == other.runtimeType &&
          fromOnboarding == other.fromOnboarding;

  @override
  int get hashCode => Object.hash(runtimeType, fromOnboarding);

  @override
  String toString() => 'VaultUnlocking(fromOnboarding: $fromOnboarding)';
}

/// Unlocked state holding the decrypted [VaultPayload] in memory (§4.1).
class VaultUnlocked extends VaultState {
  const VaultUnlocked(this.data);

  final VaultPayload data;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultUnlocked &&
          runtimeType == other.runtimeType &&
          data == other.data;

  @override
  int get hashCode => Object.hash(runtimeType, data);

  @override
  String toString() => 'VaultUnlocked(entries: ${data.entries.length})';
}

/// Error state when an unrecoverable vault failure occurs.
class VaultError extends VaultState {
  const VaultError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultError &&
          runtimeType == other.runtimeType &&
          message == other.message;

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @override
  String toString() => 'VaultError(message: $message)';
}

/// Helper calculating increasing unlock throttle delay after 5 consecutive failures (§5.7).
int calculateThrottleDelaySeconds(int consecutiveFailures) {
  if (consecutiveFailures < 5) return 0;
  final exponent = consecutiveFailures - 5;
  if (exponent >= 5) return 30; // 1, 2, 4, 8, 16, 30 max
  return 1 << exponent;
}

/// Async mutex serializing mutations to ensure writes never interleave on disk (§4.1).
class _AsyncMutex {
  Future<void>? _last;

  Future<T> run<T>(Future<T> Function() block) async {
    final prev = _last;
    final completer = Completer<void>();
    _last = completer.future;

    if (prev != null) {
      try {
        await prev;
      } catch (_) {}
    }

    try {
      return await block();
    } finally {
      completer.complete();
    }
  }
}

/// Controller managing overall vault authentication and serialized payload mutations (§4.1).
class VaultController extends Notifier<VaultState> {
  final _AsyncMutex _mutex = _AsyncMutex();
  int _sessionGeneration = 0;

  VaultRepository get _repository => ref.read(vaultRepositoryProvider);

  @override
  VaultState build() {
    return const VaultInitial();
  }

  /// Initializes the vault state by probing persistent storage (§4.1).
  Future<void> initialize() async {
    final hasVault = await _repository.hasVault();
    final hasBackup = await _repository.hasBackup();

    if (!hasVault) {
      state = VaultNoVault(hasBackup: hasBackup);
    } else {
      state = VaultLocked(hasBackup: hasBackup);
    }
  }

  /// Creates a new empty vault initialized with [password] (§5.2, §7.1 #1).
  Future<void> create(String password) async {
    final isFromOnboarding = state is VaultNoVault;
    state = VaultUnlocking(fromOnboarding: isFromOnboarding);
    try {
      final payload = await _repository.createVault(password);
      state = VaultUnlocked(payload);
    } catch (e) {
      final hasVault = await _repository.hasVault();
      final hasBackup = await _repository.hasBackup();
      if (!hasVault) {
        state = VaultNoVault(hasBackup: hasBackup);
      } else {
        state = VaultError(e.toString());
      }
      rethrow;
    }
  }

  /// Imports an external vault file during onboarding (§7.1 #1).
  Future<void> importInitialVault(Uint8List bytes, String password) async {
    final isFromOnboarding = state is VaultNoVault;
    state = VaultUnlocking(fromOnboarding: isFromOnboarding);
    try {
      final payload = await _repository.importAsNewVault(bytes, password);
      state = VaultUnlocked(payload);
    } catch (e) {
      final hasVault = await _repository.hasVault();
      final hasBackup = await _repository.hasBackup();
      if (!hasVault) {
        state = VaultNoVault(hasBackup: hasBackup);
      } else {
        state = VaultLocked(
          errorMessage: e is VaultException
              ? e.userFacingMessage
              : e.toString(),
          hasBackup: hasBackup,
        );
      }
      rethrow;
    }
  }

  /// Unlocks the vault with [password], applying throttle protections on failure (§5.7).
  Future<void> unlock(String password) async {
    final currentState = state;
    final previousAttempts = currentState is VaultLocked
        ? currentState.failedAttempts
        : 0;
    final previousBackup = currentState is VaultLocked
        ? currentState.hasBackup
        : false;

    if (currentState is VaultLocked && currentState.isLockedOut) {
      final remaining = currentState.remainingLockoutSeconds;
      state = currentState.copyWith(
        errorMessage: 'Too many attempts. Try again in ${remaining}s',
      );
      return;
    }

    state = const VaultUnlocking();
    try {
      final payload = await _repository.unlock(password);
      state = VaultUnlocked(payload);
    } catch (e) {
      final newAttempts = previousAttempts + 1;
      final delay = calculateThrottleDelaySeconds(newAttempts);
      final lockout = delay > 0
          ? DateTime.now().add(Duration(seconds: delay))
          : null;
      final msg = e is VaultException
          ? e.userFacingMessage
          : 'Wrong password or corrupted file';
      state = VaultLocked(
        errorMessage: msg,
        failedAttempts: newAttempts,
        lockoutUntil: lockout,
        hasBackup: previousBackup,
      );
    }
  }

  /// Restores and unlocks the vault from the `.bak` file using [password] (§5.6, §7.1 #2).
  Future<void> restoreBackup(String password) async {
    final isFromOnboarding = state is VaultNoVault;
    state = VaultUnlocking(fromOnboarding: isFromOnboarding);
    try {
      final payload = await _repository.restoreFromBackup(password);
      state = VaultUnlocked(payload);
    } catch (e) {
      final hasVault = await _repository.hasVault();
      final hasBackup = await _repository.hasBackup();
      if (!hasVault) {
        state = VaultNoVault(hasBackup: hasBackup);
      } else {
        final msg = e is VaultException
            ? e.userFacingMessage
            : 'Wrong password or corrupted file';
        state = VaultLocked(errorMessage: msg, hasBackup: hasBackup);
      }
      rethrow;
    }
  }

  /// Locks the vault and zeroes memory credentials (§5.2).
  Future<void> lock() async {
    _sessionGeneration++;
    _repository.lock();
    state = const VaultLocked();
    final hasBackup = await _repository.hasBackup();
    state = VaultLocked(hasBackup: hasBackup);
  }

  /// Resets the app by wiping persistent files and zeroing in-memory keys (§7.1 #2).
  Future<void> resetVault() async {
    _sessionGeneration++;
    await _repository.deleteVault();
    state = const VaultNoVault(hasBackup: false);
  }

  /// Verifies [password] without changing lock state (§7.1 #9).
  Future<bool> verifyPassword(String password) {
    return _repository.verifyPassword(password);
  }

  /// Changes the master password and re-encrypts the vault (§5.2, §7.1 #12).
  Future<void> changePassword(String oldPassword, String newPassword) {
    return _mutex.run(() async {
      final gen = _sessionGeneration;
      final currentState = state;
      if (currentState is! VaultUnlocked ||
          gen != _sessionGeneration ||
          !_repository.isUnlocked) {
        throw StateError('Cannot change password: vault is not unlocked');
      }
      await _repository.changePassword(
        oldPassword,
        newPassword,
        currentState.data,
      );
      if (gen != _sessionGeneration ||
          !_repository.isUnlocked ||
          state is! VaultUnlocked) {
        _repository.lock();
        return;
      }
    });
  }

  /// Internal helper to execute serialized state mutations and write to disk (§4.1).
  Future<T> _mutate<T>(
    Future<({VaultPayload payload, T result})> Function(VaultPayload current)
    action,
  ) {
    return _mutex.run(() async {
      final gen = _sessionGeneration;
      final currentState = state;
      if (currentState is! VaultUnlocked ||
          gen != _sessionGeneration ||
          !_repository.isUnlocked) {
        throw StateError('Cannot mutate vault: vault is not unlocked');
      }
      final outcome = await action(currentState.data);
      if (gen != _sessionGeneration ||
          !_repository.isUnlocked ||
          state is! VaultUnlocked) {
        return outcome.result;
      }
      await _repository.save(outcome.payload);
      if (gen != _sessionGeneration ||
          !_repository.isUnlocked ||
          state is! VaultUnlocked) {
        return outcome.result;
      }
      state = VaultUnlocked(outcome.payload);
      return outcome.result;
    });
  }

  /// Adds a new OTP entry, appending it with appropriate sortOrder (§4.1, §7.1 #5).
  Future<void> addEntry(OtpEntry entry) {
    return _mutate((current) async {
      final maxSortOrder = current.entries.isEmpty
          ? -1
          : current.entries.map((e) => e.sortOrder).reduce(max);
      final effectiveEntry = entry.sortOrder <= 0 && current.entries.isNotEmpty
          ? entry.copyWith(sortOrder: maxSortOrder + 1)
          : entry;

      final updatedEntries = [...current.entries, effectiveEntry];
      final updatedPayload = current.copyWith(
        entries: updatedEntries,
        modifiedAt: DateTime.now().toUtc(),
      );
      return (payload: updatedPayload, result: null);
    });
  }

  /// Updates an existing OTP entry (§4.1, §7.1 #5).
  Future<void> updateEntry(OtpEntry entry) {
    return _mutate((current) async {
      final index = current.entries.indexWhere((e) => e.id == entry.id);
      if (index == -1) {
        throw ArgumentError('Entry with id ${entry.id} not found');
      }
      final updatedEntry = entry.copyWith(updatedAt: DateTime.now().toUtc());
      final updatedEntries = List<OtpEntry>.from(current.entries);
      updatedEntries[index] = updatedEntry;

      final updatedPayload = current.copyWith(
        entries: updatedEntries,
        modifiedAt: DateTime.now().toUtc(),
      );
      return (payload: updatedPayload, result: null);
    });
  }

  /// Deletes an OTP entry by [id] (§4.1, §7.1 #3).
  Future<void> deleteEntry(String id) {
    return _mutate((current) async {
      final updatedEntries = current.entries.where((e) => e.id != id).toList();
      final updatedPayload = current.copyWith(
        entries: updatedEntries,
        modifiedAt: DateTime.now().toUtc(),
      );
      return (payload: updatedPayload, result: null);
    });
  }

  /// Reorders entries following Flutter ReorderableListView conventions (§4.1, §7.1 #3).
  Future<void> reorderEntries(int oldIndex, int newIndex) {
    return _mutate((current) async {
      final entries = List<OtpEntry>.from(current.entries)
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      var targetIndex = newIndex;
      if (oldIndex < targetIndex) {
        targetIndex -= 1;
      }
      final item = entries.removeAt(oldIndex);
      entries.insert(targetIndex, item);

      final reordered = [
        for (var i = 0; i < entries.length; i++)
          entries[i].copyWith(sortOrder: i),
      ];

      final updatedPayload = current.copyWith(
        entries: reordered,
        modifiedAt: DateTime.now().toUtc(),
      );
      return (payload: updatedPayload, result: null);
    });
  }

  /// Increments the counter of an HOTP entry by 1 (§4.1, §7.1 #3).
  Future<void> incrementHotp(String id) {
    return _mutate((current) async {
      final index = current.entries.indexWhere((e) => e.id == id);
      if (index == -1) {
        throw ArgumentError('Entry with id $id not found');
      }
      final entry = current.entries[index];
      if (entry.type != OtpType.hotp) {
        throw ArgumentError('Entry with id $id is not an HOTP entry');
      }
      final updatedEntry = entry.copyWith(
        counter: entry.counter + 1,
        updatedAt: DateTime.now().toUtc(),
      );
      final updatedEntries = List<OtpEntry>.from(current.entries);
      updatedEntries[index] = updatedEntry;

      final updatedPayload = current.copyWith(
        entries: updatedEntries,
        modifiedAt: DateTime.now().toUtc(),
      );
      return (payload: updatedPayload, result: null);
    });
  }

  /// Adds a new organization group (§4.1, §7.1 #10).
  Future<Group> addGroup(String name) {
    return _mutate((current) async {
      final nextSortOrder = current.groups.isEmpty
          ? 0
          : current.groups.map((g) => g.sortOrder).reduce(max) + 1;
      final newGroup = Group(
        id: const Uuid().v4(),
        name: name.trim(),
        sortOrder: nextSortOrder,
      );
      final updatedGroups = [...current.groups, newGroup];
      final updatedPayload = current.copyWith(
        groups: updatedGroups,
        modifiedAt: DateTime.now().toUtc(),
      );
      return (payload: updatedPayload, result: newGroup);
    });
  }

  /// Renames an existing group (§4.1, §7.1 #10).
  Future<void> renameGroup(String id, String newName) {
    return _mutate((current) async {
      final index = current.groups.indexWhere((g) => g.id == id);
      if (index == -1) {
        throw ArgumentError('Group with id $id not found');
      }
      final updatedGroup = current.groups[index].copyWith(name: newName.trim());
      final updatedGroups = List<Group>.from(current.groups);
      updatedGroups[index] = updatedGroup;

      final updatedPayload = current.copyWith(
        groups: updatedGroups,
        modifiedAt: DateTime.now().toUtc(),
      );
      return (payload: updatedPayload, result: null);
    });
  }

  /// Deletes a group and strips its ID from all entries without deleting entries (§4.1, §7.1 #10).
  Future<void> deleteGroup(String id) {
    if (ref.read(selectedGroupIdProvider) == id) {
      ref.read(selectedGroupIdProvider.notifier).selectGroup(null);
    }
    return _mutate((current) async {
      final updatedGroups = current.groups.where((g) => g.id != id).toList();
      final updatedEntries = [
        for (final entry in current.entries)
          if (entry.groupIds.contains(id))
            entry.copyWith(
              groupIds: entry.groupIds.where((gid) => gid != id).toList(),
              updatedAt: DateTime.now().toUtc(),
            )
          else
            entry,
      ];
      final updatedPayload = current.copyWith(
        groups: updatedGroups,
        entries: updatedEntries,
        modifiedAt: DateTime.now().toUtc(),
      );
      return (payload: updatedPayload, result: null);
    });
  }

  /// Reorders groups following Flutter ReorderableListView conventions (§4.1, §7.1 #10).
  Future<void> reorderGroups(int oldIndex, int newIndex) {
    return _mutate((current) async {
      final groups = List<Group>.from(current.groups)
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      var targetIndex = newIndex;
      if (oldIndex < targetIndex) {
        targetIndex -= 1;
      }
      final item = groups.removeAt(oldIndex);
      groups.insert(targetIndex, item);

      final reordered = [
        for (var i = 0; i < groups.length; i++)
          groups[i].copyWith(sortOrder: i),
      ];

      final updatedPayload = current.copyWith(
        groups: reordered,
        modifiedAt: DateTime.now().toUtc(),
      );
      return (payload: updatedPayload, result: null);
    });
  }

  /// Updates the assigned group IDs for an entry (§4.1, §7.1 #5).
  Future<void> setEntryGroups(String entryId, List<String> groupIds) {
    return _mutate((current) async {
      final index = current.entries.indexWhere((e) => e.id == entryId);
      if (index == -1) {
        throw ArgumentError('Entry with id $entryId not found');
      }
      final entry = current.entries[index];
      final updatedEntry = entry.copyWith(
        groupIds: groupIds,
        updatedAt: DateTime.now().toUtc(),
      );
      final updatedEntries = List<OtpEntry>.from(current.entries);
      updatedEntries[index] = updatedEntry;

      final updatedPayload = current.copyWith(
        entries: updatedEntries,
        modifiedAt: DateTime.now().toUtc(),
      );
      return (payload: updatedPayload, result: null);
    });
  }

  /// Exports current vault payload as encrypted bytes (§4.1, §7.1 #11).
  Future<Uint8List> exportBytes() {
    final currentState = state;
    if (currentState is! VaultUnlocked) {
      throw StateError('Cannot export bytes: vault is not unlocked');
    }
    return _repository.exportBytes(currentState.data);
  }

  /// Imports an external vault file and merges entries into the current vault (§4.1, §6.4, §7.1 #11).
  Future<MergeReport> importAndMerge(Uint8List bytes, String password) {
    return _mutex.run(() async {
      final gen = _sessionGeneration;
      final currentState = state;
      if (currentState is! VaultUnlocked ||
          gen != _sessionGeneration ||
          !_repository.isUnlocked) {
        throw StateError('Cannot import and merge: vault is not unlocked');
      }
      final result = await _repository.importAndMerge(
        bytes,
        password,
        currentState.data,
      );
      if (gen != _sessionGeneration ||
          !_repository.isUnlocked ||
          state is! VaultUnlocked) {
        _repository.lock();
        return result.report;
      }
      state = VaultUnlocked(result.merged);
      return result.report;
    });
  }
}

/// Main provider for [VaultController] and [VaultState].
final vaultControllerProvider = NotifierProvider<VaultController, VaultState>(
  VaultController.new,
);

/// Ticker emitting the current Unix epoch seconds every second (§4.1).
Stream<int> _secondTicker() async* {
  yield DateTime.now().millisecondsSinceEpoch ~/ 1000;
  yield* Stream.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
}

/// Global stream provider for TOTP timer updates (§4.1).
final tickerProvider = StreamProvider<int>((ref) => _secondTicker());

/// Search query state notifier (§4.1).
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query;
  void clear() => state = '';
}

/// Provider for entry search filtering (§4.1).
final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

/// Selected group ID filter state notifier (`null` = "All") (§4.1).
class SelectedGroupNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void selectGroup(String? id) => state = id;
}

/// Provider for group chip filtering (§4.1).
final selectedGroupIdProvider =
    NotifierProvider<SelectedGroupNotifier, String?>(SelectedGroupNotifier.new);

/// Filtered and sorted entries provider responding to search query and group selection (§4.1).
final filteredEntriesProvider = Provider<List<OtpEntry>>((ref) {
  final vaultState = ref.watch(vaultControllerProvider);
  if (vaultState is! VaultUnlocked) {
    return const <OtpEntry>[];
  }

  final selectedGroupId = ref.watch(selectedGroupIdProvider);
  final rawQuery = ref.watch(searchQueryProvider).trim().toLowerCase();

  // If a selected group is deleted or missing, gracefully fall back to All (null).
  final effectiveGroupId =
      (selectedGroupId != null &&
          vaultState.data.groups.any((g) => g.id == selectedGroupId))
      ? selectedGroupId
      : null;

  final entries = List<OtpEntry>.from(vaultState.data.entries)
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  return entries.where((entry) {
    if (effectiveGroupId != null &&
        !entry.groupIds.contains(effectiveGroupId)) {
      return false;
    }

    if (rawQuery.isNotEmpty) {
      final inIssuer = entry.issuer.toLowerCase().contains(rawQuery);
      final inAccount = entry.account.toLowerCase().contains(rawQuery);
      final inNote = entry.note.toLowerCase().contains(rawQuery);
      if (!inIssuer && !inAccount && !inNote) {
        return false;
      }
    }

    return true;
  }).toList();
});
