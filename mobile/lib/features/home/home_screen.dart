import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/connecting_state.dart';
import '../../core/ui/status_chip.dart';
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
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: carsAsync.when(
        loading: () => const ConnectingState(label: 'Loading your garage…'),
        error: (e, _) => _ErrorBlock(
          message: e is ApiException ? e.message : 'Something went wrong.',
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
    final tokens = context.tokens;
    final multipleCars = allCars.length > 1;
    final kmFormatted = NumberFormat.decimalPattern('en_US').format(car.currentKm);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: multipleCars ? () => _openSwitcher(context, ref) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.directions_car_filled,
                  color: tokens.accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            car.displayName,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (multipleCars) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.unfold_more,
                            size: 18,
                            color: theme.colorScheme.outline,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${car.plate} · $kmFormatted km',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSwitcher(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final tokens = sheetCtx.tokens;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Switch car', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                for (final c in allCars)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c.id == car.id
                            ? tokens.accent.withValues(alpha: 0.20)
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.directions_car_filled,
                        color: c.id == car.id
                            ? tokens.accent
                            : theme.colorScheme.outline,
                      ),
                    ),
                    title: Text(c.displayName),
                    subtitle: Text(
                      '${c.plate} · ${NumberFormat.decimalPattern('en_US').format(c.currentKm)} km',
                    ),
                    trailing: c.id == car.id
                        ? Icon(Icons.check_circle,
                            color: tokens.success, size: 20)
                        : null,
                    onTap: () {
                      ref.read(selectedCarIdProvider.notifier).state = c.id;
                      Navigator.of(sheetCtx).pop();
                    },
                  ),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.add, color: theme.colorScheme.outline),
                  ),
                  title: const Text('Add another car'),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    context.push('/cars/new');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shared banner shell — card with a colored left bar, icon, two-line text,
/// chevron, and a StatusChip in the corner. Reused by docs + reminders.
class _AlertBanner extends StatelessWidget {
  const _AlertBanner({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.chip,
    required this.onTap,
  });
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget chip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 4, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, color: color, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  chip,
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right,
                            size: 20, color: theme.colorScheme.outline),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    final tokens = context.tokens;
    final soonest = docs.first;
    final days = soonest.expiryDate.difference(DateTime.now()).inDays;
    final dateStr = DateFormat.MMMd().format(soonest.expiryDate);
    final overdue = days < 0;
    final urgent = days >= 0 && days <= 14;

    final color = overdue || urgent ? tokens.danger : tokens.warning;
    final chip = overdue
        ? StatusChip.overdue(label: 'Expired')
        : urgent
            ? StatusChip.overdue(label: '$days d')
            : StatusChip.dueSoon(label: '$days d');

    final title = docs.length == 1
        ? '${soonest.type.label} expiring'
        : '${docs.length} documents expiring';
    final subtitle = overdue
        ? '${soonest.type.label} expired $dateStr'
        : '${soonest.type.label} · $dateStr';

    return _AlertBanner(
      color: color,
      icon: Icons.description_outlined,
      title: title,
      subtitle: subtitle,
      chip: chip,
      onTap: () => context.push('/cars/$carId/documents'),
    );
  }
}

class _DueRemindersBanner extends StatelessWidget {
  const _DueRemindersBanner({required this.reminders, required this.carId});
  final List<ServiceReminder> reminders;
  final String carId;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final soonest = reminders.first;
    final daysRemaining = soonest.daysRemaining ?? 0;
    final overdue = daysRemaining < 0;
    final color = overdue ? tokens.danger : tokens.warning;
    final chip = overdue
        ? StatusChip.overdue(label: '${-daysRemaining} d late')
        : StatusChip.dueSoon(label: '$daysRemaining d');

    final title = reminders.length == 1
        ? soonest.serviceType
        : '${reminders.length} services due';
    final subtitle = soonest.aiMessage ??
        (overdue
            ? '${soonest.serviceType} was due ${-daysRemaining} days ago'
            : '${soonest.serviceType} due in $daysRemaining days');

    return _AlertBanner(
      color: color,
      icon: Icons.build_outlined,
      title: title,
      subtitle: subtitle,
      chip: chip,
      onTap: () => context.push('/cars/$carId/reminders'),
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
    final tokens = context.tokens;
    final liters = prediction.tankRemainingLiters ?? 0;
    final tank = car.tankSize.toDouble();
    final tankFraction = tank > 0 ? (liters / tank).clamp(0.0, 1.0) : 0.0;
    final litersStr = liters.toStringAsFixed(1);
    final daysExact = prediction.daysRemaining;
    final days = daysExact?.round();
    final hasDate = days != null;
    final isUrgent = hasDate && days <= 3;
    final isOverdue = hasDate && days <= 0;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showExplainSheet(context),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tokens.hero,
                Color.alphaBlend(Colors.black.withValues(alpha: 0.30), tokens.hero),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_gas_station,
                        size: 18, color: Colors.white.withValues(alpha: 0.8)),
                    const SizedBox(width: 8),
                    Text(
                      'Next fill-up',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const Spacer(),
                    if (isOverdue)
                      StatusChip.overdue(label: 'Now'),
                    if (isUrgent && !isOverdue)
                      StatusChip.dueSoon(label: 'Soon'),
                    const SizedBox(width: 6),
                    Icon(Icons.info_outline,
                        size: 18, color: Colors.white.withValues(alpha: 0.7)),
                  ],
                ),
                const SizedBox(height: 12),
                if (hasDate)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$days',
                        style: theme.textTheme.displayMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                          letterSpacing: -1.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          days == 1 ? 'day' : 'days',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (prediction.predictedDate != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '≈ ${DateFormat.MMMd().format(prediction.predictedDate!)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                    ],
                  )
                else
                  Text(
                    '~$litersStr L',
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 14),
                _TankGauge(fraction: tankFraction, accent: tokens.accent),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '$litersStr L of ${tank.toStringAsFixed(0)} L',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Tap to explain',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showExplainSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return _ExplainSheet(car: car, prediction: prediction);
      },
    );
  }
}

/// Thin horizontal gauge for the hero card. Renders a translucent track with
/// an amber-filled portion proportional to [fraction] (0–1).
class _TankGauge extends StatelessWidget {
  const _TankGauge({required this.fraction, required this.accent});
  final double fraction;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        FractionallySizedBox(
          widthFactor: fraction.clamp(0.04, 1.0),
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.55),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Body of the "explain this prediction" bottom sheet (spec §16-C).
///
/// The sheet renders three sections:
///   - The deterministic numeric breakdown (always visible).
///   - The async LLM explanation: spinner / fallback copy / live text.
///   - A small caption indicating provenance ("Powered by AI" vs.
///     "Pre-computed explanation") and a relative timestamp.
class _ExplainSheet extends ConsumerWidget {
  const _ExplainSheet({required this.car, required this.prediction});
  final Car car;
  final FuelPrediction prediction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final consumption = prediction.consumptionPer100km;
    final kmSince = prediction.kmSinceLastFull;
    final pace = car.avgKmPerDay;
    final explainAsync = ref.watch(predictExplainProvider(car.id));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How we got this number', style: theme.textTheme.titleLarge),
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
            _ExplainBox(
              theme: theme,
              child: explainAsync.when(
                loading: () => _ExplainLoading(theme: theme),
                error: (_, _) => _ExplainError(
                  theme: theme,
                  onRetry: () =>
                      ref.invalidate(predictExplainProvider(car.id)),
                ),
                data: (e) => _ExplainBody(theme: theme, payload: e),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tinted container wrapping the LLM explanation block. Pulled out so the
/// loading / error / data states share the same chrome.
class _ExplainBox extends StatelessWidget {
  const _ExplainBox({required this.theme, required this.child});
  final ThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

class _ExplainLoading extends StatelessWidget {
  const _ExplainLoading({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final fg = theme.colorScheme.onSecondaryContainer;
    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: fg),
        ),
        const SizedBox(width: 12),
        Text(
          'Asking the assistant…',
          style: theme.textTheme.bodySmall?.copyWith(color: fg),
        ),
      ],
    );
  }
}

class _ExplainError extends StatelessWidget {
  const _ExplainError({required this.theme, required this.onRetry});
  final ThemeData theme;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final fg = theme.colorScheme.onSecondaryContainer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome_outlined, size: 18, color: fg),
            const SizedBox(width: 8),
            // Fallback copy mirrors the original Phase 3 placeholder so the
            // sheet still tells a coherent story when the LLM endpoint is
            // unreachable.
            Expanded(
              child: Text(
                'These numbers come from your fuel entries.',
                style: theme.textTheme.bodySmall?.copyWith(color: fg),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: fg),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

class _ExplainBody extends StatelessWidget {
  const _ExplainBody({required this.theme, required this.payload});
  final ThemeData theme;
  final PredictExplain payload;

  @override
  Widget build(BuildContext context) {
    final fg = theme.colorScheme.onSecondaryContainer;
    final caption = payload.parsedBy == 'llm'
        ? 'Powered by AI'
        : 'Pre-computed explanation';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome_outlined, size: 18, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                payload.explanation.isEmpty
                    ? 'These numbers come from your fuel entries.'
                    : payload.explanation,
                style: theme.textTheme.bodySmall?.copyWith(color: fg),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '$caption · ${_relativeTime(payload.generatedAt)}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: fg.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

/// Compact relative-time formatter for the explainer's "generated at" line.
///
/// Keeps things human:
///   - <60s     → "just now"
///   - <60m     → "5 minutes ago"
///   - <24h     → "3 hours ago"
///   - otherwise → "2 days ago"
///
/// We do this inline rather than pulling in `timeago` because the dependency
/// list is already on the heavy side and this is the only call site.
String _relativeTime(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.isNegative) return 'just now';
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return m == 1 ? '1 minute ago' : '$m minutes ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return h == 1 ? '1 hour ago' : '$h hours ago';
  }
  final d = diff.inDays;
  return d == 1 ? '1 day ago' : '$d days ago';
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
            onTap: () => context.push('/cars/$carId/fuel/scan'),
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
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final enabled = onTap != null;
    final fg = enabled ? theme.colorScheme.onSurface : theme.colorScheme.outline;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: tokens.accent),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w500,
                ),
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
