import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geofence_service/geofence_service.dart' as gfs;

import '../../../core/notifications/notifications_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../../home/selected_car_provider.dart';
import '../data/gas_station_model.dart';
import '../data/gas_stations_api.dart';

/// Wraps [gfs.GeofenceService] so the rest of the app never has to import the
/// underlying package. Public surface:
///
///   - `start({ currentLat, currentLng })`  — fetch nearest 10 gas stations,
///     register them as geofences, attach the dwell-timer listener.
///   - `stop()`                              — cancel timers, unregister.
///   - `simulateEntry({ stationId })`        — bypasses real geofence events
///     and fires the dwell-completion logic immediately.
///   - `registeredStations`                  — UI accessor for the debug
///     bottom-sheet on the Settings screen.
///
/// In-memory only by design — the spec calls for re-registering on every
/// app launch (a fresh `start()` call) rather than persisting across runs.
///
/// Notes / limitations:
///   - The underlying `geofence_service` package does NOT use iOS's native
///     `CLCircularRegion` API; it polls `CLLocation` via `fl_location` while
///     the app is alive (or registered as a background location task). The
///     iOS 20-region cap doesn't apply to us, but battery does — start small.
///   - We disable `useActivityRecognition` so we don't need
///     `NSMotionUsageDescription` in Info.plist.
class GarageGeofenceService {
  GarageGeofenceService({required Ref ref}) : _ref = ref;

  final Ref _ref;

  /// Underlying singleton from the geofence_service package. We use a single
  /// instance app-wide because the package itself is a singleton.
  final gfs.GeofenceService _service = gfs.GeofenceService.instance.setup(
    interval: 5000,
    accuracy: 100,
    // The package's own `loiteringDelayMs` would mark a radius as DWELL
    // automatically; we instead manage the 2-minute dwell ourselves with a
    // foreground Timer so we can show progress / cancel cleanly on EXIT.
    // 60s here is just a sanity floor for the underlying package.
    loiteringDelayMs: 60000,
    statusChangeDelayMs: 10000,
    useActivityRecognition: false,
    allowMockLocations: false,
    printDevLog: kDebugMode,
    geofenceRadiusSortType: gfs.GeofenceRadiusSortType.DESC,
  );

  /// Stations we registered with the service on the most recent `start()`.
  /// Keyed by station id so [simulateEntry] can look them up.
  final Map<String, GasStation> _registered = <String, GasStation>{};

  /// Per-station dwell timers — when a timer completes we fire the local
  /// notification. Cancelled on EXIT before completion.
  final Map<String, Timer> _dwellTimers = <String, Timer>{};

  bool _listenerAttached = false;

  /// Snapshot of the currently-registered stations (debug UI uses this).
  List<GasStation> get registeredStations => _registered.values.toList();

  /// True once we've successfully registered at least one geofence in the
  /// current process. Reset by [stop].
  bool get isRunning => _registered.isNotEmpty;

  /// Spec §8: dwell duration before we fire the "log a fill-up?" prompt.
  /// 2 minutes — long enough that you've actually parked, short enough that
  /// the prompt is still timely.
  static const Duration kDwellDuration = Duration(minutes: 2);

  /// Spec §8: every registered geofence is a 100m circle centered on the
  /// station coordinates.
  static const double kRadiusMeters = 100;

  /// Bring the geofence layer up. Idempotent: safe to call repeatedly — each
  /// call clears the previous registration and re-registers from scratch.
  Future<void> start({
    required double currentLat,
    required double currentLng,
  }) async {
    // No-op if the user isn't authenticated. The gas-stations endpoint requires
    // a bearer token, so calling it would just 401 + bounce the user to login.
    final tokens = _ref.read(tokenStorageProvider);
    final access = await tokens.readAccess();
    if (access == null) {
      _log('start: skipped (no access token, user not authenticated)');
      return;
    }

    final List<GasStation> stations;
    try {
      stations = await _ref.read(gasStationsApiProvider).findNearby(
        lat: currentLat,
        lng: currentLng,
        // Spec §8 says 10km radius; we widen to 15km here so the demo doesn't
        // miss a station the user happens to drive 12km to. Backend will still
        // cap at `limit: 10`.
        radiusKm: 15,
        limit: 10,
      );
    } catch (e, st) {
      _log('start: gas-stations API failed: $e\n$st');
      return;
    }

    if (stations.isEmpty) {
      _log('start: 0 stations within 15km of ($currentLat, $currentLng)');
      return;
    }

    // Tear down any prior registration first so a re-start is clean.
    await _stopInternal();

    final geofences = <gfs.Geofence>[
      for (final s in stations)
        gfs.Geofence(
          id: s.id,
          // We stash the station object itself in `data` so the listener can
          // recover full station info without a lookup.
          data: s,
          latitude: s.latitude,
          longitude: s.longitude,
          radius: <gfs.GeofenceRadius>[
            gfs.GeofenceRadius(id: 'r100', length: kRadiusMeters),
          ],
        ),
    ];

    for (final s in stations) {
      _registered[s.id] = s;
    }

    if (!_listenerAttached) {
      _service.addGeofenceStatusChangeListener(_onStatusChange);
      _service.addStreamErrorListener(_onStreamError);
      _listenerAttached = true;
    }

    try {
      // The package complains with ALREADY_STARTED if start() is invoked twice,
      // so use addGeofenceList when it's already running.
      if (_service.isRunningService) {
        _service.addGeofenceList(geofences);
      } else {
        await _service.start(geofences);
      }
      _log(
        'start: registered ${geofences.length} geofences '
        '(stations: ${stations.map((s) => s.name).join(", ")})',
      );
    } catch (e, st) {
      _log('start: GeofenceService.start failed: $e\n$st');
    }
  }

  /// Cancel timers, clear registered geofences. Safe to call when not started.
  Future<void> stop() async {
    await _stopInternal();
    if (_listenerAttached) {
      _service.removeGeofenceStatusChangeListener(_onStatusChange);
      _service.removeStreamErrorListener(_onStreamError);
      _listenerAttached = false;
    }
    if (_service.isRunningService) {
      try {
        await _service.stop();
      } catch (e) {
        _log('stop: GeofenceService.stop failed: $e');
      }
    }
  }

  Future<void> _stopInternal() async {
    for (final t in _dwellTimers.values) {
      t.cancel();
    }
    _dwellTimers.clear();
    _registered.clear();
    _service.clearGeofenceList();
  }

  /// Debug helper. Bypasses real geofence events and fires the same dwell-
  /// completion logic immediately for the given station.
  ///
  /// Returns true if the station was found and the notification was fired.
  /// Falls back to fetching the station from the backend when registration
  /// hasn't happened yet (e.g. demo machine outside the seeded radius, or
  /// location permission not yet granted) so the demo button still works.
  Future<bool> simulateEntry({required String stationId}) async {
    var station = _registered[stationId];
    if (station == null) {
      // Last-ditch: hit the API and grab the station directly. Any registered
      // station is in our DB, and we keep the call cheap by using a tiny
      // search radius from a Beirut-ish anchor that the seed always covers.
      try {
        final stations = await _ref
            .read(gasStationsApiProvider)
            .findNearby(lat: 33.8938, lng: 35.5018, radiusKm: 30, limit: 50);
        station = stations.where((s) => s.id == stationId).firstOrNull;
      } catch (e) {
        _log('simulateEntry: API fallback failed — $e');
      }
    }
    if (station == null) {
      _log('simulateEntry: unknown station $stationId');
      return false;
    }
    await _fireDwellNotification(station);
    return true;
  }

  /// Returns the list of stations that the demo's "Simulate geofence entry"
  /// bottom sheet can pick from. Prefers the already-registered set (so the
  /// menu shows the same stations geofencing watches in production), but
  /// falls back to a Beirut-anchored API fetch when nothing's registered yet.
  Future<List<GasStation>> simulateCandidates() async {
    if (_registered.isNotEmpty) return _registered.values.toList();
    try {
      return await _ref
          .read(gasStationsApiProvider)
          .findNearby(lat: 33.8938, lng: 35.5018, radiusKm: 30, limit: 10);
    } catch (e) {
      _log('simulateCandidates: API fallback failed — $e');
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<void> _onStatusChange(
    gfs.Geofence geofence,
    gfs.GeofenceRadius geofenceRadius,
    gfs.GeofenceStatus status,
    gfs.Location location,
  ) async {
    final station = _registered[geofence.id];
    if (station == null) {
      // Stale event for a station we've since unregistered.
      return;
    }

    switch (status) {
      case gfs.GeofenceStatus.ENTER:
        // Start (or restart) the 2-minute dwell timer. If a prior timer is
        // already running for this station, replace it — most recent ENTER
        // wins.
        _dwellTimers[station.id]?.cancel();
        _log('ENTER: ${station.name} — starting ${kDwellDuration.inSeconds}s dwell timer');
        _dwellTimers[station.id] = Timer(kDwellDuration, () {
          _dwellTimers.remove(station.id);
          // Don't await: the listener signature is fire-and-forget once the
          // timer fires.
          unawaited(_fireDwellNotification(station));
        });
        break;
      case gfs.GeofenceStatus.EXIT:
        final cancelled = _dwellTimers.remove(station.id);
        if (cancelled != null) {
          cancelled.cancel();
          _log('EXIT: ${station.name} — dwell timer cancelled before completion');
        }
        break;
      case gfs.GeofenceStatus.DWELL:
        // The package's own DWELL fires after `loiteringDelayMs` — we ignore
        // it since we manage dwell ourselves with the timer above.
        break;
    }
  }

  /// Fires the local notification + builds the deep-link payload. Pulls the
  /// active car id from `selectedCarIdProvider`; if no car is selected the
  /// route falls back to the home dashboard so the tap still does *something*
  /// reasonable.
  Future<void> _fireDwellNotification(GasStation station) async {
    final selectedCarId = _ref.read(selectedCarIdProvider);
    final route = selectedCarId == null
        ? '/'
        : '/cars/$selectedCarId/fuel/new';

    final payload = <String, String>{
      'route': route,
      'stationId': station.id,
      'stationName': station.name,
      'lat': station.latitude.toString(),
      'lng': station.longitude.toString(),
    };

    try {
      final id = await _ref.read(notificationsServiceProvider).showNow(
        title: 'At ${station.name}',
        body: 'Tap to log a fill-up.',
        payload: payload,
      );
      _log(
        'dwell complete: fired notification id=$id station=${station.name} '
        'route=$route',
      );
    } catch (e, st) {
      _log('dwell complete: showNow failed: $e\n$st');
    }
  }

  void _onStreamError(dynamic error) {
    _log('stream error: $error');
  }

  void _log(String message) {
    if (kReleaseMode) return;
    dev.log(message, name: 'geofence');
  }
}

final garageGeofenceServiceProvider = Provider<GarageGeofenceService>((ref) {
  // The service is a singleton across the app's lifetime — we hold onto `ref`
  // (not specific providers) so dependent reads happen lazily when geofence
  // events fire, after the timer callback runs outside the original call stack.
  final svc = GarageGeofenceService(ref: ref);
  ref.onDispose(svc.stop);
  return svc;
});
