import 'package:flutter/material.dart';

/// Brand + semantic color tokens. The single source of truth for any color
/// reference in the app — *never* hardcode `Color(0xFF...)` outside this file.
///
/// Access via [GarageColors] (theme extension): `context.tokens.warning`.
class _Palette {
  _Palette._();

  // Brand — deep navy primary + warm amber accent. The amber doubles as a
  // semantic "fuel/energy" cue across the fuel and predict screens.
  static const navy = Color(0xFF1F3A5F);
  static const navyDark = Color(0xFF7BA7D9); // brighter navy for dark mode
  static const amber = Color(0xFFF2A341);

  // Semantic — overdue / due-soon / ok / informational
  static const successLight = Color(0xFF1E8E5C);
  static const successDark = Color(0xFF5CC495);
  static const warningLight = Color(0xFFE08017);
  static const warningDark = Color(0xFFF2A341);
  static const dangerLight = Color(0xFFC13B2E);
  static const dangerDark = Color(0xFFE5675C);

  // Surfaces
  static const surfaceLight = Color(0xFFF7F8FA);
  static const surfaceDark = Color(0xFF0E1116);
  static const surfaceElevLight = Color(0xFFFFFFFF);
  static const surfaceElevDark = Color(0xFF16191F);
  static const outlineLight = Color(0xFFD6DAE0);
  static const outlineDark = Color(0xFF272B33);
}

/// Theme extension carrying app-specific semantic colors that don't live in
/// Material's ColorScheme. Lookup pattern:
///
/// ```dart
/// final tokens = Theme.of(context).extension<GarageColors>()!;
/// container.color = tokens.warningContainer;
/// ```
class GarageColors extends ThemeExtension<GarageColors> {
  const GarageColors({
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.accent,
    required this.hero,
  });

  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color danger;
  final Color dangerContainer;

  /// Brand accent — amber. Used for highlights, FABs, predict gauge.
  final Color accent;

  /// Deep brand color for hero card backgrounds.
  final Color hero;

  static const light = GarageColors(
    success: _Palette.successLight,
    successContainer: Color(0xFFE0F3E9),
    warning: _Palette.warningLight,
    warningContainer: Color(0xFFFDEFD9),
    danger: _Palette.dangerLight,
    dangerContainer: Color(0xFFFCE4E1),
    accent: _Palette.amber,
    hero: _Palette.navy,
  );

  static const dark = GarageColors(
    success: _Palette.successDark,
    successContainer: Color(0xFF1E3B2D),
    warning: _Palette.warningDark,
    warningContainer: Color(0xFF3B2A14),
    danger: _Palette.dangerDark,
    dangerContainer: Color(0xFF3B1F1C),
    accent: _Palette.amber,
    hero: Color(0xFF142543),
  );

  @override
  GarageColors copyWith({
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? danger,
    Color? dangerContainer,
    Color? accent,
    Color? hero,
  }) {
    return GarageColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      accent: accent ?? this.accent,
      hero: hero ?? this.hero,
    );
  }

  @override
  GarageColors lerp(ThemeExtension<GarageColors>? other, double t) {
    if (other is! GarageColors) return this;
    return GarageColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      hero: Color.lerp(hero, other.hero, t)!,
    );
  }
}

/// Convenience extension to grab tokens off `BuildContext` without the
/// `Theme.of(context).extension<GarageColors>()!` ceremony.
extension GarageColorsContext on BuildContext {
  GarageColors get tokens => Theme.of(this).extension<GarageColors>()!;
}

/// Brand colors exposed for the ColorScheme builder. Internal use only —
/// feature code should go through ColorScheme or GarageColors instead.
class BrandColors {
  BrandColors._();
  static const navy = _Palette.navy;
  static const navyDark = _Palette.navyDark;
  static const amber = _Palette.amber;
  static const surfaceLight = _Palette.surfaceLight;
  static const surfaceDark = _Palette.surfaceDark;
  static const surfaceElevLight = _Palette.surfaceElevLight;
  static const surfaceElevDark = _Palette.surfaceElevDark;
  static const outlineLight = _Palette.outlineLight;
  static const outlineDark = _Palette.outlineDark;
}
