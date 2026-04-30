class ServiceReminder {
  ServiceReminder({
    required this.id,
    required this.carId,
    required this.serviceType,
    required this.lastDoneKm,
    required this.lastDoneDate,
    this.intervalKm,
    this.intervalMonths,
    required this.isActive,
    this.lastNotifiedAt,
    this.aiMessage,
    this.aiMessageGeneratedAt,
    this.predictedDate,
    this.daysRemaining,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String carId;
  final String serviceType;
  final int lastDoneKm;
  final DateTime lastDoneDate;
  final int? intervalKm;
  final int? intervalMonths;
  final bool isActive;
  final DateTime? lastNotifiedAt;

  /// LLM-phrased one-liner — Phase 4 (§16-B) populates this. Null in Phase 2.
  final String? aiMessage;
  final DateTime? aiMessageGeneratedAt;

  /// Computed by `/cars/:carId/reminders/due`. Null on the regular list.
  final DateTime? predictedDate;
  final int? daysRemaining;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// True when `predictedDate` has already passed.
  bool get isOverdue =>
      predictedDate != null && predictedDate!.isBefore(DateTime.now());

  /// True when due within the next 30 days but not overdue.
  bool get isDueSoon =>
      daysRemaining != null && daysRemaining! >= 0 && daysRemaining! <= 30;

  factory ServiceReminder.fromJson(Map<String, dynamic> j) => ServiceReminder(
        id: j['id'] as String,
        carId: j['carId'] as String,
        serviceType: j['serviceType'] as String,
        lastDoneKm: (j['lastDoneKm'] as num).toInt(),
        lastDoneDate: DateTime.parse(j['lastDoneDate'] as String),
        intervalKm:
            j['intervalKm'] == null ? null : (j['intervalKm'] as num).toInt(),
        intervalMonths: j['intervalMonths'] == null
            ? null
            : (j['intervalMonths'] as num).toInt(),
        isActive: (j['isActive'] as bool?) ?? true,
        lastNotifiedAt: j['lastNotifiedAt'] == null
            ? null
            : DateTime.parse(j['lastNotifiedAt'] as String),
        aiMessage: j['aiMessage'] as String?,
        aiMessageGeneratedAt: j['aiMessageGeneratedAt'] == null
            ? null
            : DateTime.parse(j['aiMessageGeneratedAt'] as String),
        predictedDate: j['predictedDate'] == null
            ? null
            : DateTime.parse(j['predictedDate'] as String),
        daysRemaining: j['daysRemaining'] == null
            ? null
            : (j['daysRemaining'] as num).toInt(),
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'carId': carId,
        'serviceType': serviceType,
        'lastDoneKm': lastDoneKm,
        'lastDoneDate': lastDoneDate.toIso8601String(),
        'intervalKm': intervalKm,
        'intervalMonths': intervalMonths,
        'isActive': isActive,
        'lastNotifiedAt': lastNotifiedAt?.toIso8601String(),
        'aiMessage': aiMessage,
        'aiMessageGeneratedAt': aiMessageGeneratedAt?.toIso8601String(),
        'predictedDate': predictedDate?.toIso8601String(),
        'daysRemaining': daysRemaining,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}
