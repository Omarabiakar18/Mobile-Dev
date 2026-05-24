import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/status_chip.dart';
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

enum _Urgency { none, ok, soon, overdue }

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.reminder});
  final ServiceReminder reminder;

  _Urgency get _urgency {
    final days = reminder.daysRemaining;
    if (days == null) return _Urgency.none;
    if (days < 0) return _Urgency.overdue;
    if (days <= 30) return _Urgency.soon;
    return _Urgency.ok;
  }

  Widget? _buildChip() {
    final days = reminder.daysRemaining;
    if (days == null) return null;
    switch (_urgency) {
      case _Urgency.overdue:
        return StatusChip.overdue(label: '${-days} d late');
      case _Urgency.soon:
        return days <= 7
            ? StatusChip.dueSoon(label: days == 0 ? 'Today' : '$days d')
            : StatusChip.dueSoon(label: '$days d');
      case _Urgency.ok:
        return StatusChip.ok(label: '$days d');
      case _Urgency.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final dateFmt = DateFormat.yMMMd();
    final kmFmt = NumberFormat.decimalPattern('en_US');

    final intervalParts = <String>[
      if (reminder.intervalKm != null)
        'every ${kmFmt.format(reminder.intervalKm)} km',
      if (reminder.intervalMonths != null)
        'every ${reminder.intervalMonths} mo',
    ];

    final headlineColor = switch (_urgency) {
      _Urgency.overdue => tokens.danger,
      _Urgency.soon => tokens.warning,
      _Urgency.ok => theme.colorScheme.onSurface,
      _Urgency.none => theme.colorScheme.outline,
    };
    final headline = reminder.predictedDate != null
        ? 'Due ${dateFmt.format(reminder.predictedDate!)}'
        : 'No projection';

    final chip = _buildChip();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.serviceType,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        headline,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: headlineColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (chip != null) chip
                else if (!reminder.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Paused', style: theme.textTheme.labelSmall),
                  ),
              ],
            ),
            if (reminder.aiMessage != null && reminder.aiMessage!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tokens.accent.withValues(alpha: 0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome, size: 16, color: tokens.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        reminder.aiMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Divider(height: 1, color: theme.colorScheme.outline.withValues(alpha: 0.2)),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.history, size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Last: ${kmFmt.format(reminder.lastDoneKm)} km · ${dateFmt.format(reminder.lastDoneDate)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
            if (intervalParts.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.repeat, size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      intervalParts.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
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
