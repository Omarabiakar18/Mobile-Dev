import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cars/data/cars_api.dart';

/// The car the home dashboard is currently focused on.
/// `null` until the cars list resolves with at least one entry.
/// Persistence across launches is intentionally not handled in v1 — the home
/// screen always defaults to the most-recently-created car on cold start.
final selectedCarIdProvider = StateProvider<String?>((ref) => null);

/// The full Car for the currently selected id, derived from the cars list.
/// Returns null when the list is loading, the user has no cars, or the
/// selected id no longer matches any car (e.g. after deletion).
final selectedCarProvider = Provider((ref) {
  final id = ref.watch(selectedCarIdProvider);
  final cars = ref.watch(carsListProvider);
  return cars.maybeWhen(
    data: (list) {
      if (list.isEmpty) return null;
      // If no selection yet, or the selection no longer exists, pick the first.
      if (id == null || !list.any((c) => c.id == id)) return list.first;
      return list.firstWhere((c) => c.id == id);
    },
    orElse: () => null,
  );
});
