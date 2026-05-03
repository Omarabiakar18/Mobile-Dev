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
  WidgetsFlutterBinding.ensureInitialized();

  // Build a Riverpod container *before* runApp so the notifications service
  // can attach its tap stream listener BEFORE the cold-start tap is replayed.
  // We then hand the same container to ProviderScope.parent so the rest of
  // the app shares state.
  final container = ProviderContainer();

  // Hydrate the "permissions explainer seen?" flag synchronously-ish so
  // the router's first redirect can decide whether to send the user to
  // /permissions on cold start.
  final seen = await container.read(permissionsSeenStoreProvider).isSeen();
  container.read(permissionsSeenProvider.notifier).state = seen;

  // Initialize the notifications layer. This MUST complete before runApp
  // so the cold-start tap (if any) is replayed onto the broadcast stream
  // that the router subscribes to in app.dart.
  await container.read(notificationsServiceProvider).init();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const GarageApp(),
    ),
  );

  // Phase 5 — kick off geofence registration once the UI is up. Fire-and-
  // forget; failure here just means the user won't get auto-arrival prompts
  // (they can still log fuel manually). Runs after runApp so the splash
  // doesn't block on a 1–2s location fix.
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
