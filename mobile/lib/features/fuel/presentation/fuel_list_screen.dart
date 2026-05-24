import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/tokens.dart';
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
          data: (list) {
            if (list.isEmpty) {
              return _EmptyState(
                onAdd: () => context.push('/cars/$carId/fuel/new'),
              );
            }
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () =>
                              context.push('/cars/$carId/fuel/stats'),
                          icon: const Icon(Icons.bar_chart),
                          label: const Text('Stats'),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  sliver: SliverList.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _FuelCard(
                      entry: list[i],
                      onTap: () => context.push(
                        '/cars/$carId/fuel/${list[i].id}/edit',
                        extra: list[i],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
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
  const _FuelCard({required this.entry, this.onTap});
  final FuelEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = DateFormat.yMMMd().format(entry.date);

    final tokens = context.tokens;
    final fuelColor = entry.isFullTank ? tokens.success : tokens.accent;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: fuelColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.local_gas_station, color: fuelColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            dateLabel,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${entry.liters.toStringAsFixed(entry.liters % 1 == 0 ? 0 : 1)} L',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: tokens.accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.station != null && entry.station!.isNotEmpty
                                ? entry.station!
                                : '${entry.fuelType.name} · ${NumberFormat.decimalPattern('en_US').format(entry.odometer)} km',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '\$${entry.totalCost.toStringAsFixed(2)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
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
