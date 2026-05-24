import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../data/maintenance_api.dart';
import '../data/maintenance_model.dart';

class MaintenanceListScreen extends ConsumerWidget {
  const MaintenanceListScreen({super.key, required this.carId});
  final String carId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(maintenanceListProvider(carId));

    return Scaffold(
      appBar: AppBar(title: const Text('Maintenance')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(maintenanceListProvider(carId)),
        child: entries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorState(
            message: e is ApiException ? e.message : e.toString(),
            onRetry: () => ref.invalidate(maintenanceListProvider(carId)),
          ),
          data: (list) => list.isEmpty
              ? _EmptyState(
                  onAdd: () => context.push('/cars/$carId/maintenance/new'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _MaintenanceCard(entry: list[i]),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add entry'),
        onPressed: () => context.push('/cars/$carId/maintenance/new'),
      ),
    );
  }
}

class _MaintenanceCard extends StatelessWidget {
  const _MaintenanceCard({required this.entry});
  final MaintenanceEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat.yMMMd();
    final costFmt = NumberFormat.simpleCurrency(decimalDigits: 2);

    final tokens = Theme.of(context).extension<GarageColors>()!;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tokens.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_iconFor(entry.type), color: tokens.accent),
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
                          entry.type.label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        costFmt.format(entry.cost),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: tokens.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${dateFmt.format(entry.date.toLocal())} · '
                    '${NumberFormat.decimalPattern('en_US').format(entry.km)} km',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  if (entry.description != null &&
                      entry.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.description!,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(MaintenanceType t) {
    switch (t) {
      case MaintenanceType.oil:
        return Icons.oil_barrel_outlined;
      case MaintenanceType.brakes:
        return Icons.album_outlined; // brake disc visual
      case MaintenanceType.tires:
        return Icons.tire_repair_outlined;
      case MaintenanceType.filter:
        return Icons.filter_alt_outlined;
      case MaintenanceType.battery:
        return Icons.battery_charging_full_outlined;
      case MaintenanceType.other:
        return Icons.build_outlined;
    }
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
          Icons.build_outlined,
          size: 80,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(
          'No maintenance yet',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Log oil changes, brakes, tires, and more to track your service history.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add entry'),
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
            Text("Couldn't load maintenance", style: theme.textTheme.titleLarge),
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
