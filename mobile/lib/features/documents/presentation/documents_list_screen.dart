import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/status_chip.dart';
import '../data/document_model.dart';
import '../data/documents_api.dart';

class DocumentsListScreen extends ConsumerWidget {
  const DocumentsListScreen({super.key, required this.carId});
  final String carId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsListProvider(carId));

    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(documentsListProvider(carId)),
        child: docs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorState(
            message: e is ApiException ? e.message : e.toString(),
            onRetry: () => ref.invalidate(documentsListProvider(carId)),
          ),
          data: (list) => list.isEmpty
              ? _EmptyState(onAdd: () => context.push('/cars/$carId/documents/new'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _DocumentCard(document: list[i]),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add document'),
        onPressed: () => context.push('/cars/$carId/documents/new'),
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document});
  final Document document;

  Widget _buildChip(BuildContext context) {
    final days = document.daysUntilExpiry;
    if (days < 0) return StatusChip.overdue(label: 'Expired');
    if (days == 0) return StatusChip.overdue(label: 'Today');
    if (days <= 30) return StatusChip.dueSoon(label: '$days d');
    return StatusChip.ok(label: '$days d');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final urgent = document.isExpired || document.isExpiringSoon;
    final iconColor = urgent ? tokens.danger : tokens.accent;
    final iconBg = urgent
        ? tokens.danger.withValues(alpha: 0.12)
        : tokens.accent.withValues(alpha: 0.14);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetails(context, document),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(document.type.icon, color: iconColor),
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
                            document.type.label,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildChip(context),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Expires ${DateFormat.yMMMd().format(document.expiryDate)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _expiryPhrase(Document d) {
    final days = d.daysUntilExpiry;
    if (days < 0) {
      final n = -days;
      return n == 1 ? 'expired 1 day ago' : 'expired $n days ago';
    }
    if (days == 0) return 'expires today';
    if (days == 1) return 'expires in 1 day';
    return 'expires in $days days';
  }

  void _showDetails(BuildContext context, Document d) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(d.type.icon, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(d.type.label, style: theme.textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: 16),
                _MetaRow(label: 'Expires', value: DateFormat.yMMMMd().format(d.expiryDate)),
                if (d.issuedDate != null)
                  _MetaRow(
                    label: 'Issued',
                    value: DateFormat.yMMMMd().format(d.issuedDate!),
                  ),
                if (d.issuer != null && d.issuer!.isNotEmpty)
                  _MetaRow(label: 'Issuer', value: d.issuer!),
                if (d.notes != null && d.notes!.isNotEmpty)
                  _MetaRow(label: 'Notes', value: d.notes!),
                _MetaRow(label: 'File', value: d.fileUrl),
                const SizedBox(height: 8),
                Text(
                  _expiryPhrase(d),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: (d.isExpired || d.isExpiringSoon)
                        ? theme.colorScheme.error
                        : theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
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
        Icon(Icons.folder_open, size: 80, color: theme.colorScheme.outline),
        const SizedBox(height: 16),
        Text(
          'No documents yet',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Upload insurance, registration, or mécanique papers so you never miss a renewal.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add a document'),
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
            Text("Couldn't load documents", style: theme.textTheme.titleLarge),
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
