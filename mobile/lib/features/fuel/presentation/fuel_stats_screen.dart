import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/ui/connecting_state.dart';
import '../data/fuel_api.dart';
import '../data/fuel_model.dart';

/// Numeric fuel summary screen — totals, average consumption, last-30/90.
/// Pull-to-refresh re-runs `fuelStatsProvider(carId)`.
class FuelStatsScreen extends ConsumerWidget {
  const FuelStatsScreen({super.key, required this.carId});
  final String carId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(fuelStatsProvider(carId));

    return Scaffold(
      appBar: AppBar(title: const Text('Fuel stats')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(fuelStatsProvider(carId)),
        child: stats.when(
          loading: () => const ConnectingState(label: 'Crunching the numbers…'),
          error: (e, _) => _ErrorState(
            message: e is ApiException ? e.message : e.toString(),
            onRetry: () => ref.invalidate(fuelStatsProvider(carId)),
          ),
          data: (s) => _StatsBody(stats: s),
        ),
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.stats});
  final FuelStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat.currency(
      locale: 'en_US',
      symbol: '\$',
      decimalDigits: 2,
    );
    final number = NumberFormat.decimalPattern('en_US');

    if (stats.fillCount == 0) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
        children: [
          Icon(
            Icons.local_gas_station_outlined,
            size: 80,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No fill-ups yet',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Log a fill-up to start seeing fuel stats.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    final litersFmt = stats.totalLiters.toStringAsFixed(
      stats.totalLiters % 1 == 0 ? 0 : 1,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Big numbers row
        Row(
          children: [
            Expanded(
              child: _BigNumberCard(
                label: 'Total spent',
                value: money.format(stats.totalCost),
                icon: Icons.attach_money,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BigNumberCard(
                label: 'Total fuel',
                value: '$litersFmt L',
                icon: Icons.local_gas_station,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BigNumberCard(
                label: 'Fill-ups',
                value: number.format(stats.fillCount),
                icon: Icons.format_list_numbered,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Average consumption
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.speed,
                  size: 36,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Average consumption',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      if (stats.avgConsumptionPer100km != null) ...[
                        Text(
                          '${stats.avgConsumptionPer100km!.toStringAsFixed(1)} L/100km',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'based on ${stats.fillCount} '
                          '${stats.fillCount == 1 ? 'fill-up' : 'fill-ups'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ] else
                        Text(
                          'Add 2+ full-tank entries to compute.',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Window cards
        _WindowCard(
          title: 'Last 30 days',
          window: stats.last30,
        ),
        const SizedBox(height: 12),
        _WindowCard(
          title: 'Last 90 days',
          window: stats.last90,
        ),
      ],
    );
  }
}

class _BigNumberCard extends StatelessWidget {
  const _BigNumberCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowCard extends StatelessWidget {
  const _WindowCard({required this.title, required this.window});

  final String title;
  final FuelWindowStats window;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat.currency(
      locale: 'en_US',
      symbol: '\$',
      decimalDigits: 2,
    );
    final litersFmt =
        window.liters.toStringAsFixed(window.liters % 1 == 0 ? 0 : 1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniMetric(
                    label: 'Spent',
                    value: money.format(window.cost),
                  ),
                ),
                Expanded(
                  child: _MiniMetric(
                    label: 'Fuel',
                    value: '$litersFmt L',
                  ),
                ),
                Expanded(
                  child: _MiniMetric(
                    label: window.fillCount == 1 ? 'Fill-up' : 'Fill-ups',
                    value: window.fillCount.toString(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 64),
        Icon(
          Icons.error_outline,
          size: 64,
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          "Couldn't load fuel stats",
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          message,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ),
      ],
    );
  }
}
