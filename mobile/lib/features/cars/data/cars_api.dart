import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/dio_client.dart';
import 'car_model.dart';

class CarsApi {
  CarsApi(this._client);
  final DioClient _client;

  Future<List<Car>> list() async {
    try {
      final r = await _client.dio.get<Map<String, dynamic>>('/cars');
      final raw = (r.data?['data']?['cars'] as List?) ?? const [];
      return raw.map((e) => Car.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Car> get(String id) async {
    try {
      final r = await _client.dio.get<Map<String, dynamic>>('/cars/$id');
      return Car.fromJson(r.data!['data']['car'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Car> create({
    required String make,
    required String model,
    required int year,
    required String plate,
    String? color,
    required int currentKm,
    required FuelType fuelType,
    required double tankSize,
  }) async {
    try {
      final r = await _client.dio.post<Map<String, dynamic>>(
        '/cars',
        data: {
          'make': make,
          'model': model,
          'year': year,
          'plate': plate,
          if (color != null && color.isNotEmpty) 'color': color,
          'currentKm': currentKm,
          'fuelType': fuelType.name,
          'tankSize': tankSize,
        },
      );
      return Car.fromJson(r.data!['data']['car'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Car> update(String id, Map<String, dynamic> patch) async {
    try {
      final r = await _client.dio.patch<Map<String, dynamic>>(
        '/cars/$id',
        data: patch,
      );
      return Car.fromJson(r.data!['data']['car'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.dio.delete<void>('/cars/$id');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final carsApiProvider = Provider<CarsApi>((ref) {
  return CarsApi(ref.watch(dioClientProvider));
});

/// Auto-refreshing cars list. Riverpod re-runs this when `ref.invalidate(carsListProvider)`
/// is called from create/update/delete flows.
final carsListProvider = FutureProvider<List<Car>>((ref) async {
  return ref.watch(carsApiProvider).list();
});
