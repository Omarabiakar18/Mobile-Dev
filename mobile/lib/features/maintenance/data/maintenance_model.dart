enum MaintenanceType {
  oil,
  brakes,
  tires,
  filter,
  battery,
  other;

  static MaintenanceType fromString(String s) =>
      MaintenanceType.values.firstWhere(
        (t) => t.name == s,
        orElse: () => MaintenanceType.other,
      );

  /// Human-friendly label for UI (titlecase, EN).
  String get label {
    switch (this) {
      case MaintenanceType.oil:
        return 'Oil change';
      case MaintenanceType.brakes:
        return 'Brakes';
      case MaintenanceType.tires:
        return 'Tires';
      case MaintenanceType.filter:
        return 'Filter';
      case MaintenanceType.battery:
        return 'Battery';
      case MaintenanceType.other:
        return 'Other';
    }
  }
}

class MaintenancePhoto {
  MaintenancePhoto({
    required this.id,
    required this.maintenanceEntryId,
    required this.url,
    required this.createdAt,
  });

  final String id;
  final String maintenanceEntryId;

  /// Server-relative URL (e.g. `/uploads/maintenance/<id>.jpg`). Resolve against
  /// the API base URL when rendering.
  final String url;
  final DateTime createdAt;

  factory MaintenancePhoto.fromJson(Map<String, dynamic> j) => MaintenancePhoto(
        id: j['id'] as String,
        maintenanceEntryId: j['maintenanceEntryId'] as String,
        url: j['url'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'maintenanceEntryId': maintenanceEntryId,
        'url': url,
        'createdAt': createdAt.toIso8601String(),
      };
}

class MaintenanceEntry {
  MaintenanceEntry({
    required this.id,
    required this.carId,
    required this.date,
    required this.km,
    required this.type,
    this.description,
    required this.cost,
    this.notes,
    required this.photos,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String carId;
  final DateTime date;
  final int km;
  final MaintenanceType type;
  final String? description;
  final double cost;
  final String? notes;
  final List<MaintenancePhoto> photos;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory MaintenanceEntry.fromJson(Map<String, dynamic> j) => MaintenanceEntry(
        id: j['id'] as String,
        carId: j['carId'] as String,
        date: DateTime.parse(j['date'] as String),
        km: (j['km'] as num).toInt(),
        type: MaintenanceType.fromString(j['type'] as String),
        description: j['description'] as String?,
        cost: _parseDecimal(j['cost']),
        notes: j['notes'] as String?,
        photos: ((j['photos'] as List?) ?? const [])
            .map((e) => MaintenancePhoto.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'carId': carId,
        'date': date.toIso8601String(),
        'km': km,
        'type': type.name,
        'description': description,
        'cost': cost,
        'notes': notes,
        'photos': photos.map((p) => p.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static double _parseDecimal(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}

/// Wrapper for the POST /cars/:id/maintenance response so the caller knows
/// whether any service reminders were auto-bumped by the cross-update
/// (Alaa's #3 in HANDOFF.md). The add-maintenance form uses
/// `updatedReminderIds.length` to enrich the success toast.
class CreateMaintenanceResult {
  CreateMaintenanceResult({
    required this.entry,
    required this.updatedReminderIds,
  });

  final MaintenanceEntry entry;
  final List<String> updatedReminderIds;
}
