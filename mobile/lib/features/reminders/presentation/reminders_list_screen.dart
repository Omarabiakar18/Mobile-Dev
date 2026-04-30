import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../data/reminder_model.dart';
import '../data/reminders_api.dart';

class RemindersListScreen extends ConsumerWidget {
  const RemindersListScreen({super.key, required this.carId});
  final String carId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(remindersListProvider(carId));

    return Scaffold(
      appBar: AppBar(title: const Text('Service reminders')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(remindersListProvider(carId));
          ref.invalidate(dueRemindersProvider(carId));
        },
        child: reminders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorState(
            message: e is ApiException ? e.message : e.toString(),
            onRetry: () => ref.invalidate(remindersListProvider(carId)),
          ),
          data: (list) => list.isEmpty
              ? _EmptyState(
                  onAdd: () => context.push('/cars/$carId/reminders/new'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _ReminderCard(reminder: list[i]),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add reminder'),
        onPressed: () => context.push('/cars/$carId/reminders/new'),
      ),
    );
  }
}

/// Visual style bucket for a reminder, derived from `daysRemaining`.
class _ProjectionStyle {
  const _ProjectionStyle({
    required this.label,
    required this.icon,
    required this.color,
    required this.emphasized,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool emphasized;

  /// `daysRemaining == null` → "Set an interval to see projection" muted.
  /// `daysRemaining < 0` → red overdue.
  /// `0 <= daysRemaining <= 7` → amber, bold.
  /// `8..30` → normal text, bold.
  /// `> 30` → normal text.
  static _ProjectionStyle resolve(
    BuildContext context,
    ServiceReminder r,
    DateFormat dateFmt,
  ) {
    final theme = Theme.of(context);
    final days = r.daysRemaining;
    if (days == null) {
      return _ProjectionStyle(
        label: 'Set an interval to see projection',
        icon: Icons.schedule_outlined,
        color: theme.colorScheme.outline,
        emphasized: false,
      );
    }
    final dateStr =
        r.predictedDate == null ? '' : ' (${dateFmt.format(r.predictedDate!)})';

    if (days < 0) {
      return _ProjectionStyle(
        label: 'Overdue by ${-days} ${(-days) == 1 ? 'day' : 'days'}$dateStr',
        icon: Icons.error_outline,
        color: theme.colorScheme.error,
        emphasized: true,
      );
    }
    if (days == 0) {
      return _ProjectionStyle(
        label: 'Due today$dateStr',
        icon: Icons.warning_amber_rounded,
        color: Colors.amber.shade800,
        emphasized: true,
      );
    }
    if (days <= 7) {
      return _ProjectionStyle(
        label: 'Due in $days ${days == 1 ? 'day' : 'days'}$dateStr',
        icon: Icons.schedule,
        color: Colors.amber.shade800,
        emphasized: true,
      );
    }
    if (days <= 30) {
      return _ProjectionStyle(
        label: 'Due in $days days$dateStr',
        icon: Icons.schedule,
        color: theme.colorScheme.onSurface,
        emphasized: true,
      );
    }
    // Beyond 30 days — show date for context, calmer emphasis.
    return _ProjectionStyle(
      label: 'Due in $days days$dateStr',
      icon: Icons.schedule_outlined,
      color: theme.colorScheme.onSurface,
      emphasized: false,
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.reminder});
  final ServiceReminder reminder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat.yMMMd();
    final kmFmt = NumberFormat.decimalPattern('en_US');

    final intervalParts = <String>[
      if (reminder.intervalKm != null)
        'every ${kmFmt.format(reminder.intervalKm)} km',
      if (reminder.intervalMonths != null)
        'every ${reminder.intervalMonths} mo',
    ];

    final style = _ProjectionStyle.resolve(context, reminder, dateFmt);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    reminder.serviceType,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (!reminder.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Paused',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Last done at ${kmFmt.format(reminder.lastDoneKm)} km '
              'on ${dateFmt.format(reminder.lastDoneDate)}',
              style: theme.textTheme.bodyMedium,
            ),
            if (intervalParts.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Interval: ${intervalParts.join(' · ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  style.icon,
                  size: 18,
                  color: style.color,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    style.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: style.color,
                      fontWeight: style.emphasized ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ],
            ),
            if (reminder.aiMessage != null && reminder.aiMessage!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        reminder.aiMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      children: [
        Icon(
          Icons.notifications_active_outlined,
          size: 80,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(
          'No reminders yet',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          "Add reminders for things like oil changes and brake pads. "
          "We'll project the next service date from your driving habits.",
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add a reminder'),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text("Couldn't load reminders", style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
