import 'otp_algorithm.dart';
import 'otp_type.dart';

/// Represents a single stored 2FA credential.
class OtpEntry {
  const OtpEntry({
    required this.id,
    required this.type,
    required this.issuer,
    required this.account,
    required this.secret,
    this.algorithm = OtpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    this.counter = 0,
    this.groupIds = const <String>[],
    this.note = '',
    this.sortOrder = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final OtpType type;
  final String issuer;
  final String account;
  final String secret;
  final OtpAlgorithm algorithm;
  final int digits;
  final int period;
  final int counter;
  final List<String> groupIds;
  final String note;
  final int sortOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  OtpEntry copyWith({
    String? id,
    OtpType? type,
    String? issuer,
    String? account,
    String? secret,
    OtpAlgorithm? algorithm,
    int? digits,
    int? period,
    int? counter,
    List<String>? groupIds,
    String? note,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OtpEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      issuer: issuer ?? this.issuer,
      account: account ?? this.account,
      secret: secret ?? this.secret,
      algorithm: algorithm ?? this.algorithm,
      digits: digits ?? this.digits,
      period: period ?? this.period,
      counter: counter ?? this.counter,
      groupIds: groupIds ?? this.groupIds,
      note: note ?? this.note,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': type.nameValue,
    'issuer': issuer,
    'account': account,
    'secret': secret,
    'algorithm': algorithm.nameValue,
    'digits': digits,
    'period': period,
    'counter': counter,
    'groupIds': groupIds,
    'note': note,
    'sortOrder': sortOrder,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory OtpEntry.fromJson(Map<String, dynamic> json) {
    return OtpEntry(
      id: json['id'] as String,
      type: OtpType.fromString(json['type'] as String? ?? 'totp'),
      issuer: json['issuer'] as String? ?? '',
      account: json['account'] as String? ?? '',
      secret: json['secret'] as String? ?? '',
      algorithm: OtpAlgorithm.fromString(
        json['algorithm'] as String? ?? 'SHA1',
      ),
      digits: (json['digits'] as num?)?.toInt() ?? 6,
      period: (json['period'] as num?)?.toInt() ?? 30,
      counter: (json['counter'] as num?)?.toInt() ?? 0,
      groupIds:
          (json['groupIds'] as List<dynamic>?)?.cast<String>() ??
          const <String>[],
      note: json['note'] as String? ?? '',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }
}
