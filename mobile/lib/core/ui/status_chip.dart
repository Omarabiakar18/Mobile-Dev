import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum _Kind { overdue, dueSoon, ok, info }

/// Compact status pill used across reminder cards, document cards, the home
/// banner, and the predict-next card. Single source of truth for what
/// "overdue" / "due-soon" / "ok" / "info" look like visually.
class StatusChip extends StatelessWidget {
  const StatusChip.overdue({
    super.key,
    required this.label,
    this.icon = Icons.warning_amber_rounded,
  }) : _kind = _Kind.overdue;

  const StatusChip.dueSoon({
    super.key,
    required this.label,
    this.icon = Icons.schedule,
  }) : _kind = _Kind.dueSoon;

  const StatusChip.ok({
    super.key,
    required this.label,
    this.icon = Icons.check_circle_outline,
  }) : _kind = _Kind.ok;

  const StatusChip.info({
    super.key,
    required this.label,
    this.icon = Icons.info_outline,
  }) : _kind = _Kind.info;

  final String label;
  final IconData? icon;
  final _Kind _kind;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (_kind) {
      _Kind.overdue => (tokens.dangerContainer, tokens.danger),
      _Kind.dueSoon => (tokens.warningContainer, tokens.warning),
      _Kind.ok => (tokens.successContainer, tokens.success),
      _Kind.info => (scheme.primaryContainer, scheme.onPrimaryContainer),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon != null ? 8 : 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
