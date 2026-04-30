/// Confidence buckets returned by `GET /cars/:carId/fuel/predict-next`.
///
/// - [ok]: enough full-tank data to compute a real prediction. Numeric fields
///   ([FuelPrediction.tankRemainingLiters], [FuelPrediction.consumptionPer100km],
///   [FuelPrediction.kmSinceLastFull]) are present. [FuelPrediction.daysRemaining]
///   may still be null when the car has no `avgKmPerDay` yet.
/// - [insufficientData]: fewer than 3 full-tank fill-ups on the car. UI should
///   prompt the user to log more.
/// - [dataInconsistent]: the car's current odometer is below the last full-tank
///   odometer. Something was mistyped — UI nudges the user to fix entries.
enum PredictConfidence {
  ok,
  insufficientData,
  dataInconsistent;

  /// Maps the wire string ("ok", "insufficient_data", "data_inconsistent") to
  /// the enum. Falls back to [insufficientData] on unknown values so the UI
  /// stays in the safe "ask for more data" state.
  static PredictConfidence fromString(String s) {
    switch (s) {
      case 'ok':
        return PredictConfidence.ok;
      case 'data_inconsistent':
        return PredictConfidence.dataInconsistent;
      case 'insufficient_data':
      default:
        return PredictConfidence.insufficientData;
    }
  }

  /// Wire string corresponding to the enum value.
  String get name {
    switch (this) {
      case PredictConfidence.ok:
        return 'ok';
      case PredictConfidence.dataInconsistent:
        return 'data_inconsistent';
      case PredictConfidence.insufficientData:
        return 'insufficient_data';
    }
  }
}

/// Response shape of `GET /cars/:carId/fuel/predict-next` (spec §6.1).
///
/// All numeric fields can be null depending on [confidence]:
///   - When `confidence == ok`, [tankRemainingLiters], [consumptionPer100km]
///     and [kmSinceLastFull] are present.
///   - [daysRemaining] / [predictedDate] are non-null only when the car has
///     enough driving data for an `avgKmPerDay` estimate.
class FuelPrediction {
  FuelPrediction({
    required this.confidence,
    this.tankRemainingLiters,
    this.daysRemaining,
    this.predictedDate,
    this.consumptionPer100km,
    this.kmSinceLastFull,
  });

  final PredictConfidence confidence;
  final double? tankRemainingLiters;
  final int? daysRemaining;
  final DateTime? predictedDate;
  final double? consumptionPer100km;
  final int? kmSinceLastFull;

  factory FuelPrediction.fromJson(Map<String, dynamic> j) => FuelPrediction(
        confidence: PredictConfidence.fromString(j['confidence'] as String),
        tankRemainingLiters: j['tankRemainingLiters'] == null
            ? null
            : _parseDecimal(j['tankRemainingLiters']),
        daysRemaining: j['daysRemaining'] == null
            ? null
            : (j['daysRemaining'] as num).toInt(),
        predictedDate: j['predictedDate'] == null
            ? null
            : DateTime.parse(j['predictedDate'] as String),
        consumptionPer100km: j['consumptionPer100km'] == null
            ? null
            : _parseDecimal(j['consumptionPer100km']),
        kmSinceLastFull: j['kmSinceLastFull'] == null
            ? null
            : (j['kmSinceLastFull'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'confidence': confidence.name,
        'tankRemainingLiters': tankRemainingLiters,
        'daysRemaining': daysRemaining,
        'predictedDate': predictedDate?.toIso8601String(),
        'consumptionPer100km': consumptionPer100km,
        'kmSinceLastFull': kmSinceLastFull,
      };

  static double _parseDecimal(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
