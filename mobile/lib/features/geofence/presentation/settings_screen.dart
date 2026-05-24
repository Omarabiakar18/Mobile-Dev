import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/notifications/notifications_service.dart';
import '../../../core/notifications/scheduling_sync.dart';
import '../../../core/ui/feedback.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/gas_station_model.dart';
import '../services/geofence_service_wrapper.dart';

/// Spec §9 screen 13 — Profile / Settings.
///
/// Stub for v1: surface the user, give them a way out (sign out), expose
/// shortcuts to the iOS Settings app for granting permissions, and host the
/// "Simulate Geofence Entry" debug button that drives the demo §10 step 7.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user =
        ref.watch(authProvider).maybeWhen(data: (u) => u, orElse: () => null);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader(label: 'Profile', theme: theme),
          if (user == null)
            const ListTile(
              leading: Icon(Icons.person_outline),
              title: Text('Not signed in'),
            )
          else
            ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.secondaryContainer,
                child: Icon(
                  Icons.person,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              title: Text(user.name),
              subtitle: Text(user.email),
            ),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              'Sign out',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => ref.read(authProvider.notifier).logout(),
          ),

          _SectionHeader(label: 'Notifications', theme: theme),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notification permissions'),
            subtitle: const Text('Open iOS Settings to manage'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => openAppSettings(),
          ),

          _SectionHeader(label: 'Location', theme: theme),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Location permissions'),
            subtitle: const Text('Open iOS Settings to manage'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => openAppSettings(),
          ),

          if (kDebugMode) ...[
            _SectionHeader(label: 'Debug tools', theme: theme),
            ListTile(
              leading: const Icon(Icons.location_searching),
              title: const Text('Simulate geofence entry'),
              subtitle: const Text(
                'Fire the dwell-complete notification for a registered station',
              ),
              onTap: () => _onSimulateTapped(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Fire test notification in 60s'),
              subtitle: const Text(
                'Schedules a one-shot local notification 60 seconds from now',
              ),
              onTap: () => _onFireTestNotification(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Force schedule resync'),
              subtitle: const Text(
                'Re-runs SchedulingSync across every car (reminders + docs)',
              ),
              onTap: () => _onForceResync(context, ref),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _onFireTestNotification(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final notifications = ref.read(notificationsServiceProvider);
    final when = DateTime.now().add(const Duration(seconds: 60));
    final id = await notifications.scheduleAt(
      when,
      title: 'Garage test notification',
      body: 'Scheduled at ${TimeOfDay.fromDateTime(when).format(context)} — '
          'if you see this, the notification pipeline works.',
      payload: const {'route': '/settings'},
    );
    if (!context.mounted) return;
    showFeedback(
      context,
      id < 0
          ? 'Failed to schedule notification'
          : 'Scheduled — wait ~60s with app in background',
      isError: id < 0,
    );
  }

  Future<void> _onForceResync(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(schedulingSyncProvider).syncForAllCars();
      if (!context.mounted) return;
      showFeedback(context, 'Notification schedule resynced');
    } catch (e) {
      if (!context.mounted) return;
      showFeedback(context, 'Resync failed: $e', isError: true);
    }
  }

  Future<void> _onSimulateTapped(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final svc = ref.read(garageGeofenceServiceProvider);

    // simulateCandidates() prefers already-registered stations, but falls
    // back to a Beirut-anchored API fetch so the demo button works even on
    // a fresh install where location permission hasn't been granted yet.
    final stations = await svc.simulateCandidates();
    if (stations.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No gas stations available — check API connection.')),
      );
      return;
    }

    if (!context.mounted) return;
    final picked = await showModalBottomSheet<GasStation>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => _StationPickerSheet(stations: stations),
    );
    if (picked == null) return;

    final ok = await svc.simulateEntry(stationId: picked.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Simulated entry: ${picked.name}'
              : 'Simulation failed for ${picked.name}',
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.theme});
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _StationPickerSheet extends StatelessWidget {
  const _StationPickerSheet({required this.stations});
  final List<GasStation> stations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'Pick a station to simulate',
              style: theme.textTheme.titleMedium,
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: stations.length,
              itemBuilder: (_, i) {
                final s = stations[i];
                return ListTile(
                  leading: const Icon(Icons.local_gas_station_outlined),
                  title: Text(s.name),
                  subtitle: Text(s.city),
                  onTap: () => Navigator.of(context).pop(s),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
