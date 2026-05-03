/// Pre-fill payload returned by `POST /cars/:carId/fuel/ocr` (spec §7).
///
/// Backend contract (per the OCR backend agent):
///   {
///     "fields":     { liters, pricePerLiter, totalCost, station, date },
///     "confidence": { liters, pricePerLiter, totalCost, station, date },
///     "rawText":    string,
///     "parsedBy":   "llm" | "regex" | "cache" | "demo" | "failed",
///     "photoUrl":   "/uploads/ocr/HASH.jpg" | null
///   }
///
/// Every field value can come back as `number | string | null`; confidences
/// are normalized to `0..1`. `parsedBy == "failed"` means the pipeline gave
/// up — the UI should treat it as an error and offer manual entry.
///
/// We keep numeric fields as `double?`/`int?` after parsing so the form can
/// `.toString()` them straight into `TextEditingController`s. `date` stays a
/// `DateTime?` so the form's date picker can pick it up directly. `station`
/// passes through as a string (whitespace-trimmed).
///
/// `receiptPhotoUrl` is the relative URL of the post-preprocess JPEG the
/// backend served from `/uploads/ocr/<hash>.jpg`. The form passes this URL
/// through to `POST /cars/:carId/fuel` so the saved fuel entry keeps a
/// permanent link to the receipt image.
class OcrPrefill {
  OcrPrefill({
    this.liters,
    this.pricePerLiter,
    this.totalCost,
    this.station,
    this.date,
    this.receiptPhotoUrl,
    required this.confidence,
    required this.rawText,
    required this.parsedBy,
  });

  final double? liters;
  final double? pricePerLiter;
  final double? totalCost;
  final String? station;
  final DateTime? date;
  final String? receiptPhotoUrl;

  /// Per-field confidence score in `[0, 1]`. Missing entries are treated as 0.
  final Map<String, double> confidence;

  final String rawText;
  final String parsedBy;

  /// Whether the OCR pipeline considers this response a failure. The camera
  /// screen uses this to short-circuit straight to manual entry.
  bool get failed => parsedBy == 'failed';

  /// Returns the confidence for [field] or `0` if missing. Field names match
  /// the keys the backend emits: `liters`, `pricePerLiter`, `totalCost`,
  /// `station`, `date`.
  double confidenceFor(String field) => confidence[field] ?? 0;

  /// Parse the response shape documented at the top of this file. Numbers
  /// are coerced from `num` or numeric strings; the `date` field accepts
  /// either an ISO-8601 string or `null`.
  factory OcrPrefill.fromJson(Map<String, dynamic> j) {
    final fields = (j['fields'] as Map?)?.cast<String, dynamic>() ?? const {};
    final conf = (j['confidence'] as Map?)?.cast<String, dynamic>() ?? const {};

    return OcrPrefill(
      liters: _parseDouble(fields['liters']),
      pricePerLiter: _parseDouble(fields['pricePerLiter']),
      totalCost: _parseDouble(fields['totalCost']),
      station: _parseString(fields['station']),
      date: _parseDate(fields['date']),
      receiptPhotoUrl: _parseString(j['photoUrl']),
      confidence: {
        for (final k in const [
          'liters',
          'pricePerLiter',
          'totalCost',
          'station',
          'date',
        ])
          k: _parseConfidence(conf[k]),
      },
      rawText: (j['rawText'] as String?) ?? '',
      parsedBy: (j['parsedBy'] as String?) ?? 'failed',
    );
  }

  static double? _parseDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  static String? _parseString(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static DateTime? _parseDate(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  /// Confidences are clamped to `[0, 1]` so misbehaving backends can't drive
  /// the UI threshold into nonsense territory.
  static double _parseConfidence(Object? v) {
    final d = _parseDouble(v);
    if (d == null) return 0;
    if (d.isNaN) return 0;
    return d.clamp(0.0, 1.0);
  }
}
