/// Category or tag for organizing OTP entries.
class Group {
  const Group({required this.id, required this.name, this.sortOrder = 0});

  /// Unique identifier (UUID v4).
  final String id;

  /// Human-readable group name.
  final String name;

  /// Relative display sort order.
  final int sortOrder;

  /// Creates a copy of this [Group] with updated values.
  Group copyWith({String? id, String? name, int? sortOrder}) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// Converts this [Group] to a JSON map.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'sortOrder': sortOrder,
  };

  /// Constructs a [Group] from a JSON map.
  ///
  /// Throws [FormatException] if required fields are missing or invalid.
  factory Group.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id == null || id is! String || id.trim().isEmpty) {
      throw const FormatException('Group id is required and cannot be empty');
    }

    final name = json['name'];
    if (name == null || name is! String) {
      throw const FormatException('Group name is required');
    }

    return Group(
      id: id.trim(),
      name: name,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Group &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          sortOrder == other.sortOrder;

  @override
  int get hashCode => Object.hash(id, name, sortOrder);

  @override
  String toString() => 'Group(id: $id, name: $name, sortOrder: $sortOrder)';
}
