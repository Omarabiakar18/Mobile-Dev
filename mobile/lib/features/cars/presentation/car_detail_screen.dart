import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/base_url.dart';
import '../../../core/ui/connecting_state.dart';
import '../../../core/ui/feedback.dart';
import '../../documents/presentation/documents_list_screen.dart';
import '../../fuel/presentation/fuel_list_screen.dart';
import '../../maintenance/presentation/maintenance_list_screen.dart';
import '../../reminders/presentation/reminders_list_screen.dart';
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
              Tab(icon: Icon(Icons.dashboard_outlined, size: 18), text: 'Overview'),
              Tab(icon: Icon(Icons.local_gas_station, size: 18), text: 'Fuel'),
              Tab(icon: Icon(Icons.build_outlined, size: 18), text: 'Maintenance'),
              Tab(icon: Icon(Icons.description_outlined, size: 18), text: 'Documents'),
              Tab(icon: Icon(Icons.notifications_outlined, size: 18), text: 'Reminders'),
            ],
          ),
        ),
        body: carsAsync.when(
          loading: () => const ConnectingState(label: 'Loading car…'),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                e is ApiException ? e.message : 'Something went wrong.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (cars) {
            final car = cars.where((c) => c.id == carId).firstOrNull;
            if (car == null) {
              return const Center(child: Text('Car not found'));
            }
            return TabBarView(
              children: [
                _OverviewTab(car: car),
                FuelListScreen(carId: car.id),
                MaintenanceListScreen(carId: car.id),
                DocumentsListScreen(carId: car.id),
                RemindersListScreen(carId: car.id),
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
        _CarPhotoHeader(car: car),
        const SizedBox(height: 16),
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

/// Photo well at the top of the Overview tab. Shows the car's photo (or a
/// placeholder) and lets the user set/replace it via `POST /cars/:id/photo`.
/// Stateful so it can show an upload spinner; on success it invalidates
/// `carsListProvider` so the new `photoUrl` propagates everywhere (list card,
/// home switcher, this header).
class _CarPhotoHeader extends ConsumerStatefulWidget {
  const _CarPhotoHeader({required this.car});
  final Car car;

  @override
  ConsumerState<_CarPhotoHeader> createState() => _CarPhotoHeaderState();
}

class _CarPhotoHeaderState extends ConsumerState<_CarPhotoHeader> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      setState(() => _uploading = true);
      await ref.read(carsApiProvider).setPhoto(widget.car.id, File(picked.path));
      ref.invalidate(carsListProvider);
      if (mounted) showFeedback(context, 'Photo updated');
    } on ApiException catch (e) {
      if (mounted) showFeedback(context, e.message, isError: true);
    } catch (_) {
      if (mounted) {
        showFeedback(context, "Couldn't update photo. Please try again.",
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photoUrl = widget.car.photoUrl;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    // Direct null check (not `!hasPhoto`) so Dart promotes `photoUrl` to
    // non-null inside the else branch.
    final fullUrl = (photoUrl == null || photoUrl.isEmpty)
        ? null
        : (photoUrl.startsWith('http') ? photoUrl : '$apiBaseUrl$photoUrl');

    return GestureDetector(
      onTap: _uploading ? null : _pickAndUpload,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 180,
          width: double.infinity,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (fullUrl != null)
                CachedNetworkImage(
                  imageUrl: fullUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, _, _) => _placeholder(theme),
                )
              else
                _placeholder(theme),

              // "Change / Add photo" affordance.
              Positioned(
                right: 8,
                bottom: 8,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.photo_camera_outlined,
                            size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          hasPhoto ? 'Change' : 'Add photo',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              if (_uploading)
                Container(
                  color: Colors.black26,
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ThemeData theme) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_car_filled_outlined,
              size: 44, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('Tap to add a photo',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      );
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
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

