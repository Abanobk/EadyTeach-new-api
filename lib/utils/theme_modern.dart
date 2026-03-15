import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Phase 2 – Smart Home UI/UX: Deep Navy Blue / Soft Orange / Light Grey-White
/// Glassmorphism cards (20px radius, BackdropFilter, soft shadow), Poppins font.
class AppColorsModern {
  static const Color primary = Color(0xFF001F3F);   // Deep Navy Blue
  static const Color accent = Color(0xFFFF9F1C);   // Soft Orange
  static const Color background = Color(0xFFF6F8FB); // Clean light (matches app theme)
  static const Color surface = Color(0xFFFFFFFF);
  static const Color cardLight = Color(0xE6FFFFFF);

  static const Color text = Color(0xFF1A1D21);
  static const Color textSecondary = Color(0xFF5C6370);
  static const Color muted = Color(0xFF8E9299);

  static const Color success = Color(0xFF2E7D32);
  static const Color error = Color(0xFFC62828);
  static const Color warning = Color(0xFFE65100);

  static const Color glassBorder = Color(0x33FFFFFF);
  static const Color shadowLight = Color(0x1A000000);
}

class AppFonts {
  static String get family => GoogleFonts.poppins().fontFamily!;
}

/// Glassmorphism card: 20px radius, frosted glass (BackdropFilter), soft shadow.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? tintColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 20,
    this.tintColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: (tintColor ?? AppColorsModern.cardLight).withOpacity(0.75),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: AppColorsModern.glassBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: AppColorsModern.shadowLight,
                blurRadius: 20,
                offset: const Offset(0, 8),
                spreadRadius: -4,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

BoxDecoration glassDecoration({double borderRadius = 20, Color? color}) {
  return BoxDecoration(
    color: (color ?? AppColorsModern.cardLight).withOpacity(0.75),
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(color: AppColorsModern.glassBorder, width: 1),
    boxShadow: [
      BoxShadow(
        color: AppColorsModern.shadowLight,
        blurRadius: 20,
        offset: const Offset(0, 8),
        spreadRadius: -4,
      ),
    ],
  );
}

ThemeData get themeModern {
  final poppins = GoogleFonts.poppins();
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColorsModern.background,
    primaryColor: AppColorsModern.primary,
    colorScheme: const ColorScheme.light(
      primary: AppColorsModern.primary,
      secondary: AppColorsModern.accent,
      surface: AppColorsModern.surface,
      error: AppColorsModern.error,
      onPrimary: Colors.white,
      onSecondary: Colors.black87,
      onSurface: AppColorsModern.text,
      onError: Colors.white,
    ),
    fontFamily: poppins.fontFamily,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: const IconThemeData(color: AppColorsModern.text),
      titleTextStyle: poppins.copyWith(
        color: AppColorsModern.text,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColorsModern.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColorsModern.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: poppins.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColorsModern.primary,
        textStyle: poppins.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColorsModern.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE0E4E8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColorsModern.primary, width: 2),
      ),
      labelStyle: poppins.copyWith(color: AppColorsModern.textSecondary),
      hintStyle: poppins.copyWith(color: AppColorsModern.muted),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      selectedItemColor: AppColorsModern.primary,
      unselectedItemColor: AppColorsModern.muted,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: poppins.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
      unselectedLabelStyle: poppins.copyWith(fontSize: 10),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColorsModern.accent,
      foregroundColor: Colors.white,
      elevation: 6,
    ),
    dividerColor: const Color(0xFFE0E4E8),
    textTheme: TextTheme(
      bodyLarge: poppins.copyWith(color: AppColorsModern.text),
      bodyMedium: poppins.copyWith(color: AppColorsModern.text),
      bodySmall: poppins.copyWith(color: AppColorsModern.textSecondary),
      titleLarge: poppins.copyWith(color: AppColorsModern.text, fontWeight: FontWeight.w700),
      titleMedium: poppins.copyWith(color: AppColorsModern.text, fontWeight: FontWeight.w600),
      titleSmall: poppins.copyWith(color: AppColorsModern.text, fontWeight: FontWeight.w600),
      labelLarge: poppins.copyWith(color: AppColorsModern.text, fontWeight: FontWeight.w600),
    ),
  );
}
