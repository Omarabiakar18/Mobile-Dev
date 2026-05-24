import 'package:flutter/material.dart';

/// Friendlier loading state for cold-start / first-fetch screens. Shows a
/// spinner plus a contextual [label] so users don't stare at a blank screen
/// wondering if the app froze — matters especially over `adb reverse` and
/// LAN tunnels where the first request can take a couple of seconds.
///
/// Used uniformly across every list/feature screen instead of a bare
/// [CircularProgressIndicator]. The dio client retries transient network
/// errors twice with backoff, which extends the "loading" window — this
/// widget makes that window legible instead of mysterious.
///
/// Pass a [label] that names what's being fetched (e.g. "Loading your
/// garage…", "Loading reminders…"). Keep it short — one line.
class ConnectingState extends StatelessWidget {
  const ConnectingState({super.key, this.label = 'Loading…'});

  /// Short contextual line beneath the spinner. Defaults to the generic
  /// "Loading…" but every caller should pass something specific.
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 20),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
