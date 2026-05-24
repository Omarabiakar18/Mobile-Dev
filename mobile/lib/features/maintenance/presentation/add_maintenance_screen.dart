import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/ui/feedback.dart';
import '../../reminders/data/reminders_api.dart';
import '../data/maintenance_api.dart';
import '../data/maintenance_model.dart';

class AddMaintenanceScreen extends ConsumerStatefulWidget {
  const AddMaintenanceScreen({super.key, required this.carId});
  final String carId;

  @override
  ConsumerState<AddMaintenanceScreen> createState() =>
      _AddMaintenanceScreenState();
}

class _AddMaintenanceScreenState extends ConsumerState<AddMaintenanceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _km = TextEditingController();
  final _cost = TextEditingController();
  final _description = TextEditingController();
  final _notes = TextEditingController();

  DateTime _date = DateTime.now();
  MaintenanceType _type = MaintenanceType.oil;

  /// Photos picked locally before save. We can only upload them after the
  /// maintenance entry is created (we need its id), so we hold them here.
  final List<File> _pendingPhotos = [];

  bool _saving = false;

  @override
  void dispose() {
    _km.dispose();
    _cost.dispose();
    _description.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickPhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() => _pendingPhotos.add(File(picked.path)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Couldn't pick image: $e"),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final api = ref.read(maintenanceApiProvider);
      final result = await api.create(
        carId: widget.carId,
        date: _date,
        km: int.parse(_km.text.trim()),
        type: _type,
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        cost: double.parse(_cost.text.trim()),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );

      // Upload any pending photos serially. If one fails the entry is still
      // saved — surface the error but keep the rest going.
      for (final f in _pendingPhotos) {
        try {
          await api.addPhoto(result.entry.id, f);
        } on ApiException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Photo upload failed: ${e.message}'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }

      ref.invalidate(maintenanceListProvider(widget.carId));

      // Cross-update side effect (Alaa's #3): when the backend bumped one or
      // more reminders, invalidate the reminders list provider so the home
      // banner + reminders tab reflect the new lastDone* immediately, and
      // enrich the success toast with the count so the user sees the
      // connection between the two features.
      final bumped = result.updatedReminderIds.length;
      if (bumped > 0) {
        ref.invalidate(remindersListProvider(widget.carId));
      }

      if (mounted) {
        final msg = bumped == 0
            ? 'Maintenance entry saved'
            : bumped == 1
                ? 'Maintenance saved · 1 reminder updated'
                : 'Maintenance saved · $bumped reminders updated';
        showFeedback(context, msg);
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
    final theme = Theme.of(context);
    final dateFmt = DateFormat.yMMMd();

    return Scaffold(
      appBar: AppBar(title: const Text('Add maintenance')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Date
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(dateFmt.format(_date)),
                  ),
                ),
                const SizedBox(height: 12),

                // Type — DropdownMenu (6 options is too many for SegmentedButton)
                DropdownMenu<MaintenanceType>(
                  initialSelection: _type,
                  expandedInsets: EdgeInsets.zero,
                  label: const Text('Type'),
                  onSelected: (v) {
                    if (v != null) setState(() => _type = v);
                  },
                  dropdownMenuEntries: MaintenanceType.values
                      .map((t) =>
                          DropdownMenuEntry(value: t, label: t.label))
                      .toList(),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        controller: _km,
                        label: 'Odometer (km)',
                        keyboardType: TextInputType.number,
                        formatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) => int.tryParse(v ?? '') == null
                            ? 'Required'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        controller: _cost,
                        label: 'Cost',
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        formatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          if (n == null) return 'Required';
                          if (n <= 0) return '> 0';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),

                _Field(
                  controller: _description,
                  label: 'Description (optional)',
                  hint: 'e.g. Synthetic 5W-30, full pads + rotors',
                ),
                _Field(
                  controller: _notes,
                  label: 'Notes (optional)',
                  maxLines: 3,
                ),

                const SizedBox(height: 16),

                // Photos
                Text('Photos', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                if (_pendingPhotos.isNotEmpty)
                  SizedBox(
                    height: 80,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _pendingPhotos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final f = _pendingPhotos[i];
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                f,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: -4,
                              right: -4,
                              child: IconButton(
                                iconSize: 18,
                                icon: const Icon(Icons.cancel),
                                color: theme.colorScheme.error,
                                onPressed: () => setState(
                                    () => _pendingPhotos.removeAt(i)),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickPhoto,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add photo'),
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
                      : const Text('Save'),
                ),
              ],
            ),
          ),
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
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? formatters;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: formatters,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: validator,
      ),
    );
  }
}
