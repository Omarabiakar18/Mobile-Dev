import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../auth/presentation/auth_notifier.dart';
import '../cars/data/car_model.dart';
import '../cars/data/cars_api.dart';
import '../documents/data/document_model.dart';
import '../documents/data/documents_api.dart';
import '../fuel/data/fuel_api.dart';
import '../fuel/data/predict_next_model.dart';
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
        ref.invalidate(fuelPredictionProvider(car.id));
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

/// Renders the predict-next card on the home dashboard. Three confidence
/// states map to three layouts; tapping the card opens an explanation sheet.
class _PredictNextCard extends ConsumerWidget {
  const _PredictNextCard({required this.car});
  final Car car;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fuelPredictionProvider(car.id));
    return async.when(
      loading: () => const _PredictCardShell.loading(),
      error: (_, _) => const _PredictCardShell.error(),
      data: (p) => _PredictCardShell(car: car, prediction: p),
    );
  }
}

/// Stateless renderer for the predict card. Splits state-shape decisions out
/// of the Riverpod-watching widget for testability.
class _PredictCardShell extends StatelessWidget {
  const _PredictCardShell({required this.car, required this.prediction})
      : _loading = false,
        _hasError = false;
  const _PredictCardShell.loading()
      : car = null,
        prediction = null,
        _loading = true,
        _hasError = false;
  const _PredictCardShell.error()
      : car = null,
        prediction = null,
        _loading = false,
        _hasError = true;

  final Car? car;
  final FuelPrediction? prediction;
  final bool _loading;
  final bool _hasError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
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
                    Text('Next fill-up prediction',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_hasError) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.local_gas_station_outlined,
                  size: 40, color: theme.colorScheme.outline),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Next fill-up prediction',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text("Couldn't load prediction. Pull to refresh.",
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final p = prediction!;
    final c = car!;
    switch (p.confidence) {
      case PredictConfidence.insufficientData:
        return _InsufficientCard(theme: theme);
      case PredictConfidence.dataInconsistent:
        return _InconsistentCard(theme: theme, carId: c.id);
      case PredictConfidence.ok:
        return _OkCard(theme: theme, car: c, prediction: p);
    }
  }
}

class _InsufficientCard extends StatelessWidget {
  const _InsufficientCard({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
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
                  Text('Next fill-up prediction',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Add at least 3 full-tank fill-ups to enable predictions.',
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

class _InconsistentCard extends StatelessWidget {
  const _InconsistentCard({required this.theme, required this.carId});
  final ThemeData theme;
  final String carId;

  @override
  Widget build(BuildContext context) {
    final color = theme.colorScheme.error;
    return Card(
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // The fuel list lives inside the car detail TabBar, so navigate to
        // `/cars/:id` rather than a non-existent `/cars/:id/fuel` route.
        onTap: () => context.push('/cars/$carId'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, size: 40, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Check your fuel entries',
                      style: theme.textTheme.titleSmall?.copyWith(color: color),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your latest odometer is below the last fill-up — '
                      'check your entries.',
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

class _OkCard extends StatelessWidget {
  const _OkCard({
    required this.theme,
    required this.car,
    required this.prediction,
  });

  final ThemeData theme;
  final Car car;
  final FuelPrediction prediction;

  @override
  Widget build(BuildContext context) {
    final liters = prediction.tankRemainingLiters ?? 0;
    final litersStr = '${liters.toStringAsFixed(1)} L';
    // Server returns fractional days (e.g. 10.6); round at render time so the
    // display reads "10 days" while the underlying value preserves precision.
    final daysExact = prediction.daysRemaining;
    final days = daysExact?.round();

    final hasDate = days != null;
    final daysColor = !hasDate
        ? theme.colorScheme.onSurface
        : (days <= 0
            ? theme.colorScheme.error
            : (days <= 3
                ? Colors.amber.shade800
                : theme.colorScheme.onSurface));

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showExplainSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.local_gas_station,
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Next fill-up prediction',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    if (hasDate)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$days',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: daysColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            days == 1 ? 'day' : 'days',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: daysColor,
                            ),
                          ),
                          if (prediction.predictedDate != null) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '≈ ${DateFormat.MMMd().format(prediction.predictedDate!)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      )
                    else
                      Text(
                        'Tank: ~$litersStr remaining',
                        style: theme.textTheme.titleMedium,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      hasDate
                          ? '$litersStr left in tank'
                          : 'Add daily driving data for date estimate',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.info_outline, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  void _showExplainSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final consumption = prediction.consumptionPer100km;
        final kmSince = prediction.kmSinceLastFull;
        final pace = car.avgKmPerDay;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How we got this number',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                if (consumption != null)
                  _ExplainRow(
                    icon: Icons.speed_outlined,
                    label: 'Avg consumption',
                    value: '${consumption.toStringAsFixed(1)} L/100km',
                  ),
                if (kmSince != null)
                  _ExplainRow(
                    icon: Icons.route_outlined,
                    label: 'Driven since last full tank',
                    value: '$kmSince km',
                  ),
                if (pace != null)
                  _ExplainRow(
                    icon: Icons.directions_car_outlined,
                    label: 'Daily pace',
                    value: '${pace.toStringAsFixed(0)} km/day',
                  ),
                if (prediction.tankRemainingLiters != null)
                  _ExplainRow(
                    icon: Icons.local_gas_station_outlined,
                    label: 'Tank remaining',
                    value:
                        '${prediction.tankRemainingLiters!.toStringAsFixed(1)} L',
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  // TODO(phase4 §16-C): replace this static note with the LLM
                  // explanation from `GET /cars/:carId/fuel/predict-next/explain`.
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 18,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'These numbers come from your fuel entries. '
                          'AI explanation lands in Phase 4.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ExplainRow extends StatelessWidget {
  const _ExplainRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.outline),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
