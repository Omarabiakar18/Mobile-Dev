import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/dio_client.dart';
import 'reminder_model.dart';

class RemindersApi {
  RemindersApi(this._client);
  final DioClient _client;

  Future<List<ServiceReminder>> listForCar(String carId) async {
    try {
      final r = await _client.dio.get<Map<String, dynamic>>(
        '/cars/$carId/reminders',
      );
      final raw = (r.data?['data']?['reminders'] as List?) ?? const [];
      return raw
          .map((e) => ServiceReminder.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<ServiceReminder> create({
    required String carId,
    required String serviceType,
    required int lastDoneKm,
    required DateTime lastDoneDate,
    int? intervalKm,
    int? intervalMonths,
    bool isActive = true,
  }) async {
    try {
      final r = await _client.dio.post<Map<String, dynamic>>(
        '/cars/$carId/reminders',
        data: {
          'serviceType': serviceType,
          'lastDoneKm': lastDoneKm,
          'lastDoneDate': lastDoneDate.toIso8601String(),
          'intervalKm': ?intervalKm,
          'intervalMonths': ?intervalMonths,
          'isActive': isActive,
        },
      );
      return ServiceReminder.fromJson(
        r.data!['data']['reminder'] as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<ServiceReminder> update(String id, Map<String, dynamic> patch) async {
    try {
      final r = await _client.dio.patch<Map<String, dynamic>>(
        '/reminders/$id',
        data: patch,
      );
      return ServiceReminder.fromJson(
        r.data!['data']['reminder'] as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.dio.delete<void>('/reminders/$id');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Reminders due within `withinDays`. Each row carries a non-null
  /// `predictedDate` and `daysRemaining`.
  Future<List<ServiceReminder>> due(
    String carId, {
    int withinDays = 30,
  }) async {
    try {
      final r = await _client.dio.get<Map<String, dynamic>>(
        '/cars/$carId/reminders/due',
        queryParameters: {'withinDays': withinDays},
      );
      final raw = (r.data?['data']?['reminders'] as List?) ?? const [];
      return raw
          .map((e) => ServiceReminder.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final remindersApiProvider = Provider<RemindersApi>((ref) {
  return RemindersApi(ref.watch(dioClientProvider));
});

/// Auto-refreshing reminders list for a given car.
/// Invalidate via `ref.invalidate(remindersListProvider(carId))` after mutations.
final remindersListProvider =
    FutureProvider.family<List<ServiceReminder>, String>((ref, carId) async {
  return ref.watch(remindersApiProvider).listForCar(carId);
});

/// Due-within-30-days list, used by the home dashboard banner.
final dueRemindersProvider =
    FutureProvider.family<List<ServiceReminder>, String>((ref, carId) async {
  return ref.watch(remindersApiProvider).due(carId);
});
