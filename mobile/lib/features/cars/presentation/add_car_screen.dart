import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/ui/feedback.dart';
import '../data/car_model.dart';
import '../data/cars_api.dart';

class AddCarScreen extends ConsumerStatefulWidget {
  const AddCarScreen({super.key});

  @override
  ConsumerState<AddCarScreen> createState() => _AddCarScreenState();
}

class _AddCarScreenState extends ConsumerState<AddCarScreen> {
  final _formKey = GlobalKey<FormState>();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController(text: '${DateTime.now().year}');
  final _plate = TextEditingController();
  final _color = TextEditingController();
  final _currentKm = TextEditingController(text: '0');
  final _tankSize = TextEditingController(text: '50');
  FuelType _fuelType = FuelType.gasoline;

  /// Optional car photo picked locally. Uploaded after the car row is created
  /// (we need its id), mirroring the maintenance-photo flow.
  File? _pendingPhoto;

  bool _saving = false;

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _year.dispose();
    _plate.dispose();
    _color.dispose();
    _currentKm.dispose();
    _tankSize.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() => _pendingPhoto = File(picked.path));
      }
    } catch (e) {
      if (mounted) showFeedback(context, "Couldn't pick image: $e", isError: true);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final api = ref.read(carsApiProvider);
      final car = await api.create(
        make: _make.text.trim(),
        model: _model.text.trim(),
        year: int.parse(_year.text.trim()),
        plate: _plate.text.trim(),
        color: _color.text.trim().isEmpty ? null : _color.text.trim(),
        currentKm: int.parse(_currentKm.text.trim()),
        fuelType: _fuelType,
        tankSize: double.parse(_tankSize.text.trim()),
      );

      // Upload the photo as a second step if one was picked. The car is
      // already saved, so a photo failure shouldn't lose the user's work —
      // surface it but still treat the car as added.
      var photoFailed = false;
      if (_pendingPhoto != null) {
        try {
          await api.setPhoto(car.id, _pendingPhoto!);
        } catch (_) {
          photoFailed = true;
        }
      }

      ref.invalidate(carsListProvider);
      if (mounted) {
        showFeedback(
          context,
          photoFailed ? 'Car added — photo upload failed' : 'Car added',
          isError: photoFailed,
        );
        context.pop();
      }
    } on ApiException catch (e) {
      if (mounted) showFeedback(context, e.message, isError: true);
    } catch (_) {
      if (mounted) {
        showFeedback(context, 'Something went wrong. Please try again.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add car')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PhotoPicker(
                  photo: _pendingPhoto,
                  onTap: _saving ? null : _pickPhoto,
                  onRemove: _pendingPhoto == null
                      ? null
                      : () => setState(() => _pendingPhoto = null),
                ),
                const SizedBox(height: 16),
                _Field(
                  controller: _make,
                  label: 'Make',
                  hint: 'e.g. Range Rover',
                  validator: _required,
                ),
                _Field(
                  controller: _model,
                  label: 'Model',
                  hint: 'e.g. Sport',
                  validator: _required,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        controller: _year,
                        label: 'Year',
                        keyboardType: TextInputType.number,
                        formatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (n == null) return 'Required';
                          if (n < 1900 || n > DateTime.now().year + 1) return 'Invalid';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        controller: _plate,
                        label: 'Plate',
                        validator: _required,
                      ),
                    ),
                  ],
                ),
                _Field(
                  controller: _color,
                  label: 'Color (optional)',
                ),
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        controller: _currentKm,
                        label: 'Current km',
                        keyboardType: TextInputType.number,
                        formatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) =>
                            int.tryParse(v ?? '') == null ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        controller: _tankSize,
                        label: 'Tank size (L)',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        formatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        validator: (v) =>
                            double.tryParse(v ?? '') == null ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SegmentedButton<FuelType>(
                  segments: const [
                    ButtonSegment(value: FuelType.gasoline, label: Text('Gasoline')),
                    ButtonSegment(value: FuelType.diesel, label: Text('Diesel')),
                  ],
                  selected: {_fuelType},
                  onSelectionChanged: (s) => setState(() => _fuelType = s.first),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save car'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.validator,
    this.formatters,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? formatters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: formatters,
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: validator,
      ),
    );
  }
}

/// Tappable car-photo well shown at the top of the add-car form. Renders the
/// picked local file or an "Add photo" placeholder. Optional — a car can be
/// saved without one.
class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.photo,
    required this.onTap,
    required this.onRemove,
  });

  final File? photo;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 160,
          color: theme.colorScheme.surfaceContainerHighest,
          child: photo == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined,
                        size: 36, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 8),
                    Text('Add a photo (optional)',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(photo!, fit: BoxFit.cover),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: IconButton(
                          iconSize: 18,
                          icon: const Icon(Icons.close, color: Colors.white),
                          tooltip: 'Remove photo',
                          onPressed: onRemove,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
