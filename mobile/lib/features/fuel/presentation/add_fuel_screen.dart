import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../cars/data/car_model.dart';
import '../../cars/data/cars_api.dart';
import '../data/fuel_api.dart';

class AddFuelScreen extends ConsumerStatefulWidget {
  const AddFuelScreen({super.key, required this.carId});
  final String carId;

  @override
  ConsumerState<AddFuelScreen> createState() => _AddFuelScreenState();
}

class _AddFuelScreenState extends ConsumerState<AddFuelScreen> {
  final _formKey = GlobalKey<FormState>();
  final _odometer = TextEditingController();
  final _liters = TextEditingController();
  final _pricePerLiter = TextEditingController();
  final _totalCost = TextEditingController();
  final _station = TextEditingController();
  final _notes = TextEditingController();

  DateTime _date = DateTime.now();
  FuelType _fuelType = FuelType.gasoline;
  bool _isFullTank = false;
  bool _saving = false;
  bool _prefilled = false;
  // True while we're filling totalCost from liters * pricePerLiter so the
  // listener doesn't bounce back and re-trigger itself.
  bool _autoFillingTotal = false;

  @override
  void initState() {
    super.initState();
    _liters.addListener(_recomputeTotal);
    _pricePerLiter.addListener(_recomputeTotal);
  }

  @override
  void dispose() {
    _liters.removeListener(_recomputeTotal);
    _pricePerLiter.removeListener(_recomputeTotal);
    _odometer.dispose();
    _liters.dispose();
    _pricePerLiter.dispose();
    _totalCost.dispose();
    _station.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _prefillFromCar(Car car) {
    if (_prefilled) return;
    _prefilled = true;
    _odometer.text = car.currentKm.toString();
    _fuelType = car.fuelType;
  }

  void _recomputeTotal() {
    final l = double.tryParse(_liters.text.trim());
    final p = double.tryParse(_pricePerLiter.text.trim());
    if (l == null || p == null) return;
    _autoFillingTotal = true;
    _totalCost.text = (l * p).toStringAsFixed(2);
    _autoFillingTotal = false;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(fuelApiProvider).create(
            widget.carId,
            date: _date,
            odometer: int.parse(_odometer.text.trim()),
            liters: double.parse(_liters.text.trim()),
            pricePerLiter: double.parse(_pricePerLiter.text.trim()),
            totalCost: double.parse(_totalCost.text.trim()),
            fuelType: _fuelType,
            station: _station.text.trim().isEmpty ? null : _station.text.trim(),
            isFullTank: _isFullTank,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      ref.invalidate(fuelListProvider(widget.carId));
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Prefill the form from the cached cars list when it arrives.
    ref.listen(carsListProvider, (_, next) {
      next.whenData((cars) {
        final car = cars.where((c) => c.id == widget.carId).firstOrNull;
        if (car != null && mounted) setState(() => _prefillFromCar(car));
      });
    });
    final carsAsync = ref.read(carsListProvider);
    carsAsync.whenData((cars) {
      final car = cars.where((c) => c.id == widget.carId).firstOrNull;
      if (car != null) _prefillFromCar(car);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Log fuel')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DatePickerField(date: _date, onTap: _pickDate),
                _Field(
                  controller: _odometer,
                  label: 'Odometer (km)',
                  keyboardType: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) =>
                      int.tryParse(v ?? '') == null ? 'Required' : null,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        controller: _liters,
                        label: 'Liters',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        formatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        validator: _positive,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        controller: _pricePerLiter,
                        label: 'Price / L',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        formatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        validator: _positive,
                      ),
                    ),
                  ],
                ),
                _Field(
                  controller: _totalCost,
                  label: 'Total cost',
                  hint: 'auto-filled — tap to override',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  formatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  validator: _positive,
                  onChanged: (_) {
                    // User edited it directly — stop auto-filling.
                    if (!_autoFillingTotal) {
                      _liters.removeListener(_recomputeTotal);
                      _pricePerLiter.removeListener(_recomputeTotal);
                    }
                  },
                ),
                const SizedBox(height: 8),
                SegmentedButton<FuelType>(
                  segments: const [
                    ButtonSegment(
                      value: FuelType.gasoline,
                      label: Text('Gasoline'),
                    ),
                    ButtonSegment(
                      value: FuelType.diesel,
                      label: Text('Diesel'),
                    ),
                  ],
                  selected: {_fuelType},
                  onSelectionChanged: (s) =>
                      setState(() => _fuelType = s.first),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isFullTank,
                  onChanged: (v) =>
                      setState(() => _isFullTank = v ?? false),
                  title: const Text('Full tank'),
                  subtitle: const Text(
                    'Marks this as a full fill-up (used for consumption math)',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                _Field(
                  controller: _station,
                  label: 'Station (optional)',
                  hint: 'e.g. Total Jounieh',
                ),
                _Field(
                  controller: _notes,
                  label: 'Notes (optional)',
                  maxLines: 3,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save fill-up'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String? _positive(String? v) {
    final n = double.tryParse(v ?? '');
    if (n == null) return 'Required';
    if (n <= 0) return 'Must be > 0';
    return null;
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({required this.date, required this.onTap});
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Date',
            suffixIcon: Icon(Icons.calendar_today),
          ),
          child: Text(DateFormat.yMMMd().format(date)),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.validator,
    this.formatters,
    this.maxLines = 1,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? formatters;
  final int maxLines;
  final ValueChanged<String>? onChanged;

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
        maxLines: maxLines,
        onChanged: onChanged,
      ),
    );
  }
}
