import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/dio_client.dart';
import '../../auth/presentation/auth_notifier.dart';
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

  /// Multipart upload — field name must be `photo` (matches backend's
  /// `photoUpload.single('photo')`). Returns the updated car with its new
  /// `photoUrl`. Mirrors `MaintenanceApi.addPhoto`.
  Future<Car> setPhoto(String id, File file) async {
    try {
      final form = FormData.fromMap({
        'photo': await MultipartFile.fromFile(
          file.path,
          filename: file.uri.pathSegments.last,
        ),
      });
      final r = await _client.dio.post<Map<String, dynamic>>(
        '/cars/$id/photo',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      return Car.fromJson(r.data!['data']['car'] as Map<String, dynamic>);
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
///
/// Auth-gated: `app.dart`'s router does `ref.listen(carsListProvider)`, which
/// initializes this provider at app startup — BEFORE login. Without the auth
/// dependency it fetched `GET /cars` with no token; the 401 body has no
/// `data.cars`, so `list()` returned `[]`, which got cached as `data([])` and
/// was never re-fetched after login → an empty "no cars" home on first sign-in
/// until the next app launch. Watching `authProvider` makes it (a) skip the
/// pointless pre-login fetch and (b) re-run on the signed-out→signed-in edge.
final carsListProvider = FutureProvider<List<Car>>((ref) async {
  final signedIn = ref.watch(authProvider).maybeWhen(
        data: (u) => u != null,
        orElse: () => false,
      );
  if (!signedIn) return const <Car>[];
  return ref.watch(carsApiProvider).list();
});
