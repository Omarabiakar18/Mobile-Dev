import 'package:flutter_test/flutter_test.dart';
import 'package:garage/features/geofence/data/geo_math.dart';

void main() {
  group('haversineMeters', () {
    test('is zero for identical points', () {
      expect(
        haversineMeters(33.8938, 35.5018, 33.8938, 35.5018),
        closeTo(0, 0.001),
      );
    });

    test('~111 m for 0.001° of latitude', () {
      // 0.001° latitude ≈ 111.3 m anywhere on Earth.
      final d = haversineMeters(33.8938, 35.5018, 33.8948, 35.5018);
      expect(d, closeTo(111.3, 2));
    });

    test('~1.11 km for 0.01° of latitude', () {
      final d = haversineMeters(33.0, 35.0, 33.01, 35.0);
      expect(d, closeTo(1113, 10));
    });

    test('is symmetric', () {
      final a = haversineMeters(33.8938, 35.5018, 33.9000, 35.5100);
      final b = haversineMeters(33.9000, 35.5100, 33.8938, 35.5018);
      expect(a, closeTo(b, 0.001));
    });
  });

  group('lerpLatLng', () {
    test('returns start at t=0 and target at t=1', () {
      final start = lerpLatLng(33.0, 35.0, 34.0, 36.0, 0.0);
      expect(start.lat, 33.0);
      expect(start.lng, 35.0);
      final end = lerpLatLng(33.0, 35.0, 34.0, 36.0, 1.0);
      expect(end.lat, 34.0);
      expect(end.lng, 36.0);
    });

    test('midpoint at t=0.5', () {
      final mid = lerpLatLng(33.0, 35.0, 34.0, 36.0, 0.5);
      expect(mid.lat, closeTo(33.5, 1e-9));
      expect(mid.lng, closeTo(35.5, 1e-9));
    });

    test('clamps t outside [0,1]', () {
      final under = lerpLatLng(33.0, 35.0, 34.0, 36.0, -1.0);
      expect(under.lat, 33.0);
      final over = lerpLatLng(33.0, 35.0, 34.0, 36.0, 2.0);
      expect(over.lat, 34.0);
    });
  });
}
