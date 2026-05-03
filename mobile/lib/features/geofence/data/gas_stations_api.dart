import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/dio_client.dart';
import 'gas_station_model.dart';

/// Thin client for `GET /gas-stations?lat=&lng=&radiusKm=&limit=`.
///
/// The backend is contract-defined to return:
///   `{ data: { stations: [...], origin: {lat,lng}, radiusKm } }`
/// — but we only consume `stations` here. `origin` / `radiusKm` are echoed for
/// debugging and not surfaced to the geofence layer.
class GasStationsApi {
  GasStationsApi(this._client);
  final DioClient _client;

  Future<List<GasStation>> findNearby({
    required double lat,
    required double lng,
    double radiusKm = 10,
    int limit = 10,
  }) async {
    try {
      final r = await _client.dio.get<Map<String, dynamic>>(
        '/gas-stations',
        queryParameters: {
          'lat': lat,
          'lng': lng,
          'radiusKm': radiusKm,
          'limit': limit,
        },
      );
      final raw = (r.data?['data']?['stations'] as List?) ?? const [];
      return raw
          .map((e) => GasStation.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final gasStationsApiProvider = Provider<GasStationsApi>((ref) {
  return GasStationsApi(ref.watch(dioClientProvider));
});
