/// VoiceReader brand theme — Material 3, dark navy first.
///
/// Brand tokens (kept in sync with docs/design mockups):
///   navy  #0B1B33  background
///   coral #FF6B4A  primary / actions / highlight
///   teal  #2DD4BF  secondary / progress / accents
library;

import 'package:flutter/material.dart';

abstract final class BrandColors {
  static const navy = Color(0xFF0B1B33);
  static const navyCard = Color(0xFF12264A);
  static const navyRaised = Color(0xFF1B345E);
  static const coral = Color(0xFFFF6B4A);
  static const coralSoft = Color(0xFFFF8563);
  static const teal = Color(0xFF2DD4BF);
  static const text = Color(0xFFE8EDF7);
  static const muted = Color(0xFF93A4C4);
}

/// Spacing tokens — use instead of magic `16`, `24` in widgets.
@immutable
class AppSpacing extends ThemeExtension<AppSpacing> {
  const AppSpacing({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
  });

  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;

  static const standard = AppSpacing(xs: 4, sm: 8, md: 16, lg: 24, xl: 32);

  @override
  AppSpacing copyWith({double? xs, double? sm, double? md, double? lg, double? xl}) =>
      AppSpacing(
        xs: xs ?? this.xs,
        sm: sm ?? this.sm,
        md: md ?? this.md,
        lg: lg ?? this.lg,
        xl: xl ?? this.xl,
      );

  @override
  AppSpacing lerp(ThemeExtension<AppSpacing>? other, double t) {
    if (other is! AppSpacing) return this;
    return AppSpacing(
      xs: xs + (other.xs - xs) * t,
      sm: sm + (other.sm - sm) * t,
      md: md + (other.md - md) * t,
      lg: lg + (other.lg - lg) * t,
      xl: xl + (other.xl - xl) * t,
    );
  }
}

/// Radius tokens — consistent card/button rounding.
@immutable
class AppRadii extends ThemeExtension<AppRadii> {
  const AppRadii({required this.sm, required this.md, required this.lg});

  final double sm;
  final double md;
  final double lg;

  static const standard = AppRadii(sm: 8, md: 12, lg: 14);

  @override
  AppRadii copyWith({double? sm, double? md, double? lg}) =>
      AppRadii(sm: sm ?? this.sm, md: md ?? this.md, lg: lg ?? this.lg);

  @override
  AppRadii lerp(ThemeExtension<AppRadii>? other, double t) {
    if (other is! AppRadii) return this;
    return AppRadii(
      sm: sm + (other.sm - sm) * t,
      md: md + (other.md - md) * t,
      lg: lg + (other.lg - lg) * t,
    );
  }
}

abstract final class AppTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      surface: BrandColors.navy,
      primary: BrandColors.coral,
      onPrimary: Color(0xFF1A0E08),
      secondary: BrandColors.teal,
      onSecondary: Color(0xFF04231E),
      error: Color(0xFFFFB4AB),
      onSurface: BrandColors.text,
      surfaceContainerHighest: BrandColors.navyCard,
      outline: BrandColors.navyRaised,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: BrandColors.navy,
      extensions: const [AppSpacing.standard, AppRadii.standard],
      appBarTheme: const AppBarTheme(
        backgroundColor: BrandColors.navy,
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        color: BrandColors.navyCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BrandColors.coral,
          foregroundColor: const Color(0xFF1A0E08),
          minimumSize: const Size(64, 52),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: BrandColors.navyCard,
        selectedItemColor: BrandColors.teal,
        unselectedItemColor: BrandColors.muted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerColor: BrandColors.navyRaised,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: BrandColors.text,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          color: BrandColors.text,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: BrandColors.text, height: 1.55),
        bodyMedium: TextStyle(color: BrandColors.text, height: 1.55),
        bodySmall: TextStyle(color: BrandColors.muted),
      ),
    );
  }
}
