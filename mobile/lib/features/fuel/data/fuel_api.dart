import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/dio_client.dart';
import '../../cars/data/car_model.dart';
import 'fuel_model.dart';
import 'predict_next_model.dart';

class FuelApi {
  FuelApi(this._client);
  final DioClient _client;

  Future<List<FuelEntry>> listForCar(
    String carId, {
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final r = await _client.dio.get<Map<String, dynamic>>(
        '/cars/$carId/fuel',
        queryParameters: {'page': page, 'limit': limit},
      );
      final raw = (r.data?['data']?['entries'] as List?) ?? const [];
      return raw
          .map((e) => FuelEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<FuelEntry> get(String id) async {
    try {
      final r = await _client.dio.get<Map<String, dynamic>>('/fuel/$id');
      return FuelEntry.fromJson(
        r.data!['data']['entry'] as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<FuelEntry> create(
    String carId, {
    required DateTime date,
    required int odometer,
    required double liters,
    required double pricePerLiter,
    required double totalCost,
    required FuelType fuelType,
    String? station,
    bool isFullTank = false,
    double? latitude,
    double? longitude,
    String? notes,
  }) async {
    try {
      final r = await _client.dio.post<Map<String, dynamic>>(
        '/cars/$carId/fuel',
        data: {
          'date': date.toUtc().toIso8601String(),
          'odometer': odometer,
          'liters': liters,
          'pricePerLiter': pricePerLiter,
          'totalCost': totalCost,
          'fuelType': fuelType.name,
          if (station != null && station.isNotEmpty) 'station': station,
          'isFullTank': isFullTank,
          'latitude': ?latitude,
          'longitude': ?longitude,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
      );
      return FuelEntry.fromJson(
        r.data!['data']['entry'] as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<FuelEntry> update(String id, Map<String, dynamic> patch) async {
    try {
      final r = await _client.dio.patch<Map<String, dynamic>>(
        '/fuel/$id',
        data: patch,
      );
      return FuelEntry.fromJson(
        r.data!['data']['entry'] as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.dio.delete<void>('/fuel/$id');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<FuelStats> stats(String carId) async {
    try {
      final r = await _client.dio.get<Map<String, dynamic>>(
        '/cars/$carId/fuel/stats',
      );
      return FuelStats.fromJson(
        (r.data!['data'] as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<FuelPrediction> predictNext(String carId) async {
    try {
      final r = await _client.dio.get<Map<String, dynamic>>(
        '/cars/$carId/fuel/predict-next',
      );
      return FuelPrediction.fromJson(
        (r.data!['data'] as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final fuelApiProvider = Provider<FuelApi>((ref) {
  return FuelApi(ref.watch(dioClientProvider));
});

/// Auto-refreshing fuel list keyed by `carId`. Invalidate via
/// `ref.invalidate(fuelListProvider(carId))` after create/update/delete.
final fuelListProvider =
    FutureProvider.family<List<FuelEntry>, String>((ref, carId) async {
  return ref.watch(fuelApiProvider).listForCar(carId);
});

/// Aggregated fuel stats for a car (totals, last-30/90, avg consumption).
/// Invalidate to force a refresh.
final fuelStatsProvider =
    FutureProvider.family<FuelStats, String>((ref, carId) async {
  return ref.watch(fuelApiProvider).stats(carId);
});

/// Predicted next fill-up payload for a car. The home dashboard's
/// pull-to-refresh invalidates this alongside the other dashboard providers.
final fuelPredictionProvider =
    FutureProvider.family<FuelPrediction, String>((ref, carId) async {
  return ref.watch(fuelApiProvider).predictNext(carId);
});
