import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/base_url.dart';
import '../../cars/data/car_model.dart';
import '../../cars/data/cars_api.dart';
import '../data/fuel_api.dart';
import '../data/ocr_prefill_model.dart';

/// Confidence threshold under which we tint a field's border orange and
/// show the "verify these" banner. The OCR pipeline tends to be highly
/// confident (≥0.9) on clean numeric fields, so 0.7 is a safe "not sure" cut.
const double _kLowConfidenceThreshold = 0.7;

class AddFuelScreen extends ConsumerStatefulWidget {
  const AddFuelScreen({super.key, required this.carId, this.ocrPrefill});

  final String carId;

  /// Optional OCR-extracted fields. When non-null, the form initializes its
  /// controllers from this payload and visually flags low-confidence values
  /// in orange. The user must still tap Save — OCR never auto-saves.
  final OcrPrefill? ocrPrefill;

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
    _applyOcrPrefill();
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

  /// Seed the controllers from an OCR payload (if any was passed in via
  /// go_router). Numeric fields use a tight `toStringAsFixed` so the form
  /// doesn't render `45.0000000001` from a JSON-decoded double.
  void _applyOcrPrefill() {
    final p = widget.ocrPrefill;
    if (p == null) return;
    if (p.liters != null) _liters.text = _formatNum(p.liters!);
    if (p.pricePerLiter != null) {
      _pricePerLiter.text = _formatNum(p.pricePerLiter!);
    }
    if (p.totalCost != null) _totalCost.text = _formatNum(p.totalCost!);
    if (p.station != null) _station.text = p.station!;
    if (p.date != null) _date = p.date!;
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
            // Persist the receipt photo URL the OCR endpoint surfaced. The
            // backend served it from /uploads/ocr/<hash>.jpg; saving it here
            // means the fuel entry keeps a permanent link to the receipt.
            receiptPhotoUrl: widget.ocrPrefill?.receiptPhotoUrl,
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

    final theme = Theme.of(context);
    final ocr = widget.ocrPrefill;
    final hasLowConfidence = ocr != null &&
        const ['liters', 'pricePerLiter', 'totalCost', 'station', 'date']
            .any((f) => ocr.confidenceFor(f) > 0 &&
                ocr.confidenceFor(f) < _kLowConfidenceThreshold);

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
                if (ocr?.receiptPhotoUrl != null)
                  _ReceiptThumbnail(relativeUrl: ocr!.receiptPhotoUrl!),
                if (hasLowConfidence) _LowConfidenceBanner(theme: theme),
                _DatePickerField(
                  date: _date,
                  onTap: _pickDate,
                  confidence: ocr?.confidenceFor('date'),
                ),
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
                        confidence: ocr?.confidenceFor('liters'),
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
                        confidence: ocr?.confidenceFor('pricePerLiter'),
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
                  confidence: ocr?.confidenceFor('totalCost'),
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
                  confidence: ocr?.confidenceFor('station'),
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

  /// Human-friendly numeric formatting for OCR prefill: drops trailing zeros
  /// so `45.0` renders as `45` and `45.20` as `45.2`.
  static String _formatNum(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    final s = v.toStringAsFixed(2);
    return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
  }
}

/// Returns an `InputDecoration` whose border is tinted orange when the
/// supplied confidence is below [_kLowConfidenceThreshold]. Returns the
/// theme's default decoration when [confidence] is null (no OCR) or high.
InputDecoration _confidenceBorder(
  ThemeData theme,
  double? confidence, {
  required String label,
  String? hint,
  Widget? suffixIcon,
}) {
  final base = InputDecoration(
    labelText: label,
    hintText: hint,
    suffixIcon: suffixIcon,
  );
  if (confidence == null || confidence >= _kLowConfidenceThreshold) {
    return base;
  }
  // Orange holds up well in both light and dark schemes — and survives the
  // form being read at arm's length on a phone in daylight.
  const orange = Color(0xFFE08017);
  return base.copyWith(
    enabledBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: orange, width: 1.4),
    ),
    focusedBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: orange, width: 2),
    ),
    border: const OutlineInputBorder(
      borderSide: BorderSide(color: orange),
    ),
    suffixIcon: suffixIcon ??
        const Tooltip(
          message: 'Low OCR confidence — please verify',
          child: Icon(Icons.warning_amber_rounded, color: orange),
        ),
    helperText: 'Verify',
    helperStyle: const TextStyle(color: orange, fontSize: 11),
  );
}

class _LowConfidenceBanner extends StatelessWidget {
  const _LowConfidenceBanner({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFE08017);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: orange.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: orange.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: orange, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Fields highlighted in orange were uncertain — please verify.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.date,
    required this.onTap,
    this.confidence,
  });
  final DateTime date;
  final VoidCallback onTap;
  final double? confidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: _confidenceBorder(
            theme,
            confidence,
            label: 'Date',
            suffixIcon: const Icon(Icons.calendar_today),
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
    this.confidence,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? formatters;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  /// `null` when the form isn't OCR-prefilled; `0..1` otherwise. Below the
  /// threshold the field renders an orange border + warning icon.
  final double? confidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: formatters,
        decoration: _confidenceBorder(
          theme,
          confidence,
          label: label,
          hint: hint,
        ),
        validator: validator,
        maxLines: maxLines,
        onChanged: onChanged,
      ),
    );
  }
}

/// Small preview of the OCR'd receipt rendered at the top of the form.
/// Caps the height at 160px and uses a rounded clip so it sits well above the
/// existing fields. The URL is the relative path emitted by the OCR endpoint
/// (e.g. `/uploads/ocr/<hash>.jpg`); we prefix with [apiBaseUrl] here so the
/// raw payload from the backend doesn't need to know about the deployment
/// host.
class _ReceiptThumbnail extends StatelessWidget {
  const _ReceiptThumbnail({required this.relativeUrl});

  final String relativeUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fullUrl = relativeUrl.startsWith('http')
        ? relativeUrl
        : '$apiBaseUrl$relativeUrl';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: CachedNetworkImage(
            imageUrl: fullUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            placeholder: (_, _) => Container(
              height: 160,
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorWidget: (_, _, _) => Container(
              height: 80,
              color: theme.colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_not_supported_outlined,
                      color: theme.colorScheme.outline),
                  const SizedBox(width: 8),
                  Text('Receipt preview unavailable',
                      style: TextStyle(color: theme.colorScheme.outline)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
