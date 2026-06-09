import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/notifications_service.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/feedback.dart';
import '../../home/selected_car_provider.dart';
import '../data/gas_station_model.dart';
import '../data/gas_stations_api.dart';
import '../data/geo_math.dart';

/// Locally "dropped" demo stations — the "use my current location as a station"
/// button adds one here. Kept in a provider so it survives screen rebuilds and
/// navigation during the demo.
final demoStationsProvider = StateProvider<List<GasStation>>((ref) => const []);

/// Forgiving radius for the live demo. Production geofences use 100 m
/// (`GarageGeofenceService.kRadiusMeters`); we widen to 150 m here so an
/// imperfect indoor GPS fix near a "demo station" still counts as arrived.
const double _kDemoRadiusMeters = 150;
const double _kApproachingMeters = 600;

/// A live, on-screen demonstration that the app reads location and detects
/// gas-station arrival. Shows the device's real GPS, live Haversine distances
/// to every nearby/dropped station, a proximity ring that closes as you
/// approach, an "ARRIVED" detection the moment you cross the radius, AND fires
/// the same arrival notification production uses.
///
/// Two ways to trigger a real detection without driving:
///   1. "Use my current location as a station" — drops a station where you
///      stand, so real GPS instantly detects you're inside it (and notifies).
///   2. "Simulate drive" — animates the position toward a chosen station so the
///      distance visibly closes (backstop if indoor GPS won't move).
class GeofenceLiveScreen extends ConsumerStatefulWidget {
  const GeofenceLiveScreen({super.key});

  @override
  ConsumerState<GeofenceLiveScreen> createState() => _GeofenceLiveScreenState();
}

class _GeofenceLiveScreenState extends ConsumerState<GeofenceLiveScreen> {
  StreamSubscription<Position>? _gpsSub;
  Timer? _simTimer;

  double? _lat;
  double? _lng;
  double? _accuracy;
  bool _gpsLive = false;
  bool _simulating = false;
  GasStation? _simTarget;
  String? _statusNote;
  int _gpsFixes = 0;

  List<GasStation> _apiStations = const [];

  /// The station we last fired an arrival notification for. Cleared when we
  /// leave the radius so a later re-entry notifies again. Prevents spamming a
  /// notification on every position tick while parked inside.
  String? _notifiedStationId;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _simTimer?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    // Make sure notifications can actually show — the arrival prompt needs
    // POST_NOTIFICATIONS on Android 13+.
    unawaited(ref.read(notificationsServiceProvider).requestPermission());

    final serviceOn = await Geolocator.isLocationServiceEnabled();
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    final granted = perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;

    if (!serviceOn || !granted) {
      // Degrade gracefully: seed a Beirut anchor so the "Simulate drive"
      // backstop still works and the seeded stations still load.
      setState(() {
        _statusNote = !serviceOn
            ? 'Location services are off — turn them on, or use Simulate drive.'
            : 'Location permission not granted — use Simulate drive below.';
      });
      _onPosition(33.8938, 35.5018, null, fromGps: false);
      await _fetchNearby(33.8938, 35.5018);
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition();
      _onPosition(pos.latitude, pos.longitude, pos.accuracy, fromGps: true);
      await _fetchNearby(pos.latitude, pos.longitude);
    } catch (_) {
      _onPosition(33.8938, 35.5018, null, fromGps: false);
      await _fetchNearby(33.8938, 35.5018);
    }

    // `high` (not `best`) so the fused provider can use Wi-Fi/cell indoors and
    // actually emit updates — `best` is GPS-only and often starves inside.
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen((pos) {
      // A running simulation overrides the live GPS so the demo drive isn't
      // yanked back to the real (stationary) position.
      if (_simulating) return;
      _onPosition(pos.latitude, pos.longitude, pos.accuracy, fromGps: true);
    });
  }

  Future<void> _fetchNearby(double lat, double lng) async {
    try {
      final stations = await ref.read(gasStationsApiProvider).findNearby(
            lat: lat,
            lng: lng,
            radiusKm: 50,
            limit: 10,
          );
      if (mounted) setState(() => _apiStations = stations);
      _maybeNotifyArrival();
    } catch (_) {
      // Non-fatal — the screen still works with dropped demo stations.
    }
  }

  void _onPosition(double lat, double lng, double? acc,
      {required bool fromGps}) {
    if (!mounted) return;
    setState(() {
      _lat = lat;
      _lng = lng;
      _accuracy = acc;
      _gpsLive = fromGps;
      if (fromGps) _gpsFixes++;
      if (fromGps && !_simulating) _statusNote = null;
    });
    _maybeNotifyArrival();
  }

  void _dropStationHere() {
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null) {
      showFeedback(context, 'No location fix yet — wait a moment.', isError: true);
      return;
    }
    final station = GasStation(
      id: 'demo-${DateTime.now().millisecondsSinceEpoch}',
      name: 'Demo station (here)',
      latitude: lat,
      longitude: lng,
      city: 'Demo location',
    );
    ref.read(demoStationsProvider.notifier).update((list) => [station, ...list]);
    showFeedback(context, 'Station registered at your current location.');
    _maybeNotifyArrival();
  }

  /// Fires the arrival notification exactly once per arrival — when a station
  /// first comes inside the radius. Re-arms when you leave so a later re-entry
  /// notifies again. Same pipeline production uses, driven by the live position.
  void _maybeNotifyArrival() {
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null) return;
    final all = <GasStation>[...ref.read(demoStationsProvider), ..._apiStations];
    GasStation? inside;
    var best = double.infinity;
    for (final s in all) {
      final d = haversineMeters(lat, lng, s.latitude, s.longitude);
      if (d < _kDemoRadiusMeters && d < best) {
        best = d;
        inside = s;
      }
    }
    if (inside == null) {
      _notifiedStationId = null; // left the radius — re-arm
      return;
    }
    if (_notifiedStationId == inside.id) return; // already fired for this arrival
    _notifiedStationId = inside.id;
    _fireArrivalNotification(inside);
  }

  Future<void> _fireArrivalNotification(GasStation station) async {
    final car = ref.read(selectedCarProvider);
    final route = car == null ? '/' : '/cars/${car.id}/fuel/new';
    try {
      await ref.read(notificationsServiceProvider).showNow(
            title: 'At ${station.name}',
            body: 'Tap to log a fill-up.',
            payload: {
              'route': route,
              'stationId': station.id,
              'stationName': station.name,
              'lat': station.latitude.toString(),
              'lng': station.longitude.toString(),
            },
          );
    } catch (_) {
      // Non-fatal — the on-screen banner still shows the detection.
    }
  }

  void _simulateDriveTo(GasStation target) {
    _simTimer?.cancel();
    // Begin ~600 m south-west of the target so there's a visible approach, and
    // re-arm the notification so the simulated arrival fires one.
    _notifiedStationId = null;
    final originLat = target.latitude - 0.005;
    final originLng = target.longitude - 0.005;
    setState(() {
      _simulating = true;
      _simTarget = target;
      _statusNote = 'Simulating drive to ${target.name}';
    });
    const steps = 48;
    var i = 0;
    _simTimer = Timer.periodic(const Duration(milliseconds: 180), (t) {
      i++;
      final frac = i / steps;
      final p = lerpLatLng(
          originLat, originLng, target.latitude, target.longitude, frac);
      _onPosition(p.lat, p.lng, 5, fromGps: false);
      if (i >= steps) t.cancel();
    });
  }

  void _stopSimulation() {
    _simTimer?.cancel();
    setState(() {
      _simulating = false;
      _simTarget = null;
      _statusNote = null;
    });
  }

  void _logFillUp(GasStation station) {
    final car = ref.read(selectedCarProvider);
    if (car == null) {
      showFeedback(context, 'Add or select a car first.', isError: true);
      return;
    }
    // Deep-link to the fuel form pre-filled with the detected station.
    context.push('/cars/${car.id}/fuel/new', extra: station.name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    // Merge dropped demo stations with the seeded backend stations, then sort
    // by live distance from the current position.
    final demo = ref.watch(demoStationsProvider);
    final all = <GasStation>[...demo, ..._apiStations];

    final lat = _lat;
    final lng = _lng;
    final ranked = <({GasStation station, double distance})>[];
    if (lat != null && lng != null) {
      for (final s in all) {
        ranked.add((
          station: s,
          distance: haversineMeters(lat, lng, s.latitude, s.longitude),
        ));
      }
      ranked.sort((a, b) => a.distance.compareTo(b.distance));
    }

    final nearest = ranked.isNotEmpty ? ranked.first : null;
    final arrived = (nearest != null && nearest.distance < _kDemoRadiusMeters)
        ? nearest.station
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Live geofence detection')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _LiveLocationCard(
            lat: lat,
            lng: lng,
            accuracy: _accuracy,
            gpsLive: _gpsLive,
            simulating: _simulating,
            statusNote: _statusNote,
            gpsFixes: _gpsFixes,
          ),
          const SizedBox(height: 16),

          // The proximity ring — visible proof of approach.
          Center(
            child: _ProximityRing(
              distance: nearest?.distance,
              radius: _kDemoRadiusMeters,
              stationName: nearest?.station.name,
              inside: arrived != null,
            ),
          ),
          const SizedBox(height: 16),

          if (arrived != null) ...[
            _ArrivedBanner(
              station: arrived,
              distance: nearest!.distance,
              onLogFillUp: () => _logFillUp(arrived),
            ),
            const SizedBox(height: 16),
          ],

          // Controls.
          FilledButton.icon(
            onPressed: _dropStationHere,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Use my current location as a station'),
          ),
          const SizedBox(height: 8),
          if (_simulating)
            OutlinedButton.icon(
              onPressed: _stopSimulation,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text('Stop simulating (${_simTarget?.name ?? ""})'),
            )
          else
            OutlinedButton.icon(
              onPressed: all.isEmpty ? null : () => _pickSimulateTarget(all),
              icon: const Icon(Icons.directions_car_outlined),
              label: const Text('Simulate drive to a station'),
            ),
          const SizedBox(height: 6),
          Text(
            'Indoors, GPS may not reflect small movements — drop a station here '
            'to detect arrival, or use Simulate drive to show an approach.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),

          const SizedBox(height: 20),
          Text('Stations', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (ranked.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                lat == null
                    ? 'Waiting for a location fix…'
                    : 'No stations nearby. Drop one with the button above.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            ...ranked.map((r) => _StationRow(
                  station: r.station,
                  distance: r.distance,
                  radius: _kDemoRadiusMeters,
                  tokens: tokens,
                )),
        ],
      ),
    );
  }

  Future<void> _pickSimulateTarget(List<GasStation> stations) async {
    final picked = await showModalBottomSheet<GasStation>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Drive to which station?'),
            ),
            for (final s in stations)
              ListTile(
                leading: const Icon(Icons.local_gas_station_outlined),
                title: Text(s.name),
                subtitle: Text(s.city),
                onTap: () => Navigator.of(context).pop(s),
              ),
          ],
        ),
      ),
    );
    if (picked != null) _simulateDriveTo(picked);
  }
}

class _LiveLocationCard extends StatelessWidget {
  const _LiveLocationCard({
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.gpsLive,
    required this.simulating,
    required this.statusNote,
    required this.gpsFixes,
  });

  final double? lat;
  final double? lng;
  final double? accuracy;
  final bool gpsLive;
  final bool simulating;
  final String? statusNote;
  final int gpsFixes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    final Color dot;
    final String mode;
    if (simulating) {
      dot = tokens.accent;
      mode = 'SIMULATED';
    } else if (gpsLive) {
      dot = tokens.success;
      mode = 'GPS · LIVE';
    } else {
      dot = theme.colorScheme.onSurfaceVariant;
      mode = 'NO FIX';
    }

    final detail = accuracy != null
        ? 'Accuracy ±${accuracy!.toStringAsFixed(0)} m · $gpsFixes GPS updates'
        : (statusNote ?? 'Acquiring GPS…');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.my_location, color: dot, size: 20),
                const SizedBox(width: 8),
                Text('Your location', style: theme.textTheme.titleSmall),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: dot.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    mode,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: dot, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              lat == null
                  ? '—'
                  : '${lat!.toStringAsFixed(5)},  ${lng!.toStringAsFixed(5)}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 2),
            Text(
              statusNote != null && accuracy == null ? statusNote! : detail,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Concentric range rings with "you" at the centre and the nearest station as
/// a dot whose radial position tracks its real distance — it slides toward the
/// centre as you approach and turns green when inside the geofence radius.
class _ProximityRing extends StatelessWidget {
  const _ProximityRing({
    required this.distance,
    required this.radius,
    required this.stationName,
    required this.inside,
  });

  final double? distance;
  final double radius;
  final String? stationName;
  final bool inside;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final dotColor = inside ? tokens.success : tokens.accent;

    return SizedBox(
      width: 240,
      height: 240,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: CustomPaint(
          key: ValueKey<String>(
            '${distance?.round()}-${inside ? "in" : "out"}',
          ),
          painter: _RingPainter(
            distance: distance,
            radius: radius,
            ringColor: theme.colorScheme.outline,
            insideColor: tokens.success,
            dotColor: dotColor,
            labelColor: theme.colorScheme.onSurfaceVariant,
            youColor: theme.colorScheme.primary,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  distance == null ? '—' : _fmtDistance(distance!),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: inside ? tokens.success : null,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (stationName != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      inside ? 'INSIDE · $stationName' : 'to $stationName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.distance,
    required this.radius,
    required this.ringColor,
    required this.insideColor,
    required this.dotColor,
    required this.labelColor,
    required this.youColor,
  });

  final double? distance;
  final double radius;
  final Color ringColor;
  final Color insideColor;
  final Color dotColor;
  final Color labelColor;
  final Color youColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxPx = size.width / 2 - 10;
    // The outermost ring maps to ~4× the geofence radius so an approach is
    // visible before you cross in.
    final maxMeters = radius * 4;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = ringColor;

    // Geofence radius ring (highlighted).
    final radiusPx = (radius / maxMeters) * maxPx;
    final geoRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = insideColor.withValues(alpha: 0.7);

    // Three faint guide rings + the geofence ring.
    for (final frac in [0.34, 0.67, 1.0]) {
      canvas.drawCircle(center, maxPx * frac, ringPaint);
    }
    canvas.drawCircle(center, radiusPx, geoRing);

    // "You" at the centre.
    canvas.drawCircle(center, 5, Paint()..color = youColor);

    // The nearest station dot, placed at a fixed bearing (up-right) so it reads
    // cleanly; only its RADIAL distance changes as you approach.
    if (distance != null) {
      final clampedM = math.min(distance!, maxMeters);
      final r = (clampedM / maxMeters) * maxPx;
      const angle = -math.pi / 4; // up-right
      final dot = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
      canvas.drawLine(
        center,
        dot,
        Paint()
          ..color = dotColor.withValues(alpha: 0.4)
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(dot, 7, Paint()..color = dotColor);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.distance != distance ||
      old.radius != radius ||
      old.dotColor != dotColor;
}

class _ArrivedBanner extends StatelessWidget {
  const _ArrivedBanner({
    required this.station,
    required this.distance,
    required this.onLogFillUp,
  });

  final GasStation station;
  final double distance;
  final VoidCallback onLogFillUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return Card(
      color: tokens.successContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: tokens.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Arrival detected',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: tokens.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'You are at ${station.name} — detected at '
              '${distance.toStringAsFixed(0)} m. A notification was sent.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onLogFillUp,
              icon: const Icon(Icons.local_gas_station),
              label: const Text('Log fill-up'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationRow extends StatelessWidget {
  const _StationRow({
    required this.station,
    required this.distance,
    required this.radius,
    required this.tokens,
  });

  final GasStation station;
  final double distance;
  final double radius;
  final GarageColors tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (String label, Color color) = distance < radius
        ? ('INSIDE', tokens.success)
        : distance < _kApproachingMeters
            ? ('Approaching', tokens.warning)
            : ('Far', theme.colorScheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.local_gas_station_outlined,
              size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  station.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                Text(
                  _fmtDistance(distance),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtDistance(double meters) {
  if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
  return '${(meters / 1000).toStringAsFixed(2)} km';
}
