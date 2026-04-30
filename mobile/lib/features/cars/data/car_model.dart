enum FuelType {
  gasoline,
  diesel;

  static FuelType fromString(String s) =>
      FuelType.values.firstWhere((f) => f.name == s, orElse: () => FuelType.gasoline);
}

class Car {
  Car({
    required this.id,
    required this.userId,
    required this.make,
    required this.model,
    required this.year,
    required this.plate,
    this.color,
    required this.currentKm,
    required this.fuelType,
    required this.tankSize,
    this.photoUrl,
    this.avgKmPerDay,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String make;
  final String model;
  final int year;
  final String plate;
  final String? color;
  final int currentKm;
  final FuelType fuelType;
  final double tankSize;
  final String? photoUrl;
  final double? avgKmPerDay;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayName => '$year $make $model';

  factory Car.fromJson(Map<String, dynamic> j) => Car(
        id: j['id'] as String,
        userId: j['userId'] as String,
        make: j['make'] as String,
        model: j['model'] as String,
        year: (j['year'] as num).toInt(),
        plate: j['plate'] as String,
        color: j['color'] as String?,
        currentKm: (j['currentKm'] as num).toInt(),
        fuelType: FuelType.fromString(j['fuelType'] as String),
        tankSize: _parseDecimal(j['tankSize']),
        photoUrl: j['photoUrl'] as String?,
        avgKmPerDay: j['avgKmPerDay'] == null ? null : _parseDecimal(j['avgKmPerDay']),
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'make': make,
        'model': model,
        'year': year,
        'plate': plate,
        'color': color,
        'currentKm': currentKm,
        'fuelType': fuelType.name,
        'tankSize': tankSize,
        'photoUrl': photoUrl,
        'avgKmPerDay': avgKmPerDay,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static double _parseDecimal(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
