import 'dart:math' as math;

/// Great-circle distance in **meters** between two lat/lng points (Haversine).
///
/// This is the exact same computation the geofence detection runs on every
/// location update to decide whether you're inside a station's radius — kept
/// pure (no Flutter, no I/O) so it can be unit-tested in isolation.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusM = 6371000.0;
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusM * c;
}

/// Linear interpolation between two coordinates — used by the "simulate drive"
/// backstop to animate a position moving from `start` toward `target`.
/// `t` runs 0.0 (start) → 1.0 (target). Fine for the short, local distances a
/// demo drive covers; not geodesically exact, but visually correct.
({double lat, double lng}) lerpLatLng(
  double startLat,
  double startLng,
  double targetLat,
  double targetLng,
  double t,
) {
  final clamped = t.clamp(0.0, 1.0);
  return (
    lat: startLat + (targetLat - startLat) * clamped,
    lng: startLng + (targetLng - startLng) * clamped,
  );
}

double _toRad(double deg) => deg * math.pi / 180.0;
