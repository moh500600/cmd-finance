import 'package:flutter/material.dart';

/// Finance palette: deep teal primary, emerald for money in, rose for money
/// out, amber for warnings, navy surfaces in dark mode.
class AppColors {
  static const primary = Color(0xFF0F766E);
  static const primaryDark = Color(0xFF0B4F4A);
  static const income = Color(0xFF059669);
  static const expense = Color(0xFFE11D48);
  static const transfer = Color(0xFF2563EB);
  static const warning = Color(0xFFF59E0B);
  static const gold = Color(0xFFD4A017);
  static const navy = Color(0xFF0B1324);
  static const navyCard = Color(0xFF131D33);
  static const chart = [Color(0xFF0F766E), Color(0xFF2563EB), Color(0xFFF59E0B), Color(0xFF7C3AED), Color(0xFFDB2777), Color(0xFF059669),
    Color(0xFFEA580C), Color(0xFF0891B2), Color(0xFF65A30D), Color(0xFFDC2626), Color(0xFF4F46E5), Color(0xFF64748B)];
}

class AppTheme {
  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: b).copyWith(
      primary: dark ? const Color(0xFF2DD4BF) : AppColors.primary,
      surface: dark ? AppColors.navy : const Color(0xFFF6F8FA),
      surfaceContainerLowest: dark ? AppColors.navyCard : Colors.white,
      surfaceContainerLow: dark ? const Color(0xFF16223B) : const Color(0xFFFFFFFF),
      surfaceContainer: dark ? const Color(0xFF1A2742) : const Color(0xFFF0F3F6),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Tajawal',
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent, centerTitle: false, elevation: 0,
          titleTextStyle: TextStyle(fontFamily: 'Tajawal', fontSize: 20, fontWeight: FontWeight.w700, color: scheme.onSurface)),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: scheme.outlineVariant.withValues(alpha: dark ? 0.25 : 0.5))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700, fontSize: 16))),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primary.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontFamily: 'Tajawal', fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 14)),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.4), space: 1),
    );
  }
}
