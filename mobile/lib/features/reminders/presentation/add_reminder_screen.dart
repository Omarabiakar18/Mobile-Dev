import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/feedback.dart';
import '../../../core/notifications/scheduling_sync.dart';
import '../../cars/data/cars_api.dart';
import '../data/reminders_api.dart';

class AddReminderScreen extends ConsumerStatefulWidget {
  const AddReminderScreen({super.key, required this.carId});
  final String carId;

  @override
  ConsumerState<AddReminderScreen> createState() => _AddReminderScreenState();
}

class _AddReminderScreenState extends ConsumerState<AddReminderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serviceType = TextEditingController();
  final _lastDoneKm = TextEditingController();
  final _intervalKm = TextEditingController();
  final _intervalMonths = TextEditingController();

  DateTime _lastDoneDate = _stripTime(DateTime.now());
  bool _isActive = true;
  bool _saving = false;
  bool _prefillApplied = false;

  static DateTime _stripTime(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _lastDoneKm.text = '0';
  }

  @override
  void dispose() {
    _serviceType.dispose();
    _lastDoneKm.dispose();
    _intervalKm.dispose();
    _intervalMonths.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _lastDoneDate,
      firstDate: DateTime(now.year - 30),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _lastDoneDate = _stripTime(picked));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final intervalKmText = _intervalKm.text.trim();
    final intervalMonthsText = _intervalMonths.text.trim();
    if (intervalKmText.isEmpty && intervalMonthsText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set at least one of km or months interval'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(remindersApiProvider).create(
            carId: widget.carId,
            serviceType: _serviceType.text.trim(),
            lastDoneKm: int.parse(_lastDoneKm.text.trim()),
            lastDoneDate: _lastDoneDate,
            intervalKm: intervalKmText.isEmpty ? null : int.parse(intervalKmText),
            intervalMonths: intervalMonthsText.isEmpty
                ? null
                : int.parse(intervalMonthsText),
            isActive: _isActive,
          );
      ref.invalidate(remindersListProvider(widget.carId));
      ref.invalidate(dueRemindersProvider(widget.carId));
      // Phase 5 — newly-created reminder needs its 30d / 7d notifications
      // scheduled. Fire-and-forget; SchedulingSync swallows network errors.
      unawaited(
        ref.read(schedulingSyncProvider).syncForCar(widget.carId),
      );
      if (mounted) {
        showFeedback(context, 'Reminder saved');
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
    // Prefill `lastDoneKm` once with the car's current km when the cars list
    // resolves. We watch instead of read so we get the value when it's loaded.
    final carsAsync = ref.watch(carsListProvider);
    if (!_prefillApplied) {
      carsAsync.whenData((cars) {
        final car = cars.where((c) => c.id == widget.carId).firstOrNull;
        if (car != null) {
          _lastDoneKm.text = car.currentKm.toString();
          _prefillApplied = true;
        }
      });
    }

    // Current km from the loaded car — used by the km-vs-calendar conflict
    // banner below. When the cars list hasn't resolved yet, currentKm is
    // null and the banner stays silent.
    final currentKm = carsAsync.maybeWhen(
      data: (cars) =>
          cars.where((c) => c.id == widget.carId).firstOrNull?.currentKm,
      orElse: () => null,
    );

    final dateFmt = DateFormat.yMMMd();

    return Scaffold(
      appBar: AppBar(title: const Text('Add reminder')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Field(
                  controller: _serviceType,
                  label: 'Service type',
                  hint: 'e.g. Oil change, Brake fluid, Air filter',
                  validator: _required,
                ),
                _Field(
                  controller: _lastDoneKm,
                  label: 'Last done at (km)',
                  keyboardType: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null) return 'Required';
                    if (n < 0) return 'Must be ≥ 0';
                    return null;
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Last done on',
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(dateFmt.format(_lastDoneDate))),
                          const Icon(Icons.calendar_today, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        controller: _intervalKm,
                        label: 'Interval (km)',
                        hint: 'optional',
                        keyboardType: TextInputType.number,
                        formatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = int.tryParse(v);
                          if (n == null || n <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        controller: _intervalMonths,
                        label: 'Interval (months)',
                        hint: 'optional',
                        keyboardType: TextInputType.number,
                        formatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = int.tryParse(v);
                          if (n == null || n <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Set at least one — km, months, or both.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                // Live km-vs-calendar conflict banner. Re-evaluates whenever
                // the user edits any of the three relevant fields. HANDOFF
                // 2026-05-24: when both intervals are set AND currentKm is
                // already past lastDoneKm + intervalKm, the projection
                // takes min(kmLeg, calLeg) → kmLeg ≤ 0 → projects to today,
                // silently masking the calendar leg. Warn the user before
                // they save instead of surfacing the surprise later on the
                // home banner.
                ListenableBuilder(
                  listenable: Listenable.merge(
                    [_intervalKm, _intervalMonths, _lastDoneKm],
                  ),
                  builder: (ctx, _) {
                    final warning = _kmConflictMessage(currentKm);
                    if (warning == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _ConflictBanner(message: warning),
                    );
                  },
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text(
                    "When off, this reminder won't surface on the home dashboard.",
                  ),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save reminder'),
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

  /// Returns a user-facing warning string if both intervals are set AND
  /// the car's current km is already at/past the km threshold, otherwise
  /// null. The projection logic on the backend takes min(kmLeg, calLeg);
  /// when kmLeg projects to today, the calendar leg is silently dropped.
  /// Surface this before save so the user can adjust expectations.
  String? _kmConflictMessage(int? currentKm) {
    if (currentKm == null) return null;
    final intervalKm = int.tryParse(_intervalKm.text.trim());
    final intervalMonths = int.tryParse(_intervalMonths.text.trim());
    final lastDoneKm = int.tryParse(_lastDoneKm.text.trim());
    if (intervalKm == null ||
        intervalMonths == null ||
        lastDoneKm == null) {
      return null;
    }
    final threshold = lastDoneKm + intervalKm;
    if (currentKm < threshold) return null;
    return "You're already past the km threshold — current $currentKm km, "
        'threshold $threshold km. The projection will use today from the km '
        'side and ignore the $intervalMonths-month calendar interval.';
  }
}

/// Token-colored warning banner used by the km-vs-calendar conflict notice.
/// Same visual shape as [StatusChip.dueSoon] so the form's amber surface
/// reads consistently with the rest of the app's reminder UI.
class _ConflictBanner extends StatelessWidget {
  const _ConflictBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.warningContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: tokens.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
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
