import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(carsApiProvider).create(
            make: _make.text.trim(),
            model: _model.text.trim(),
            year: int.parse(_year.text.trim()),
            plate: _plate.text.trim(),
            color: _color.text.trim().isEmpty ? null : _color.text.trim(),
            currentKm: int.parse(_currentKm.text.trim()),
            fuelType: _fuelType,
            tankSize: double.parse(_tankSize.text.trim()),
          );
      ref.invalidate(carsListProvider);
      if (mounted) {
        showFeedback(context, 'Car added');
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
