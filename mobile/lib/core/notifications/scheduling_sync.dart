import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../features/cars/data/cars_api.dart';
import '../../features/cars/data/car_model.dart';
import '../../features/documents/data/documents_api.dart';
import '../../features/documents/data/document_model.dart';
import '../../features/reminders/data/reminders_api.dart';
import '../../features/reminders/data/reminder_model.dart';
import 'notifications_service.dart';

/// Orchestrates the conversion of `due reminders + expiring documents` into
/// scheduled local notifications.
///
/// Spec §6.2 / §6.3: each reminder & each document gets two notifications,
/// at `dueDate - 30d` and `dueDate - 7d`. Past dates are skipped. Existing
/// notifications under the same scheduling key are cancelled first so a
/// shifted predicted date cleanly replaces a stale schedule.
class SchedulingSync {
  SchedulingSync(this._ref);

  final Ref _ref;

  static const _windowDays = 60; // see spec §6.2 — fetch within 60d window

  NotificationsService get _notifications =>
      _ref.read(notificationsServiceProvider);

  /// Sync notifications for a single car. Cheap to call — the work is
  /// bounded by the # of due reminders + expiring documents (~10 max each).
  Future<void> syncForCar(String carId) async {
    final reminders = await _safeFuture(
      () => _ref
          .read(remindersApiProvider)
          .due(carId, withinDays: _windowDays),
    );
    final documents = await _safeFuture(
      () => _ref
          .read(documentsApiProvider)
          .expiring(carId, withinDays: _windowDays),
    );

    final cars = _ref.read(carsListProvider).valueOrNull;
    final car = cars?.where((c) => c.id == carId).firstOrNull;

    if (reminders != null) {
      for (final r in reminders) {
        await _scheduleReminder(r);
      }
    }
    if (documents != null) {
      for (final d in documents) {
        await _scheduleDocument(d, car: car);
      }
    }
  }

  /// Iterates over every car and runs [syncForCar]. Reads the cars list
  /// from `carsListProvider.valueOrNull`; if it hasn't loaded yet, this is
  /// a no-op (caller should refresh first or wait for the FutureProvider).
  Future<void> syncForAllCars() async {
    final cars = _ref.read(carsListProvider).valueOrNull ?? const <Car>[];
    for (final car in cars) {
      await syncForCar(car.id);
    }
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Future<void> _scheduleReminder(ServiceReminder r) async {
    final due = r.predictedDate;
    if (due == null) {
      // Cancel any prior schedule for this reminder — projection is no
      // longer computable (e.g. user removed both intervals).
      await _notifications.cancelKeyed(_reminderKey(r.id, 30));
      await _notifications.cancelKeyed(_reminderKey(r.id, 7));
      return;
    }

    final title = '${_humanize(r.serviceType)} due soon';
    final body = (r.aiMessage != null && r.aiMessage!.isNotEmpty)
        ? r.aiMessage!
        : '${_humanize(r.serviceType)} due ~${DateFormat.yMMMd().format(due)}.';
    final payload = {'route': '/cars/${r.carId}/reminders'};

    await _notifications.scheduleKeyed(
      _reminderKey(r.id, 30),
      due.subtract(const Duration(days: 30)),
      title: title,
      body: body,
      payload: payload,
      channelKey: NotificationChannel.reminders,
    );
    await _notifications.scheduleKeyed(
      _reminderKey(r.id, 7),
      due.subtract(const Duration(days: 7)),
      title: '${_humanize(r.serviceType)} due in 1 week',
      body: body,
      payload: payload,
      channelKey: NotificationChannel.reminders,
    );
  }

  Future<void> _scheduleDocument(Document d, {Car? car}) async {
    final due = d.expiryDate;
    final title = '${d.type.label} expires soon';
    final carName = car?.displayName ?? 'your car';
    final body =
        '${d.type.label} for $carName expires ${DateFormat.yMMMd().format(due)}.';
    final payload = {'route': '/cars/${d.carId}/documents'};

    await _notifications.scheduleKeyed(
      _docKey(d.id, 30),
      due.subtract(const Duration(days: 30)),
      title: title,
      body: body,
      payload: payload,
      channelKey: NotificationChannel.reminders,
    );
    await _notifications.scheduleKeyed(
      _docKey(d.id, 7),
      due.subtract(const Duration(days: 7)),
      title: '${d.type.label} expires in 1 week',
      body: body,
      payload: payload,
      channelKey: NotificationChannel.reminders,
    );
  }

  String _reminderKey(String id, int days) => 'reminder:$id:${days}d';
  String _docKey(String id, int days) => 'doc:$id:${days}d';

  /// Generic fetch wrapper — sync should never crash app launch on a
  /// network blip. Errors are swallowed and logged in debug.
  Future<T?> _safeFuture<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('SchedulingSync: fetch failed — $e\n$st');
      }
      return null;
    }
  }

  /// Turn `oil_change` / `Oil Change` / `oil-change` into `Oil change`.
  static String _humanize(String s) {
    if (s.isEmpty) return s;
    final cleaned = s.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    if (cleaned.isEmpty) return cleaned;
    return cleaned[0].toUpperCase() + cleaned.substring(1).toLowerCase();
  }
}

final schedulingSyncProvider = Provider<SchedulingSync>((ref) {
  return SchedulingSync(ref);
});
