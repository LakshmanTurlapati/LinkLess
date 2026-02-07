import 'package:flutter/material.dart';

/// Material 3 theme configuration for the LinkLess app.
///
/// Provides a light theme using Material 3 design system.
/// Can be extended with dark theme and custom color schemes later.
class AppTheme {
  AppTheme._();

  /// Light theme with Material 3 and blue color scheme.
  static ThemeData get light {
    return ThemeData(
      colorSchemeSeed: Colors.blue,
      useMaterial3: true,
      brightness: Brightness.light,
    );
  }
}
