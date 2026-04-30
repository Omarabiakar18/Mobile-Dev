import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../data/fuel_api.dart';
import '../data/fuel_model.dart';

class FuelListScreen extends ConsumerWidget {
  const FuelListScreen({super.key, required this.carId});
  final String carId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(fuelListProvider(carId));

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(fuelListProvider(carId)),
        child: entries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorState(
            message: e is ApiException ? e.message : e.toString(),
            onRetry: () => ref.invalidate(fuelListProvider(carId)),
          ),
          data: (list) => list.isEmpty
              ? _EmptyState(
                  onAdd: () => context.push('/cars/$carId/fuel/new'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _FuelCard(entry: list[i]),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.local_gas_station),
        label: const Text('Log fuel'),
        onPressed: () => context.push('/cars/$carId/fuel/new'),
      ),
    );
  }
}

class _FuelCard extends StatelessWidget {
  const _FuelCard({required this.entry});
  final FuelEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = DateFormat.yMMMd().format(entry.date);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Icon(
                entry.isFullTank
                    ? Icons.local_gas_station
                    : Icons.local_gas_station_outlined,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dateLabel, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    entry.displaySummary(),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (entry.station != null && entry.station!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.station!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (entry.isFullTank)
              Tooltip(
                message: 'Full tank',
                child: Icon(
                  Icons.battery_full,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
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
          'Log your fuel stops to track spend, mileage, and consumption.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Log first fill-up'),
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
            Text("Couldn't load fuel log", style: theme.textTheme.titleLarge),
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
