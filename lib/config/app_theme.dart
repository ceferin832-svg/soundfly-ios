import 'package:flutter/material.dart';
import 'app_config.dart';

/// App theme configuration
/// 
/// Defines the color scheme and styling for the Soundfly iOS app
class AppTheme {
  // ===========================================
  // COLORS
  // ===========================================
  
  /// Primary color (red - same as Android app)
  static const Color primaryColor = Color(AppConfig.primaryColorValue);
  
  /// Purple colors
  static const Color purple200 = Color(0xFFBB86FC);
  static const Color purple500 = Color(0xFF6200EE);
  static const Color purple700 = Color(0xFF3700B3);
  
  /// Teal colors
  static const Color teal200 = Color(0xFF03DAC5);
  static const Color teal700 = Color(0xFF018786);
  
  /// Basic colors
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color red = Color(0xFFFF3044);
  static const Color yellow = Color(0xFFE67D20);
  static const Color lightBlack = Color(0xFF23232C);
  
  /// Background colors
  static const Color splashBackground = black;
  static const Color scaffoldBackground = white;
  static const Color darkScaffoldBackground = lightBlack;
  
  // ===========================================
  // LIGHT THEME
  // ===========================================
  
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: scaffoldBackground,
      colorScheme: const ColorScheme.light(
        primary: purple500,
        onPrimary: white,
        secondary: teal200,
        onSecondary: black,
        surface: white,
        onSurface: black,
        error: red,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: white,
        foregroundColor: black,
        elevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
      ),
    );
  }
  
  // ===========================================
  // DARK THEME
  // ===========================================
  
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: darkScaffoldBackground,
      colorScheme: const ColorScheme.dark(
        primary: purple200,
        onPrimary: black,
        secondary: teal200,
        onSecondary: black,
        surface: lightBlack,
        onSurface: white,
        error: red,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBlack,
        foregroundColor: white,
        elevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightBlack,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
      ),
    );
  }
}
