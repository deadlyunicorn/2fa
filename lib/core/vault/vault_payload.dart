import '../models/group.dart';
import '../models/otp_entry.dart';
import 'vault_errors.dart';

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Top-level decrypted database content representation (§5.5).
class VaultPayload {
  VaultPayload({
    this.schemaVersion = 1,
    required this.createdAt,
    required this.modifiedAt,
    List<Group> groups = const <Group>[],
    List<OtpEntry> entries = const <OtpEntry>[],
    this.invalidEntriesSkipped = 0,
  }) : groups = List<Group>.unmodifiable(groups),
       entries = List<OtpEntry>.unmodifiable(entries);

  /// Empty initial vault constructor.
  factory VaultPayload.empty({DateTime? now}) {
    final timestamp = now ?? DateTime.now().toUtc();
    return VaultPayload(
      schemaVersion: 1,
      createdAt: timestamp,
      modifiedAt: timestamp,
      groups: const <Group>[],
      entries: const <OtpEntry>[],
      invalidEntriesSkipped: 0,
    );
  }

  /// Schema version identifier (must be 1 for v1).
  final int schemaVersion;

  /// UTC creation timestamp of the vault.
  final DateTime createdAt;

  /// UTC last modified timestamp of the vault.
  final DateTime modifiedAt;

  /// Categories/tags for organizing entries.
  final List<Group> groups;

  /// Decrypted 2FA TOTP/HOTP entries.
  final List<OtpEntry> entries;

  /// Deserialization metric tracking how many corrupt or missing-field entries were skipped.
  final int invalidEntriesSkipped;

  VaultPayload copyWith({
    int? schemaVersion,
    DateTime? createdAt,
    DateTime? modifiedAt,
    List<Group>? groups,
    List<OtpEntry>? entries,
    int? invalidEntriesSkipped,
  }) {
    return VaultPayload(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      groups: groups ?? this.groups,
      entries: entries ?? this.entries,
      invalidEntriesSkipped:
          invalidEntriesSkipped ?? this.invalidEntriesSkipped,
    );
  }

  /// Serializes payload to a JSON Map conforming to §5.5 schema.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'modifiedAt': modifiedAt.toUtc().toIso8601String(),
    'groups': groups.map((Group g) => g.toJson()).toList(),
    'entries': entries.map((OtpEntry e) => e.toJson()).toList(),
  };

  /// Deserializes a [VaultPayload] from a JSON map (§5.5).
  ///
  /// - Unknown fields are ignored.
  /// - Missing optional fields receive defaults.
  /// - Malformed entries or entries missing required fields (`secret`, `type`)
  ///   are skipped and recorded in [invalidEntriesSkipped].
  /// - Throws [InvalidPayload] if `schemaVersion` is missing or != 1.
  factory VaultPayload.fromJson(Map<String, dynamic> json) {
    final rawVersion = json['schemaVersion'];
    if (rawVersion == null || rawVersion is! num || rawVersion.toInt() != 1) {
      throw InvalidPayload('Unsupported schema version: $rawVersion');
    }
    final int schemaVersion = rawVersion.toInt();

    final DateTime createdAt;
    if (json['createdAt'] != null && json['createdAt'] is String) {
      createdAt =
          DateTime.tryParse(json['createdAt'] as String)?.toUtc() ??
          DateTime.now().toUtc();
    } else {
      createdAt = DateTime.now().toUtc();
    }

    final DateTime modifiedAt;
    if (json['modifiedAt'] != null && json['modifiedAt'] is String) {
      modifiedAt =
          DateTime.tryParse(json['modifiedAt'] as String)?.toUtc() ?? createdAt;
    } else {
      modifiedAt = createdAt;
    }

    final List<Group> groups = <Group>[];
    final rawGroups = json['groups'];
    if (rawGroups is List) {
      for (final raw in rawGroups) {
        if (raw is Map<String, dynamic>) {
          try {
            groups.add(Group.fromJson(raw));
          } catch (_) {
            // Malformed group skipped
          }
        }
      }
    }

    int invalidEntriesSkipped = 0;
    final List<OtpEntry> entries = <OtpEntry>[];
    final rawEntries = json['entries'];
    if (rawEntries is List) {
      for (final raw in rawEntries) {
        if (raw is Map<String, dynamic>) {
          try {
            entries.add(OtpEntry.fromJson(raw));
          } catch (_) {
            invalidEntriesSkipped++;
          }
        } else {
          invalidEntriesSkipped++;
        }
      }
    }

    return VaultPayload(
      schemaVersion: schemaVersion,
      createdAt: createdAt,
      modifiedAt: modifiedAt,
      groups: groups,
      entries: entries,
      invalidEntriesSkipped: invalidEntriesSkipped,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultPayload &&
          runtimeType == other.runtimeType &&
          schemaVersion == other.schemaVersion &&
          createdAt == other.createdAt &&
          modifiedAt == other.modifiedAt &&
          _listEquals(groups, other.groups) &&
          _listEquals(entries, other.entries);

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    createdAt,
    modifiedAt,
    Object.hashAll(groups),
    Object.hashAll(entries),
  );

  @override
  String toString() =>
      'VaultPayload(schemaVersion: $schemaVersion, groups: ${groups.length}, entries: ${entries.length}, invalidSkipped: $invalidEntriesSkipped)';
}
