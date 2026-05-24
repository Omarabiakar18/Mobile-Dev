import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Shows a styled SnackBar with an icon + colored background so success vs
/// error is immediately readable. Cancels any in-flight SnackBar first so
/// rapid taps don't stack up. Uses the GarageColors theme extension so the
/// chrome adapts to light/dark.
void showFeedback(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final tokens = context.tokens;
  final (bg, fg) = isError
      ? (tokens.danger, Colors.white)
      : (tokens.success, Colors.white);

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: fg,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: fg, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: bg,
        duration: Duration(seconds: isError ? 5 : 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
      ),
    );
}
