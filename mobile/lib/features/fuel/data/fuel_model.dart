import 'package:intl/intl.dart';

import '../../cars/data/car_model.dart';

class FuelEntry {
  FuelEntry({
    required this.id,
    required this.carId,
    required this.date,
    required this.odometer,
    required this.liters,
    required this.pricePerLiter,
    required this.totalCost,
    required this.fuelType,
    this.station,
    required this.isFullTank,
    this.receiptPhotoUrl,
    this.latitude,
    this.longitude,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String carId;
  final DateTime date;
  final int odometer;
  final double liters;
  final double pricePerLiter;
  final double totalCost;
  final FuelType fuelType;
  final String? station;
  final bool isFullTank;
  final String? receiptPhotoUrl;
  final double? latitude;
  final double? longitude;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Compact one-liner for list rows, e.g. "45.2 L · $67.80 · 14,235 km".
  String displaySummary() {
    final litersFmt = liters.toStringAsFixed(liters % 1 == 0 ? 0 : 1);
    final costFmt = NumberFormat.currency(
      locale: 'en_US',
      symbol: '\$',
      decimalDigits: 2,
    ).format(totalCost);
    final odoFmt = NumberFormat.decimalPattern('en_US').format(odometer);
    return '$litersFmt L · $costFmt · $odoFmt km';
  }

  factory FuelEntry.fromJson(Map<String, dynamic> j) => FuelEntry(
        id: j['id'] as String,
        carId: j['carId'] as String,
        date: DateTime.parse(j['date'] as String),
        odometer: (j['odometer'] as num).toInt(),
        liters: _parseDecimal(j['liters']),
        pricePerLiter: _parseDecimal(j['pricePerLiter']),
        totalCost: _parseDecimal(j['totalCost']),
        fuelType: FuelType.fromString(j['fuelType'] as String),
        station: j['station'] as String?,
        isFullTank: (j['isFullTank'] as bool?) ?? false,
        receiptPhotoUrl: j['receiptPhotoUrl'] as String?,
        latitude: j['latitude'] == null ? null : _parseDecimal(j['latitude']),
        longitude: j['longitude'] == null ? null : _parseDecimal(j['longitude']),
        notes: j['notes'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'carId': carId,
        'date': date.toIso8601String(),
        'odometer': odometer,
        'liters': liters,
        'pricePerLiter': pricePerLiter,
        'totalCost': totalCost,
        'fuelType': fuelType.name,
        'station': station,
        'isFullTank': isFullTank,
        'receiptPhotoUrl': receiptPhotoUrl,
        'latitude': latitude,
        'longitude': longitude,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static double _parseDecimal(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
