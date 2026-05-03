import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/notifications/scheduling_sync.dart';
import '../data/document_model.dart';
import '../data/documents_api.dart';

class AddDocumentScreen extends ConsumerStatefulWidget {
  const AddDocumentScreen({super.key, required this.carId});
  final String carId;

  @override
  ConsumerState<AddDocumentScreen> createState() => _AddDocumentScreenState();
}

class _AddDocumentScreenState extends ConsumerState<AddDocumentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _issuer = TextEditingController();
  final _notes = TextEditingController();

  DocumentType _type = DocumentType.insurance;
  DateTime? _expiryDate;
  DateTime? _issuedDate;
  PlatformFile? _picked;

  bool _saving = false;

  @override
  void dispose() {
    _issuer.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'heic'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _picked = result.files.first);
    }
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? DateTime(now.year + 1, now.month, now.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _pickIssued() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _issuedDate ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null) setState(() => _issuedDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_picked?.path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pick a file (PDF or image)'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_expiryDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expiry date is required'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(documentsApiProvider).create(
            carId: widget.carId,
            type: _type,
            expiryDate: _expiryDate!,
            issuedDate: _issuedDate,
            issuer: _issuer.text.trim().isEmpty ? null : _issuer.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            filePath: _picked!.path!,
            fileName: _picked!.name,
          );
      ref.invalidate(documentsListProvider(widget.carId));
      ref.invalidate(expiringDocumentsProvider(widget.carId));
      // Phase 5 — newly-created document needs its 30d / 7d expiry alerts
      // scheduled. Fire-and-forget; SchedulingSync swallows network errors.
      unawaited(
        ref.read(schedulingSyncProvider).syncForCar(widget.carId),
      );
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Add document')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ----- File picker ---------------------------------------
                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _pickFile,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            _picked == null ? Icons.upload_file : Icons.insert_drive_file,
                            size: 32,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _picked == null ? 'Pick a file' : _picked!.name,
                                  style: theme.textTheme.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _picked == null
                                      ? 'PDF or image, up to 5 MB'
                                      : _formatBytes(_picked!.size),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (_picked != null)
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() => _picked = null),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ----- Type ---------------------------------------------
                DropdownButtonFormField<DocumentType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: DocumentType.values
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Row(
                            children: [
                              Icon(t.icon, size: 18),
                              const SizedBox(width: 8),
                              Text(t.label),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _type = v ?? DocumentType.other),
                ),
                const SizedBox(height: 12),

                // ----- Expiry date --------------------------------------
                _DateField(
                  label: 'Expiry date *',
                  value: _expiryDate,
                  onTap: _pickExpiry,
                ),
                const SizedBox(height: 12),

                // ----- Issued date --------------------------------------
                _DateField(
                  label: 'Issued date (optional)',
                  value: _issuedDate,
                  onTap: _pickIssued,
                  onClear: _issuedDate == null
                      ? null
                      : () => setState(() => _issuedDate = null),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _issuer,
                  decoration: const InputDecoration(
                    labelText: 'Issuer (optional)',
                    hintText: 'e.g. Allianz, AAA',
                  ),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  minLines: 2,
                  maxLines: 4,
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
                      : const Text('Save document'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value != null && onClear != null
              ? IconButton(icon: const Icon(Icons.close), onPressed: onClear)
              : const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(
          value == null ? 'Pick a date' : DateFormat.yMMMMd().format(value!),
        ),
      ),
    );
  }
}
