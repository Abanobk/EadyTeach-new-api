import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_tech_flutter/controllers/theme_controller.dart';

const Color _brandPrimary = Color(0xFFF59E0B);
const Color _brandSecondary = Color(0xFF2563EB);
const Color _brandTertiary = Color(0xFF14B8A6);
const Color _success = Color(0xFF16A34A);
const Color _error = Color(0xFFDC2626);

const Color _lightBackground = Color(0xFFF4F7FB);
const Color _lightSurface = Color(0xFFFFFFFF);
const Color _lightSurfaceAlt = Color(0xFFE9EEF7);
const Color _lightText = Color(0xFF0F172A);
const Color _lightMuted = Color(0xFF64748B);
const Color _lightBorder = Color(0xFFD7E0EC);

const Color _darkBackground = Color(0xFF06111F);
const Color _darkSurface = Color(0xFF0D1B2A);
const Color _darkSurfaceAlt = Color(0xFF13263B);
const Color _darkText = Color(0xFFF8FAFC);
const Color _darkMuted = Color(0xFF9FB3C8);
const Color _darkBorder = Color(0xFF1E3954);

class AppColors {
  static const Color bg = _darkBackground;
  static const Color background = _lightBackground;
  static const Color card = _darkSurface;
  static const Color border = _darkBorder;
  static const Color text = _darkText;
  static const Color muted = _darkMuted;
  static const Color primary = _brandPrimary;
  static const Color primaryDark = _brandSecondary;
  static const Color success = _success;
  static const Color error = _error;
  static const Color warning = _brandPrimary;
}

class AppTheme {
  static ThemeData get lightTheme {
    final scheme = const ColorScheme.light(
      primary: _brandPrimary,
      onPrimary: Colors.black,
      secondary: _brandSecondary,
      onSecondary: Colors.white,
      tertiary: _brandTertiary,
      onTertiary: Colors.white,
      error: _error,
      onError: Colors.white,
      surface: _lightSurface,
      onSurface: _lightText,
      outline: _lightBorder,
      onSurfaceVariant: _lightMuted,
      surfaceContainerHighest: _lightSurfaceAlt,
      background: _lightBackground,
      onBackground: _lightText,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: _lightBackground,
      fontFamily: 'Roboto',
      primaryColor: _brandPrimary,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.black.withOpacity(0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      dividerColor: _lightBorder,
      splashColor: _brandPrimary.withOpacity(0.08),
      highlightColor: Colors.transparent,
      iconTheme: IconThemeData(color: scheme.onSurface),
      textTheme: TextTheme(
        displaySmall: TextStyle(color: scheme.onSurface, fontSize: 34, fontWeight: FontWeight.w800, height: 1.1),
        headlineMedium: TextStyle(color: scheme.onSurface, fontSize: 28, fontWeight: FontWeight.w800, height: 1.15),
        headlineSmall: TextStyle(color: scheme.onSurface, fontSize: 24, fontWeight: FontWeight.w800, height: 1.2),
        titleLarge: const TextStyle(color: _lightText, fontSize: 22, fontWeight: FontWeight.w800, height: 1.2),
        titleMedium: const TextStyle(color: _lightText, fontSize: 18, fontWeight: FontWeight.w700, height: 1.25),
        titleSmall: const TextStyle(color: _lightMuted, fontSize: 14, fontWeight: FontWeight.w700, height: 1.25),
        bodyLarge: const TextStyle(color: _lightText, fontSize: 16, fontWeight: FontWeight.w500, height: 1.55),
        bodyMedium: const TextStyle(color: _lightText, fontSize: 14, fontWeight: FontWeight.w500, height: 1.55),
        bodySmall: const TextStyle(color: _lightMuted, fontSize: 12, fontWeight: FontWeight.w500, height: 1.45),
        labelLarge: const TextStyle(color: _lightText, fontSize: 14, fontWeight: FontWeight.w700),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _lightSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        hintStyle: const TextStyle(color: _lightMuted, fontSize: 15, fontWeight: FontWeight.w500),
        labelStyle: const TextStyle(color: _lightMuted, fontSize: 14, fontWeight: FontWeight.w600),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _brandSecondary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _error, width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _lightSurfaceAlt,
        selectedColor: _brandPrimary.withOpacity(0.15),
        secondarySelectedColor: _brandSecondary.withOpacity(0.15),
        labelStyle: const TextStyle(color: _lightText, fontWeight: FontWeight.w700),
        side: const BorderSide(color: _lightBorder),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: _lightSurface.withOpacity(0.98),
        selectedItemColor: _brandPrimary,
        unselectedItemColor: _lightMuted,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10.5),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _brandPrimary,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: _brandPrimary,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: const BorderSide(color: _lightBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0F172A),
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static ThemeData get darkTheme {
    final scheme = const ColorScheme.dark(
      primary: _brandPrimary,
      onPrimary: Colors.black,
      secondary: Color(0xFF60A5FA),
      onSecondary: Colors.black,
      tertiary: Color(0xFF2DD4BF),
      onTertiary: Colors.black,
      error: Color(0xFFF87171),
      onError: Colors.black,
      surface: _darkSurface,
      onSurface: _darkText,
      outline: _darkBorder,
      onSurfaceVariant: _darkMuted,
      surfaceContainerHighest: _darkSurfaceAlt,
      background: _darkBackground,
      onBackground: _darkText,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: _darkBackground,
      fontFamily: 'Roboto',
      primaryColor: _brandPrimary,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.black.withOpacity(0.25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      dividerColor: _darkBorder,
      splashColor: _brandPrimary.withOpacity(0.12),
      highlightColor: Colors.transparent,
      iconTheme: IconThemeData(color: scheme.onSurface),
      textTheme: TextTheme(
        displaySmall: TextStyle(color: scheme.onSurface, fontSize: 34, fontWeight: FontWeight.w800, height: 1.1),
        headlineMedium: TextStyle(color: scheme.onSurface, fontSize: 28, fontWeight: FontWeight.w800, height: 1.15),
        headlineSmall: TextStyle(color: scheme.onSurface, fontSize: 24, fontWeight: FontWeight.w800, height: 1.2),
        titleLarge: const TextStyle(color: _darkText, fontSize: 22, fontWeight: FontWeight.w800, height: 1.2),
        titleMedium: const TextStyle(color: _darkText, fontSize: 18, fontWeight: FontWeight.w700, height: 1.25),
        titleSmall: const TextStyle(color: _darkMuted, fontSize: 14, fontWeight: FontWeight.w700, height: 1.25),
        bodyLarge: const TextStyle(color: _darkText, fontSize: 16, fontWeight: FontWeight.w500, height: 1.55),
        bodyMedium: const TextStyle(color: _darkText, fontSize: 14, fontWeight: FontWeight.w500, height: 1.55),
        bodySmall: const TextStyle(color: _darkMuted, fontSize: 12, fontWeight: FontWeight.w500, height: 1.45),
        labelLarge: const TextStyle(color: _darkText, fontSize: 14, fontWeight: FontWeight.w700),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkSurfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        hintStyle: const TextStyle(color: _darkMuted, fontSize: 15, fontWeight: FontWeight.w500),
        labelStyle: const TextStyle(color: _darkMuted, fontSize: 14, fontWeight: FontWeight.w600),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _brandPrimary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFF87171)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFF87171), width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _darkSurfaceAlt,
        selectedColor: _brandPrimary.withOpacity(0.18),
        secondarySelectedColor: const Color(0xFF60A5FA).withOpacity(0.18),
        labelStyle: const TextStyle(color: _darkText, fontWeight: FontWeight.w700),
        side: const BorderSide(color: _darkBorder),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: _darkSurface.withOpacity(0.96),
        selectedItemColor: _brandPrimary,
        unselectedItemColor: _darkMuted,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10.5),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _brandPrimary,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: _brandPrimary,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: const BorderSide(color: _darkBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF111827),
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static ThemeData get theme => darkTheme;
}

class AppThemeDecorations {
  static Color mutedColor(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;

  static Color pageBackground(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? _darkBackground : _lightBackground;
  }

  static Color cardColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? _darkSurface : _lightSurface;
  }

  static BoxShadow _lightShadow([double opacity = 0.08]) => BoxShadow(
        color: const Color(0xFF0F172A).withOpacity(opacity),
        blurRadius: 24,
        spreadRadius: -6,
        offset: const Offset(0, 18),
      );

  static BoxDecoration pageCardDecoration(BuildContext context, [double radius = 24]) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: cardColor(context),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: c.outline.withOpacity(isDark ? 0.7 : 0.8)),
      boxShadow: isDark ? [] : [_lightShadow()],
    );
  }

  static BoxDecoration gradientBackground(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: isDark
            ? const [Color(0xFF06111F), Color(0xFF0B1A2C), Color(0xFF13263B)]
            : const [Color(0xFFF8FAFD), Color(0xFFF1F5FB), Color(0xFFE8EEF8)],
      ),
    );
  }

  static BoxDecoration heroPanel(BuildContext context, {double radius = 28}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: isDark
            ? const [Color(0xFF142B44), Color(0xFF0D1B2A), Color(0xFF0A1624)]
            : const [Color(0xFF1D4ED8), Color(0xFF2563EB), Color(0xFFF59E0B)],
      ),
      boxShadow: isDark
          ? []
          : [
              BoxShadow(
                color: const Color(0xFF1D4ED8).withOpacity(0.16),
                blurRadius: 30,
                spreadRadius: -8,
                offset: const Offset(0, 20),
              ),
            ],
    );
  }

  static BoxDecoration glassCard(BuildContext context, {double radius = 24}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: (isDark ? Colors.white : c.surface).withOpacity(isDark ? 0.06 : 0.72),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withOpacity(isDark ? 0.08 : 0.5)),
      boxShadow: isDark ? [] : [_lightShadow(0.05)],
    );
  }

  static BoxDecoration loginStyleCard(BuildContext context, [double radius = 28]) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: isDark ? c.surface.withOpacity(0.94) : Colors.white.withOpacity(0.92),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: c.outline.withOpacity(isDark ? 0.6 : 0.75)),
      boxShadow: isDark
          ? []
          : [
              BoxShadow(
                color: const Color(0xFF0F172A).withOpacity(0.12),
                blurRadius: 40,
                spreadRadius: -10,
                offset: const Offset(0, 28),
              ),
            ],
    );
  }

  static BoxDecoration card(BuildContext context, [double radius = 24]) {
    return pageCardDecoration(context, radius);
  }

  static const LinearGradient primaryButtonGradient = LinearGradient(
    colors: [Color(0xFF2563EB), Color(0xFFF59E0B)],
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
  );
}

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
        borderRadius: BorderRadius.circular(20 * scale),
        gradient: AppThemeDecorations.primaryButtonGradient,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.24),
            blurRadius: 18,
            spreadRadius: -4,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        'ET',
        style: TextStyle(
          fontSize: (26 * scale).roundToDouble(),
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
          color: Colors.white,
        ),
      ),
    );
  }
}

class ThemeToggleLogo extends StatelessWidget {
  final double size;
  final VoidCallback? onToggle;

  const ThemeToggleLogo({super.key, this.size = 46, this.onToggle});

  @override
  Widget build(BuildContext context) {
    final scale = size / 46;
    return GestureDetector(
      onTap: onToggle ?? () => context.read<ThemeController>().toggleTheme(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size + (10 * scale),
            height: size + (10 * scale),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
            ),
          ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14 * scale),
              gradient: AppThemeDecorations.primaryButtonGradient,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.22),
                  blurRadius: 20,
                  spreadRadius: -5,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              'ET',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                fontSize: (16 * scale).roundToDouble(),
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration appThemeInputDecoration(
  BuildContext context, {
  required String hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? labelText,
}) {
  final c = Theme.of(context).colorScheme;
  return InputDecoration(
    hintText: hintText,
    labelText: labelText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Theme.of(context).brightness == Brightness.dark ? c.surfaceContainerHighest : c.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    hintStyle: TextStyle(color: c.onSurfaceVariant.withOpacity(0.95), fontSize: 15, fontWeight: FontWeight.w500),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: c.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: c.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: c.secondary, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: c.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: c.error, width: 1.4),
    ),
  );
}
