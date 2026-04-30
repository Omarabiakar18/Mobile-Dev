import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cars_api.dart';
import '../data/car_model.dart';

class CarDetailScreen extends ConsumerWidget {
  const CarDetailScreen({super.key, required this.carId});
  final String carId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carsAsync = ref.watch(carsListProvider);

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: carsAsync.maybeWhen(
            data: (cars) {
              final car = cars.where((c) => c.id == carId).firstOrNull;
              return Text(car?.displayName ?? 'Car');
            },
            orElse: () => const Text('Car'),
          ),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Fuel'),
              Tab(text: 'Maintenance'),
              Tab(text: 'Documents'),
              Tab(text: 'Reminders'),
            ],
          ),
        ),
        body: carsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (cars) {
            final car = cars.where((c) => c.id == carId).firstOrNull;
            if (car == null) {
              return const Center(child: Text('Car not found'));
            }
            return TabBarView(
              children: [
                _OverviewTab(car: car),
                const _ComingSoonTab('Fuel log lands in Phase 2'),
                const _ComingSoonTab('Maintenance log lands in Phase 2'),
                const _ComingSoonTab('Documents land in Phase 2'),
                const _ComingSoonTab('Service reminders land in Phase 3'),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.car});
  final Car car;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(car.displayName, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                _InfoRow(label: 'Plate', value: car.plate),
                if (car.color != null) _InfoRow(label: 'Color', value: car.color!),
                _InfoRow(label: 'Fuel', value: car.fuelType.name),
                _InfoRow(label: 'Tank size', value: '${car.tankSize.toStringAsFixed(0)} L'),
                _InfoRow(label: 'Current km', value: car.currentKm.toString()),
                if (car.avgKmPerDay != null)
                  _InfoRow(
                    label: 'Avg km/day',
                    value: car.avgKmPerDay!.toStringAsFixed(1),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _ComingSoonTab extends StatelessWidget {
  const _ComingSoonTab(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
