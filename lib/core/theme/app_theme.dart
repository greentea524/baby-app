import 'package:flutter/material.dart';

/// Central light/dark theme (KAN-142, refined in KAN-167). Both brightnesses
/// derive from one seed so they stay consistent, with component tweaks that
/// keep surfaces legible and calm in dark mode.
abstract final class AppTheme {
  /// The palette used when the caregiver hasn't picked one (KAN-180).
  static const defaultSeed = Color(0xFF7E9BD0);

  static ThemeData light([Color seed = defaultSeed]) =>
      _base(Brightness.light, seed);

  static ThemeData dark([Color seed = defaultSeed]) =>
      _base(Brightness.dark, seed);

  static ThemeData _base(Brightness brightness, Color seed) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
        // A subtle tinted bar once content scrolls under it.
        scrolledUnderElevation: 2,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        elevation: 2,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        // Slightly raised container so cards read against the surface in dark.
        color: isDark
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(visualDensity: VisualDensity.compact),
      ),
    );
  }
}
