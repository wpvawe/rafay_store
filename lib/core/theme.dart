import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  static const Color primary = Color(0xFFD32F2F);
  static const Color primaryDark = Color(0xFF9A0007);
  static const Color primaryLight = Color(0xFFFF6659);

  static const Color secondary = Color(0xFF00ACC1);
  static const Color secondaryDark = Color(0xFF007C91);
  static const Color secondaryLight = Color(0xFF5DDEF4);

  static const Color amber = Color(0xFFFDD835);

  static const Color background = Color(0xFFF7F8FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF0F2F5);

  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF1A1A2E);
  static const Color onSurfaceVariant = Color(0xFF6B7280);

  // Status colors — 4 statuses
  static const Color statusPending = Color(0xFFF59E0B);
  static const Color statusAvailable = Color(0xFF16A34A);
  static const Color statusDeferred = Color(0xFF2563EB);
  static const Color statusUrgent = Color(0xFFDC2626);

  static const Color statusPendingBg = Color(0xFFFFF8E1);
  static const Color statusAvailableBg = Color(0xFFECFDF5);
  static const Color statusDeferredBg = Color(0xFFEFF6FF);
  static const Color statusUrgentBg = Color(0xFFFEF2F2);

  static const Color divider = Color(0xFFE5E7EB);
  static const Color border = Color(0xFFD1D5DB);
  static const Color error = Color(0xFFB00020);
}

// Urdu/Arabic fallback — relies on Android/iOS system fonts
// (NotoNastaliqUrdu and NotoNaskhArabic are NOT bundled as assets;
//  listing non-existent custom fonts here prevents Flutter from finding
//  the system equivalents, causing text rendering issues.)
const List<String> _urduFallback = [
  'sans-serif',
];

TextStyle _withUrdu(TextStyle style) =>
    style.copyWith(fontFamilyFallback: _urduFallback);

final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,

  colorScheme: const ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    secondary: AppColors.secondary,
    onSecondary: AppColors.onPrimary,
    error: AppColors.error,
    surface: AppColors.surface,
    onSurface: AppColors.onSurface,
    surfaceContainerHighest: AppColors.surfaceVariant,
  ),

  scaffoldBackgroundColor: AppColors.background,

  textTheme: TextTheme(
    displayLarge: _withUrdu(GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
    titleLarge: _withUrdu(GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
    titleMedium: _withUrdu(GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
    bodyLarge: _withUrdu(GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.onSurface)),
    bodyMedium: _withUrdu(GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.onSurface)),
    bodySmall: _withUrdu(GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.onSurfaceVariant)),
    labelLarge: _withUrdu(GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
    labelMedium: _withUrdu(GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
    labelSmall: _withUrdu(GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.onSurfaceVariant)),
    headlineMedium: _withUrdu(GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
    headlineSmall: _withUrdu(GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
    titleSmall: _withUrdu(GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
  ),

  appBarTheme: AppBarTheme(
    backgroundColor: AppColors.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 1,
    shadowColor: AppColors.divider,
    centerTitle: false,
    titleTextStyle: GoogleFonts.inter(
      fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface,
    ).copyWith(fontFamilyFallback: _urduFallback),
    iconTheme: const IconThemeData(color: AppColors.onSurface),
  ),

  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: AppColors.surface,
    indicatorColor: AppColors.primary.withValues(alpha: 0.12),
    labelTextStyle: WidgetStateProperty.all(
      GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
    ),
    iconTheme: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return const IconThemeData(color: AppColors.primary);
      }
      return const IconThemeData(color: AppColors.onSurfaceVariant);
    }),
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    elevation: 0,
  ),

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
      elevation: 0,
    ),
  ),

  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),

  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      side: const BorderSide(color: AppColors.primary),
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),

  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surfaceVariant,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border, width: 1)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 1)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
    hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant).copyWith(fontFamilyFallback: _urduFallback),
    labelStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurface).copyWith(fontFamilyFallback: _urduFallback),
    floatingLabelStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.primary).copyWith(fontFamilyFallback: _urduFallback),
    errorStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.error),
  ),

  cardTheme: CardThemeData(
    color: AppColors.surface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: AppColors.divider),
    ),
    margin: EdgeInsets.zero,
  ),

  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: AppColors.surface,
    selectedItemColor: AppColors.primary,
    unselectedItemColor: AppColors.onSurfaceVariant,
    elevation: 0,
    type: BottomNavigationBarType.fixed,
  ),

  dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1, space: 0),

  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: AppColors.primary,
    foregroundColor: AppColors.onPrimary,
    elevation: 2,
  ),

  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    backgroundColor: AppColors.onSurface,
    contentTextStyle: GoogleFonts.inter(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500).copyWith(fontFamilyFallback: _urduFallback),
  ),

  chipTheme: ChipThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    side: BorderSide.none,
  ),
);
