import 'package:flutter/material.dart';

/// الهوية: أزرق داكن جداً خلفية، Navy للبطاقات، نص أبيض واضح
class AppColors {
  /// خلفية التطبيق — Very Dark Blue
  static const Color bg = Color(0xFF001220);
  /// البطاقات والقوائم — Navy Blue
  static const Color card = Color(0xFF001F3F);
  static const Color border = Color(0xFF1A3A5C);
  /// النص الرئيسي — أبيض واضح
  static const Color text = Color(0xFFFFFFFF);
  /// النص الثانوي
  static const Color muted = Color(0xFFB0BEC5);
  static const Color primary = Color(0xFFFF9F1C);
  static const Color primaryDark = Color(0xFFE65100);
  static const Color success = Color(0xFF2E7D32);
  static const Color error = Color(0xFFEF5350);
  static const Color warning = Color(0xFFE65100);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFFF6F8FB),
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.primaryDark,
        surface: AppColors.card,
        error: AppColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: AppColors.text),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF001A2E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.muted),
        hintStyle: const TextStyle(color: AppColors.muted),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.card,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.muted,
        type: BottomNavigationBarType.fixed,
      ),
      dividerColor: AppColors.border,
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.text),
        bodyMedium: TextStyle(color: AppColors.text),
        bodySmall: TextStyle(color: AppColors.muted),
        titleLarge: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
      ),
    );
  }
}
