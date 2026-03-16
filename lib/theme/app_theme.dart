import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_tech_flutter/controllers/theme_controller.dart';

// ─── Dark theme colors ─────────────────────────────────────────────────────
const Color _darkPrimary = Color(0xFFF68B1F);
const Color _darkBackground = Color(0xFF021C2D);
const Color _darkCard = Color(0xFF0A2A45);
const Color _darkAccentBlue = Color(0xFF2F6FED);
const Color _darkOnSurface = Color(0xFFFFFFFF);
const Color _darkOnSurfaceVariant = Color(0xFFA8C0D8);
const Color _darkBorder = Color(0xFF1A3A5C);

// ─── Light theme colors ─────────────────────────────────────────────────────
// درجات أوضح وأكثر تبايناً في الوضع الفاتح
const Color _lightPrimary = Color(0xFFF68B1F);
const Color _lightBackground = Color(0xFFE1E5ED); // خلفية أغمق قليلاً لتمييز البطاقات
const Color _lightCard = Color(0xFFF9FAFB); // بطاقات أفتح من الخلفية لكن ليست أبيض صافي
const Color _lightAccentBlue = Color(0xFF2563EB);
const Color _lightTextDark = Color(0xFF111827); // نص غامق جداً لقراءة أوضح
const Color _lightOnSurfaceVariant = Color(0xFF4B5563); // نص ثانوي أغمق
const Color _lightBorder = Color(0xFFD1D5DB);

const Color _error = Color(0xFFEF5350);
const Color _success = Color(0xFF2E7D32);

/// Global theme system — light and dark themes
class AppTheme {
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: _lightBackground,
        colorScheme: const ColorScheme.light(
          primary: _lightPrimary,
          onPrimary: Colors.black,
          secondary: _lightAccentBlue,
          onSecondary: Colors.white,
          surface: _lightCard,
          onSurface: _lightTextDark,
          surfaceContainerHighest: _lightCard,
          onSurfaceVariant: _lightOnSurfaceVariant,
          error: _error,
          onError: Colors.white,
          outline: _lightBorder,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: _lightTextDark),
          titleTextStyle: TextStyle(
            color: _lightTextDark,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: CardThemeData(
          color: _lightCard,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _lightCard,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _lightBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _lightBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _lightPrimary, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _error)),
          hintStyle: const TextStyle(color: _lightOnSurfaceVariant, fontSize: 16),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: _lightTextDark, fontSize: 17, height: 1.4),
          bodyMedium: TextStyle(color: _lightTextDark, fontSize: 15, height: 1.4),
          bodySmall: TextStyle(color: _lightOnSurfaceVariant, fontSize: 13, height: 1.4),
          // عناوين أوضح في الوضع الفاتح
          titleLarge: TextStyle(color: _lightPrimary, fontSize: 22, fontWeight: FontWeight.bold),
          titleMedium: TextStyle(color: _lightPrimary, fontSize: 18, fontWeight: FontWeight.w600),
          titleSmall: TextStyle(color: _lightOnSurfaceVariant, fontSize: 15, fontWeight: FontWeight.w600),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: _lightCard,
          selectedItemColor: _lightPrimary,
          unselectedItemColor: _lightOnSurfaceVariant,
          type: BottomNavigationBarType.fixed,
        ),
        dividerColor: _lightBorder,
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _darkBackground,
        colorScheme: const ColorScheme.dark(
          primary: _darkPrimary,
          onPrimary: Colors.black,
          secondary: _darkAccentBlue,
          onSecondary: Colors.white,
          surface: _darkCard,
          onSurface: _darkOnSurface,
          surfaceContainerHighest: _darkCard,
          onSurfaceVariant: _darkOnSurfaceVariant,
          error: _error,
          onError: Colors.white,
          outline: _darkBorder,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: _darkOnSurface),
          titleTextStyle: TextStyle(
            color: _darkOnSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        cardTheme: CardThemeData(
          color: _darkCard,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _darkCard,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _darkBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _darkBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _darkPrimary, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _error)),
          hintStyle: TextStyle(color: _darkOnSurfaceVariant.withOpacity(0.9), fontSize: 16),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: _darkOnSurface, fontSize: 16),
          bodyMedium: TextStyle(color: _darkOnSurface, fontSize: 14),
          bodySmall: TextStyle(color: _darkOnSurfaceVariant, fontSize: 12),
          titleLarge: TextStyle(color: _darkOnSurface, fontSize: 20, fontWeight: FontWeight.bold),
          titleMedium: TextStyle(color: _darkOnSurface, fontSize: 16, fontWeight: FontWeight.w600),
          titleSmall: TextStyle(color: _darkOnSurfaceVariant, fontSize: 14),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: _darkCard,
          selectedItemColor: _darkPrimary,
          unselectedItemColor: _darkOnSurfaceVariant,
          type: BottomNavigationBarType.fixed,
        ),
        dividerColor: _darkBorder,
      );

  /// Backward compatibility
  static ThemeData get theme => darkTheme;
}

/// Theme-aware decorations — pass BuildContext to use current theme
class AppThemeDecorations {
  /// Secondary/muted text and icon color — readable in both light and dark (e.g. #6B7280 light, #A8C0D8 dark).
  static Color mutedColor(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;

  /// Dynamic page background: dark blue in dark mode, soft gray in light mode.
  static Color pageBackground(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF0B1F3A) : _lightBackground;
  }

  /// Dynamic card/section color: deep blue in dark mode, white in light mode.
  static Color cardColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF162F4D) : _lightCard;
  }

  /// Card decoration with theme-aware color and subtle shadow in light mode.
  static BoxDecoration pageCardDecoration(BuildContext context, [double radius = 20]) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: cardColor(context),
      borderRadius: BorderRadius.circular(radius),
      boxShadow: isDark
          ? []
          : [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
    );
  }

  /// Gradient background using theme background → surface
  static BoxDecoration gradientBackground(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [c.background, c.surface],
      ),
    );
  }

  /// Card with shadow (Login-style)
  static BoxDecoration loginStyleCard(BuildContext context, [double radius = 24]) {
    final c = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.08),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  /// Card with optional soft shadow in light mode for hierarchy.
  static BoxDecoration card(BuildContext context, [double radius = 24]) {
    final c = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: isDark
          ? []
          : [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
    );
  }

  /// Primary button gradient (same in both themes)
  static const LinearGradient primaryButtonGradient = LinearGradient(
    colors: [Color(0xFF2F6FED), Color(0xFFF68B1F)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}

/// Unified ET logo widget (static, no tap)
class EtLogo extends StatelessWidget {
  final double size;

  const EtLogo({super.key, this.size = 70});

  @override
  Widget build(BuildContext context) {
    final scale = size / 70;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18 * scale),
        color: Theme.of(context).colorScheme.primary,
      ),
      child: Center(
        child: Text(
          'ET',
          style: TextStyle(
            fontSize: (28 * scale).roundToDouble(),
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

/// ET logo that toggles theme on tap. Use everywhere the logo should switch Light/Dark mode.
class ThemeToggleLogo extends StatelessWidget {
  final double size;
  final VoidCallback? onToggle;

  const ThemeToggleLogo({super.key, this.size = 44, this.onToggle});

  @override
  Widget build(BuildContext context) {
    final scale = size / 44;
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onToggle ?? () => context.read<ThemeController>().toggleTheme(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: primary,
          borderRadius: BorderRadius.circular(12 * scale),
        ),
        alignment: Alignment.center,
        child: Text(
          'ET',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: (16 * scale).roundToDouble(),
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

/// Theme-aware input decoration
InputDecoration appThemeInputDecoration(
  BuildContext context, {
  required String hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final c = Theme.of(context).colorScheme;
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(color: c.onSurfaceVariant.withOpacity(0.9), fontSize: 16),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: c.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c.error),
    ),
  );
}

/// Legacy color getters — prefer Theme.of(context).colorScheme in new code
class AppThemeColors {
  static const Color primary = Color(0xFFF68B1F);
  static const Color accentBlue = Color(0xFF2F6FED);
  static const Color error = Color(0xFFEF5350);
  static const Color success = Color(0xFF2E7D32);
}
