/// A gas station the backend has seeded for geofencing.
///
/// Mirrors the shape returned by `GET /gas-stations`:
/// `{ id, name, latitude, longitude, city }`.
class GasStation {
  GasStation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.city,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String city;

  factory GasStation.fromJson(Map<String, dynamic> j) => GasStation(
        id: j['id'] as String,
        name: j['name'] as String,
        latitude: _parseDouble(j['latitude']),
        longitude: _parseDouble(j['longitude']),
        city: (j['city'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'city': city,
      };

  /// Backend may return Postgres `numeric` columns as strings (e.g. `"33.892"`)
  /// or as JSON numbers depending on driver config. Tolerate both.
  static double _parseDouble(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
