import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../auth/presentation/auth_notifier.dart';
import '../cars/data/car_model.dart';
import '../cars/data/cars_api.dart';
import '../documents/data/document_model.dart';
import '../documents/data/documents_api.dart';
import '../reminders/data/reminder_model.dart';
import '../reminders/data/reminders_api.dart';
import 'selected_car_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carsAsync = ref.watch(carsListProvider);
    final user = ref.watch(authProvider).maybeWhen(data: (u) => u, orElse: () => null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Garage'),
        actions: [
          IconButton(
            tooltip: 'All cars',
            icon: const Icon(Icons.directions_car_outlined),
            onPressed: () => context.push('/cars'),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: carsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorBlock(
          message: '$e',
          onRetry: () => ref.invalidate(carsListProvider),
        ),
        data: (cars) {
          if (cars.isEmpty) return _NoCarsState(name: user?.name);
          final selected = ref.watch(selectedCarProvider);
          if (selected == null) return const Center(child: CircularProgressIndicator());
          return _Dashboard(car: selected, allCars: cars);
        },
      ),
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.car, required this.allCars});
  final Car car;
  final List<Car> allCars;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final expiring = ref.watch(expiringDocumentsProvider(car.id));
    final due = ref.watch(dueRemindersProvider(car.id));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(carsListProvider);
        ref.invalidate(expiringDocumentsProvider(car.id));
        ref.invalidate(dueRemindersProvider(car.id));
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CarHeader(car: car, allCars: allCars),
          const SizedBox(height: 16),

          // Banners — only render if there's something to show
          expiring.maybeWhen(
            data: (docs) => docs.isEmpty
                ? const SizedBox.shrink()
                : _ExpiringDocsBanner(docs: docs, carId: car.id),
            orElse: () => const SizedBox.shrink(),
          ),
          due.maybeWhen(
            data: (reminders) => reminders.isEmpty
                ? const SizedBox.shrink()
                : _DueRemindersBanner(reminders: reminders, carId: car.id),
            orElse: () => const SizedBox.shrink(),
          ),

          const SizedBox(height: 8),
          _PredictNextCard(car: car),
          const SizedBox(height: 16),

          Text('Quick actions', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _QuickActions(carId: car.id),
          const SizedBox(height: 16),

          OutlinedButton.icon(
            icon: const Icon(Icons.tune),
            label: const Text('View car details'),
            onPressed: () => context.push('/cars/${car.id}'),
          ),
        ],
      ),
    );
  }
}

class _CarHeader extends ConsumerWidget {
  const _CarHeader({required this.car, required this.allCars});
  final Car car;
  final List<Car> allCars;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Icon(
                Icons.directions_car_filled,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (allCars.length > 1)
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isDense: true,
                        value: car.id,
                        items: [
                          for (final c in allCars)
                            DropdownMenuItem(value: c.id, child: Text(c.displayName)),
                        ],
                        onChanged: (id) {
                          if (id != null) {
                            ref.read(selectedCarIdProvider.notifier).state = id;
                          }
                        },
                      ),
                    )
                  else
                    Text(car.displayName, style: theme.textTheme.titleLarge),
                  Text(
                    '${car.plate} · ${car.currentKm} km',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpiringDocsBanner extends StatelessWidget {
  const _ExpiringDocsBanner({required this.docs, required this.carId});
  final List<Document> docs;
  final String carId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final soonest = docs.first;
    final days = soonest.expiryDate.difference(DateTime.now()).inDays;
    final dateStr = DateFormat.yMMMMd().format(soonest.expiryDate);

    final color = days < 0
        ? theme.colorScheme.error
        : days <= 14
            ? theme.colorScheme.error
            : theme.colorScheme.secondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/cars/$carId/documents'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.description_outlined, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      docs.length == 1
                          ? '1 document expiring soon'
                          : '${docs.length} documents expiring soon',
                      style: theme.textTheme.titleSmall?.copyWith(color: color),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      days < 0
                          ? '${soonest.type.label} expired $dateStr'
                          : '${soonest.type.label} expires $dateStr (in $days days)',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _DueRemindersBanner extends StatelessWidget {
  const _DueRemindersBanner({required this.reminders, required this.carId});
  final List<ServiceReminder> reminders;
  final String carId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final soonest = reminders.first;
    final color = (soonest.daysRemaining ?? 0) < 0
        ? theme.colorScheme.error
        : Colors.amber.shade700;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/cars/$carId/reminders'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.build_outlined, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminders.length == 1
                          ? '1 service due soon'
                          : '${reminders.length} services due soon',
                      style: theme.textTheme.titleSmall?.copyWith(color: color),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      soonest.aiMessage ??
                          '${soonest.serviceType}'
                              '${soonest.daysRemaining != null ? ' — in ${soonest.daysRemaining} days' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _PredictNextCard extends StatelessWidget {
  const _PredictNextCard({required this.car});
  final Car car;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Phase 2: predict-next is a stub returning insufficient_data. Real math
    // lands in Phase 3. Render the placeholder state here so the layout is
    // ready for the real card later.
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.local_gas_station_outlined,
                size: 40, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Next fill-up prediction', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Add at least 3 full-tank fill-ups to enable.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.carId});
  final String carId;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.local_gas_station,
            label: 'Add fuel',
            onTap: () => context.push('/cars/$carId/fuel/new'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionTile(
            icon: Icons.build,
            label: 'Maintenance',
            onTap: () => context.push('/cars/$carId/maintenance/new'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionTile(
            icon: Icons.document_scanner_outlined,
            label: 'Scan receipt',
            disabledMessage: 'Coming in Phase 4',
            onTap: null,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.disabledMessage,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? disabledMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final fg = enabled ? theme.colorScheme.onSurface : theme.colorScheme.outline;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: disabledMessage == null
            ? null
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(disabledMessage!),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: fg),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(color: fg),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoCarsState extends StatelessWidget {
  const _NoCarsState({this.name});
  final String? name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
      children: [
        Icon(Icons.directions_car_filled_outlined,
            size: 80, color: theme.colorScheme.outline),
        const SizedBox(height: 16),
        Text(
          name == null ? 'Welcome' : 'Welcome, $name',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Add your first car to start tracking fuel, maintenance, and documents.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add a car'),
          onPressed: () => context.push('/cars/new'),
        ),
      ],
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message, required this.onRetry});
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
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(message, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
