import '../models/group.dart';
import '../models/otp_entry.dart';

/// Top-level decrypted database content representation.
class VaultPayload {
  const VaultPayload({
    this.schemaVersion = 1,
    required this.createdAt,
    required this.modifiedAt,
    this.groups = const <Group>[],
    this.entries = const <OtpEntry>[],
  });

  final int schemaVersion;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final List<Group> groups;
  final List<OtpEntry> entries;

  VaultPayload copyWith({
    int? schemaVersion,
    DateTime? createdAt,
    DateTime? modifiedAt,
    List<Group>? groups,
    List<OtpEntry>? entries,
  }) {
    return VaultPayload(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      groups: groups ?? this.groups,
      entries: entries ?? this.entries,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
    'groups': groups.map((Group g) => g.toJson()).toList(),
    'entries': entries.map((OtpEntry e) => e.toJson()).toList(),
  };

  factory VaultPayload.fromJson(Map<String, dynamic> json) {
    final List<dynamic>? rawGroups = json['groups'] as List<dynamic>?;
    final List<dynamic>? rawEntries = json['entries'] as List<dynamic>?;

    return VaultPayload(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.parse(json['modifiedAt'] as String)
          : DateTime.now(),
      groups:
          rawGroups
              ?.map((dynamic g) => Group.fromJson(g as Map<String, dynamic>))
              .toList() ??
          const <Group>[],
      entries:
          rawEntries
              ?.map((dynamic e) => OtpEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <OtpEntry>[],
    );
  }
}
