import '../otp/base32.dart';
import 'otp_algorithm.dart';
import 'otp_type.dart';

/// Represents a single stored 2FA credential.
class OtpEntry {
  OtpEntry({
    required this.id,
    required this.type,
    this.issuer = '',
    this.account = '',
    required String secret,
    this.algorithm = OtpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    this.counter = 0,
    List<String> groupIds = const <String>[],
    this.note = '',
    this.sortOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : secret = Base32Codec.normalize(secret),
       groupIds = List<String>.unmodifiable(groupIds),
       createdAt = (createdAt ?? DateTime.now()).toUtc(),
       updatedAt = (updatedAt ?? createdAt ?? DateTime.now()).toUtc() {
    if (digits < 6 || digits > 8) {
      throw RangeError.range(digits, 6, 8, 'digits');
    }
    if (period < 1 || period > 300) {
      throw RangeError.range(period, 1, 300, 'period');
    }
    if (counter < 0) {
      throw ArgumentError.value(counter, 'counter', 'Counter must be >= 0');
    }
  }

  /// Unique identifier (UUID v4).
  final String id;

  /// OTP credential type (TOTP or HOTP).
  final OtpType type;

  /// Service provider or organisation issuing the token (e.g. "GitHub").
  final String issuer;

  /// User account or identity (e.g. "alice@example.com").
  final String account;

  /// Normalized Base32 secret string (uppercase, unpadded, without spaces/hyphens).
  final String secret;

  /// HMAC digest algorithm (defaults to SHA1).
  final OtpAlgorithm algorithm;

  /// Number of digits in generated code (6, 7, or 8).
  final int digits;

  /// Step duration in seconds for TOTP (1..300, default 30).
  final int period;

  /// Moving factor counter for HOTP (>= 0).
  final int counter;

  /// List of assigned group IDs.
  final List<String> groupIds;

  /// User-defined freeform text notes.
  final String note;

  /// Manual display order index.
  final int sortOrder;

  /// Timestamp when entry was created (UTC).
  final DateTime createdAt;

  /// Timestamp when entry was last modified (UTC).
  final DateTime updatedAt;

  /// Creates a copy of this [OtpEntry] with modified properties.
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

  /// Serializes this entry to JSON per schema version 1 (§5.5).
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': type.nameValue,
    'issuer': issuer,
    'account': account,
    'secret': secret,
    'algorithm': algorithm.nameValue,
    'digits': digits,
    if (type == OtpType.totp) 'period': period,
    if (type == OtpType.hotp) 'counter': counter,
    'groupIds': groupIds,
    'note': note,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Deserializes an [OtpEntry] from JSON (§5.5).
  ///
  /// Unknown fields are ignored. Missing optional fields receive standard defaults.
  /// Throws [FormatException] if required fields (`type`, `secret`) are missing or invalid,
  /// or if numerical fields (`digits`, `period`, `counter`) are out of range.
  factory OtpEntry.fromJson(Map<String, dynamic> json) {
    final typeRaw = json['type'];
    if (typeRaw == null || typeRaw is! String) {
      throw const FormatException('Missing or invalid required field "type"');
    }
    final OtpType type;
    try {
      type = OtpType.fromString(typeRaw);
    } on FormatException catch (e) {
      throw FormatException('Invalid "type": ${e.message}');
    }

    final secretRaw = json['secret'];
    if (secretRaw == null || secretRaw is! String || secretRaw.trim().isEmpty) {
      throw const FormatException('Missing or empty required field "secret"');
    }
    final String normalizedSecret;
    try {
      normalizedSecret = Base32Codec.normalize(secretRaw);
    } on FormatException catch (e) {
      throw FormatException('Invalid Base32 "secret": ${e.message}');
    }

    final digitsRaw = json['digits'];
    final int digits = (digitsRaw as num?)?.toInt() ?? 6;
    if (digits < 6 || digits > 8) {
      throw FormatException(
        'Invalid "digits": $digits, must be between 6 and 8',
      );
    }

    final periodRaw = json['period'];
    final int period = (periodRaw as num?)?.toInt() ?? 30;
    if (period < 1 || period > 300) {
      throw FormatException(
        'Invalid "period": $period, must be between 1 and 300',
      );
    }

    final counterRaw = json['counter'];
    final int counter = (counterRaw as num?)?.toInt() ?? 0;
    if (counter < 0) {
      throw FormatException('Invalid "counter": $counter, must be >= 0');
    }

    final id = json['id'] as String? ?? '';
    final issuer = (json['issuer'] as String?)?.trim() ?? '';
    final account = (json['account'] as String?)?.trim() ?? '';

    final algoRaw = json['algorithm'] as String?;
    final OtpAlgorithm algorithm;
    if (algoRaw != null && algoRaw.isNotEmpty) {
      try {
        algorithm = OtpAlgorithm.fromString(algoRaw);
      } on FormatException catch (e) {
        throw FormatException('Invalid "algorithm": ${e.message}');
      }
    } else {
      algorithm = OtpAlgorithm.sha1;
    }

    final groupIdsRaw = json['groupIds'];
    final List<String> groupIds = groupIdsRaw is List
        ? List<String>.unmodifiable(groupIdsRaw.map((e) => e.toString()))
        : const <String>[];

    final note = json['note'] as String? ?? '';
    final sortOrder = (json['sortOrder'] as num?)?.toInt() ?? 0;

    final DateTime createdAt;
    if (json['createdAt'] is String) {
      createdAt =
          DateTime.tryParse(json['createdAt'] as String)?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    } else {
      createdAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    final DateTime updatedAt;
    if (json['updatedAt'] is String) {
      updatedAt =
          DateTime.tryParse(json['updatedAt'] as String)?.toUtc() ?? createdAt;
    } else {
      updatedAt = createdAt;
    }

    return OtpEntry(
      id: id,
      type: type,
      issuer: issuer,
      account: account,
      secret: normalizedSecret,
      algorithm: algorithm,
      digits: digits,
      period: period,
      counter: counter,
      groupIds: groupIds,
      note: note,
      sortOrder: sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OtpEntry &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          issuer == other.issuer &&
          account == other.account &&
          secret == other.secret &&
          algorithm == other.algorithm &&
          digits == other.digits &&
          period == other.period &&
          counter == other.counter &&
          _listEquals(groupIds, other.groupIds) &&
          note == other.note &&
          sortOrder == other.sortOrder &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    issuer,
    account,
    secret,
    algorithm,
    digits,
    period,
    counter,
    Object.hashAll(groupIds),
    note,
    sortOrder,
    createdAt,
    updatedAt,
  );

  /// Safe representation that intentionally omits the sensitive secret.
  @override
  String toString() =>
      'OtpEntry(id: $id, type: $type, issuer: $issuer, account: $account, '
      'algorithm: $algorithm, digits: $digits, period: $period, counter: $counter, '
      'groupIds: $groupIds, sortOrder: $sortOrder)';
}
