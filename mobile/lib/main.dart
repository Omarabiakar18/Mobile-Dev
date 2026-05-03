import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'app.dart';
import 'core/notifications/notifications_service.dart';
import 'core/notifications/permissions_seen_store.dart';
import 'features/geofence/services/geofence_service_wrapper.dart';

Future<void> main() async {
  // Wrap the entire bootstrap in a guarded zone so a plugin failure
  // (notifications, secure-storage, timezone, geofence native side, etc.)
  // never prevents `runApp` from being called. The user gets the splash and
  // then the login screen even when a plugin is broken on the host iOS — the
  // affected feature gracefully degrades. Without this guard a single iOS
  // plugin throw kills the whole app on launch.
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();

  // Step 1: hydrate the permissions-explainer flag. If this fails, default
  // to "not seen" so the user lands on the explainer screen — safe fallback.
  try {
    final seen = await container.read(permissionsSeenStoreProvider).isSeen();
    container.read(permissionsSeenProvider.notifier).state = seen;
  } catch (e, st) {
    debugPrint('permissions-seen hydrate failed: $e\n$st');
  }

  // Step 2: notifications init. We pre-init so cold-start taps replay onto
  // the listener that app.dart attaches. If the plugin throws on this iOS
  // build, the app still boots — local notifications just won't fire. Auth
  // / cars / fuel / OCR / predict still work.
  try {
    await container.read(notificationsServiceProvider).init();
  } catch (e, st) {
    debugPrint('notifications init failed: $e\n$st');
  }

  // Step 3: ALWAYS run the app, even if anything above failed.
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const GarageApp(),
    ),
  );

  // Step 4: geofence bring-up — fire-and-forget, already wrapped in try/catch.
  unawaited(_bootstrapGeofence(container));
}

/// One-shot geofence bring-up. Called from `main()` after `runApp`.
///
///   1. Check whether we have at least `whileInUse` location permission. If
///      not, no-op silently — the permissions screen (owned by the
///      notifications agent) is responsible for prompting.
///   2. Get a one-shot location fix (best-available accuracy, 10s timeout).
///   3. Hand it to [GarageGeofenceService.start] which fetches the nearest
///      gas stations and registers them.
Future<void> _bootstrapGeofence(ProviderContainer container) async {
  try {
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      // User hasn't granted location yet. Silent no-op — they'll be prompted
      // by the explainer flow; the next app launch picks geofencing up.
      return;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      // Device-level Location Services off. Nothing we can do.
      return;
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 10),
      ),
    );

    await container.read(garageGeofenceServiceProvider).start(
      currentLat: pos.latitude,
      currentLng: pos.longitude,
    );
  } catch (e, st) {
    // Don't break the app over a location/geofence failure — log and move on.
    if (kDebugMode) {
      // ignore: avoid_print
      debugPrint('geofence bootstrap failed: $e\n$st');
    }
  }
}
