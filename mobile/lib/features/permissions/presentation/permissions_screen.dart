import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/notifications_service.dart';
import '../../../core/notifications/permissions_seen_store.dart';

/// One-time screen shown after a user signs in for the first time. Spec §9
/// (screen 14) — explains *why* we need notifications + location, then
/// requests them. The "Always" upgrade for geofencing is owned by the
/// geofence agent's flow; we ask for "When-In-Use" here per spec §8.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  bool _busyNotif = false;
  bool _busyLoc = false;
  bool _notifGranted = false;
  bool _locGranted = false;

  Future<void> _requestNotifications() async {
    setState(() => _busyNotif = true);
    try {
      final granted =
          await ref.read(notificationsServiceProvider).requestPermission();
      if (!mounted) return;
      setState(() => _notifGranted = granted);
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notifications denied. You can enable them later in Settings.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyNotif = false);
    }
  }

  Future<void> _requestLocation() async {
    setState(() => _busyLoc = true);
    try {
      // When-In-Use only — the spec's escalation to "Always" is owned by
      // the geofence agent and happens after the user adds a car.
      var status = await Geolocator.checkPermission();
      if (status == LocationPermission.denied) {
        status = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      final granted = status == LocationPermission.always ||
          status == LocationPermission.whileInUse;
      setState(() => _locGranted = granted);
      if (status == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location is permanently denied. Enable it in Settings to use auto-logging.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyLoc = false);
    }
  }

  Future<void> _continue() async {
    await ref.read(permissionsSeenStoreProvider).markSeen();
    ref.read(permissionsSeenProvider.notifier).state = true;
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'A couple of permissions help Garage do more for you.',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                "You can grant or revoke either one later in iOS Settings — nothing is irreversible.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 24),
              _PermissionCard(
                icon: Icons.notifications_active,
                title: 'Notifications',
                description:
                    'So we can ping you about service reminders and document expiries before they sneak up on you.',
                buttonLabel: _notifGranted ? 'Allowed' : 'Allow notifications',
                buttonEnabled: !_notifGranted,
                busy: _busyNotif,
                onPressed: _requestNotifications,
              ),
              const SizedBox(height: 12),
              _PermissionCard(
                icon: Icons.location_on,
                title: 'Location',
                description:
                    "Used to detect when you're at a known gas station so we can prompt a fill-up entry. "
                    "When-In-Use is fine to start — Garage will ask for Always later if you opt into background auto-logging.",
                buttonLabel: _locGranted ? 'Allowed' : 'Allow location',
                buttonEnabled: !_locGranted,
                busy: _busyLoc,
                onPressed: _requestLocation,
              ),
              const Spacer(),
              FilledButton(
                onPressed: _continue,
                child: const Text('Continue'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _continue,
                child: const Text('Skip for now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.buttonEnabled,
    required this.busy,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final bool buttonEnabled;
  final bool busy;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed:
                    busy || !buttonEnabled ? null : () => onPressed(),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
