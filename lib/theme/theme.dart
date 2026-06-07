import 'package:flutter/material.dart';
 
class SGTColors {
  // Brand
  static const navy = Color(0xFF0d2137);
  static const navyLight = Color(0xFF112844);
  static const navyDeep = Color(0xFF070f1a);
 
  // Accent
  static const blue = Color(0xFF1a5fa8);
  static const blueLight = Color(0xFF2979cc);
  static const blueMuted = Color(0xFF4a7fc1);
 
  // Surface
  static const surface = Color(0xFF0d1625);
  static const surfaceRaised = Color(0xFF112030);
  static const border = Color(0xFF1e2d4a);
  static const borderLight = Color(0xFF2a3f5f);
 
  // Text
  static const textPrimary = Color(0xFFa8c8f0);
  static const textSecondary = Color(0xFF4a6a8a);
  static const textMuted = Color(0xFF2a4a6a);
 
  // Status
  static const online = Color(0xFF2ecc71);
  static const onlineBg = Color(0xFF0d2a1a);
  static const warning = Color(0xFFf39c12);
  static const danger = Color(0xFFe74c3c);
  static const dangerBg = Color(0xFF2a0a0a);
}
 
class SGTTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: SGTColors.navyDeep,
      colorScheme: const ColorScheme.dark(
        primary: SGTColors.blue,
        secondary: SGTColors.blueMuted,
        surface: SGTColors.surface,
        error: SGTColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: SGTColors.navyDeep,
        foregroundColor: SGTColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: SGTColors.blueMuted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 2.0,
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: SGTColors.textPrimary, fontSize: 14),
        bodyMedium: TextStyle(color: SGTColors.textPrimary, fontSize: 13),
        bodySmall: TextStyle(color: SGTColors.textSecondary, fontSize: 11),
        labelSmall: TextStyle(
          color: SGTColors.textMuted,
          fontSize: 9,
          letterSpacing: 1.2,
        ),
      ),
      dividerColor: SGTColors.border,
      cardColor: SGTColors.surface,
    );
  }
}