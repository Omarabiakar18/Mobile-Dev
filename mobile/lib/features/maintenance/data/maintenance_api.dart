import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/dio_client.dart';
import 'maintenance_model.dart';

class MaintenanceApi {
  MaintenanceApi(this._client);
  final DioClient _client;

  Future<List<MaintenanceEntry>> listForCar(
    String carId, {
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final r = await _client.dio.get<Map<String, dynamic>>(
        '/cars/$carId/maintenance',
        queryParameters: {'page': page, 'limit': limit},
      );
      final raw = (r.data?['data']?['items'] as List?) ?? const [];
      return raw
          .map((e) => MaintenanceEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<MaintenanceEntry> get(String id) async {
    try {
      final r = await _client.dio
          .get<Map<String, dynamic>>('/maintenance/$id');
      return MaintenanceEntry.fromJson(
        r.data!['data']['maintenance'] as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Wraps the create response so the caller knows about the cross-update.
  /// `updatedReminderIds.length` is what the UI shows in the toast.
  Future<CreateMaintenanceResult> create({
    required String carId,
    required DateTime date,
    required int km,
    required MaintenanceType type,
    String? description,
    required double cost,
    String? notes,
  }) async {
    try {
      final r = await _client.dio.post<Map<String, dynamic>>(
        '/cars/$carId/maintenance',
        data: {
          'date': date.toUtc().toIso8601String(),
          'km': km,
          'type': type.name,
          if (description != null && description.isNotEmpty)
            'description': description,
          'cost': cost,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
      );
      final data = (r.data!['data'] as Map).cast<String, dynamic>();
      final entry = MaintenanceEntry.fromJson(
        data['maintenance'] as Map<String, dynamic>,
      );
      // `updatedReminderIds` is additive on the backend — older builds and
      // proxies may strip it, so default to an empty list rather than null
      // here. Defensive against partial deploys.
      final ids = (data['updatedReminderIds'] as List?)?.cast<String>() ?? const [];
      return CreateMaintenanceResult(entry: entry, updatedReminderIds: ids);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<MaintenanceEntry> update(String id, Map<String, dynamic> patch) async {
    try {
      final r = await _client.dio.patch<Map<String, dynamic>>(
        '/maintenance/$id',
        data: patch,
      );
      return MaintenanceEntry.fromJson(
        r.data!['data']['maintenance'] as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.dio.delete<void>('/maintenance/$id');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Multipart upload — field name must be `photo` (matches backend's
  /// `multer.single('photo')`).
  Future<MaintenancePhoto> addPhoto(String maintId, File file) async {
    try {
      final form = FormData.fromMap({
        'photo': await MultipartFile.fromFile(
          file.path,
          filename: file.uri.pathSegments.last,
        ),
      });
      final r = await _client.dio.post<Map<String, dynamic>>(
        '/maintenance/$maintId/photos',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      return MaintenancePhoto.fromJson(
        r.data!['data']['photo'] as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> deletePhoto(String maintId, String photoId) async {
    try {
      await _client.dio
          .delete<void>('/maintenance/$maintId/photos/$photoId');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final maintenanceApiProvider = Provider<MaintenanceApi>((ref) {
  return MaintenanceApi(ref.watch(dioClientProvider));
});

/// Auto-refreshing maintenance list scoped to a single car. Invalidate via
/// `ref.invalidate(maintenanceListProvider(carId))` after mutations.
final maintenanceListProvider =
    FutureProvider.family<List<MaintenanceEntry>, String>((ref, carId) async {
  return ref.watch(maintenanceApiProvider).listForCar(carId);
});
