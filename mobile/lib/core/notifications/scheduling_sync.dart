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

  /// iOS hard-caps pending local notifications at 64 per app and silently drops
  /// excess. We stay under that with headroom for the geofence-fired ad-hoc
  /// notifications. Across all cars × (reminders + documents) × 2 thresholds
  /// (-30d / -7d), the soonest-firing entries win.
  static const _maxScheduled = 50;

  NotificationsService get _notifications =>
      _ref.read(notificationsServiceProvider);

  /// Sync notifications for a single car. Convenience for "user just
  /// added/edited a reminder or document on this car" — re-runs the global
  /// sync so the per-car add doesn't break the global cap.
  Future<void> syncForCar(String _) async => syncForAllCars();

  /// Walks every car the user owns, collects every candidate (reminder ×2,
  /// document ×2) into one global list, sorts by fire-time ascending, takes
  /// the first [_maxScheduled], and schedules. Anything beyond the cap is
  /// explicitly cancelled so a previously-scheduled-but-now-overflowed entry
  /// doesn't linger.
  Future<void> syncForAllCars() async {
    final cars = _ref.read(carsListProvider).valueOrNull ?? const <Car>[];
    if (cars.isEmpty) return;

    // 1. Collect every candidate across every car.
    final candidates = <_Candidate>[];
    for (final car in cars) {
      final reminders = await _safeFuture(
        () => _ref
            .read(remindersApiProvider)
            .due(car.id, withinDays: _windowDays),
      );
      final documents = await _safeFuture(
        () => _ref
            .read(documentsApiProvider)
            .expiring(car.id, withinDays: _windowDays),
      );

      if (reminders != null) {
        for (final r in reminders) {
          candidates.addAll(_remindersToCandidates(r));
        }
      }
      if (documents != null) {
        for (final d in documents) {
          candidates.addAll(_documentsToCandidates(d, car: car));
        }
      }
    }

    // 2. Sort by fire-time ascending (soonest first), drop already-past, cap.
    final now = DateTime.now();
    final futureCandidates = candidates
        .where((c) => c.when.isAfter(now))
        .toList()
      ..sort((a, b) => a.when.compareTo(b.when));

    final keep = futureCandidates.take(_maxScheduled).toList();
    final keepKeys = keep.map((c) => c.key).toSet();

    // 3. Cancel anything previously scheduled that didn't make the cut.
    //    This includes (a) entries shifted to past, (b) entries demoted
    //    by newly-soonest reminders pushing them past the cap, (c) entries
    //    whose underlying reminder/document was deleted.
    for (final c in candidates) {
      if (!keepKeys.contains(c.key)) {
        await _notifications.cancelKeyed(c.key);
      }
    }

    // 4. Schedule the survivors.
    for (final c in keep) {
      await _notifications.scheduleKeyed(
        c.key,
        c.when,
        title: c.title,
        body: c.body,
        payload: c.payload,
        channelKey: NotificationChannel.reminders,
      );
    }
  }

  /// Compatibility shim for sites that called the old per-car method
  /// directly (e.g. AddReminderScreen / AddDocumentScreen). Just runs the
  /// global sync — the new global cap means we have to.
  // ignore: unused_element
  Future<void> _legacyPerCar(String _) => syncForAllCars();

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Iterable<_Candidate> _remindersToCandidates(ServiceReminder r) sync* {
    final due = r.predictedDate;
    if (due == null) return; // skip + cancel-if-present handled by global pass

    final title = '${_humanize(r.serviceType)} due soon';
    final body = (r.aiMessage != null && r.aiMessage!.isNotEmpty)
        ? r.aiMessage!
        : '${_humanize(r.serviceType)} due ~${DateFormat.yMMMd().format(due)}.';
    final payload = {'route': '/cars/${r.carId}/reminders'};

    yield _Candidate(
      key: _reminderKey(r.id, 30),
      when: due.subtract(const Duration(days: 30)),
      title: title,
      body: body,
      payload: payload,
    );
    yield _Candidate(
      key: _reminderKey(r.id, 7),
      when: due.subtract(const Duration(days: 7)),
      title: '${_humanize(r.serviceType)} due in 1 week',
      body: body,
      payload: payload,
    );
  }

  Iterable<_Candidate> _documentsToCandidates(Document d, {Car? car}) sync* {
    final due = d.expiryDate;
    final title = '${d.type.label} expires soon';
    final carName = car?.displayName ?? 'your car';
    final body =
        '${d.type.label} for $carName expires ${DateFormat.yMMMd().format(due)}.';
    final payload = {'route': '/cars/${d.carId}/documents'};

    yield _Candidate(
      key: _docKey(d.id, 30),
      when: due.subtract(const Duration(days: 30)),
      title: title,
      body: body,
      payload: payload,
    );
    yield _Candidate(
      key: _docKey(d.id, 7),
      when: due.subtract(const Duration(days: 7)),
      title: '${d.type.label} expires in 1 week',
      body: body,
      payload: payload,
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

/// One scheduled (or about-to-be-scheduled) notification candidate. We collect
/// these globally first, sort by [when], cap at 50, and only then call the
/// notifications plugin. See `syncForAllCars`.
class _Candidate {
  const _Candidate({
    required this.key,
    required this.when,
    required this.title,
    required this.body,
    required this.payload,
  });

  final String key;
  final DateTime when;
  final String title;
  final String body;
  final Map<String, String> payload;
}
