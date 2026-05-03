import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color _brandPrimary = Color(0xFF2F3E8F);
  static const Color _brandSecondary = Color(0xFF2F6FEB);
  static const Color _lightSurfaceTint = Color(0xFFF5F6FA);
  static const Color _lightCard = Colors.white;
  static const Color _darkSurface = Color(0xFF0F172A);
  static const Color _darkSurfaceContainer = Color(0xFF16213E);

  static final ColorScheme _lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: _brandPrimary,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFE6ECFA),
    onPrimaryContainer: const Color(0xFF172554),
    secondary: _brandSecondary,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFEAF1FF),
    onSecondaryContainer: const Color(0xFF163B73),
    tertiary: const Color(0xFF22B15D),
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFE8F5E9),
    onTertiaryContainer: const Color(0xFF14532D),
    error: const Color(0xFFDC2626),
    onError: Colors.white,
    errorContainer: const Color(0xFFFEE2E2),
    onErrorContainer: const Color(0xFF7F1D1D),
    surface: _lightCard,
    onSurface: const Color(0xFF111827),
    onSurfaceVariant: const Color(0xFF64748B),
    outline: const Color(0xFFDCE3F4),
    outlineVariant: const Color(0xFFE5E7EB),
    shadow: const Color(0x180E1A33),
    scrim: const Color(0x99000000),
    inverseSurface: const Color(0xFF1E293B),
    onInverseSurface: const Color(0xFFF8FAFC),
    inversePrimary: const Color(0xFFAFC0FF),
    surfaceTint: _brandPrimary,
  );

  static final ColorScheme _darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: const Color(0xFFAFC0FF),
    onPrimary: const Color(0xFF14235D),
    primaryContainer: const Color(0xFF253C8B),
    onPrimaryContainer: const Color(0xFFE1E8FF),
    secondary: const Color(0xFF9BB9FF),
    onSecondary: const Color(0xFF0D2A57),
    secondaryContainer: const Color(0xFF1A417B),
    onSecondaryContainer: const Color(0xFFDCE9FF),
    tertiary: const Color(0xFF5FD08B),
    onTertiary: const Color(0xFF08361A),
    tertiaryContainer: const Color(0xFF14532D),
    onTertiaryContainer: const Color(0xFFC9F4D6),
    error: const Color(0xFFF87171),
    onError: const Color(0xFF450A0A),
    errorContainer: const Color(0xFF7F1D1D),
    onErrorContainer: const Color(0xFFFECACA),
    surface: _darkSurfaceContainer,
    onSurface: const Color(0xFFF8FAFC),
    onSurfaceVariant: const Color(0xFF94A3B8),
    outline: const Color(0xFF334155),
    outlineVariant: const Color(0xFF1E293B),
    shadow: Colors.black,
    scrim: const Color(0xCC000000),
    inverseSurface: const Color(0xFFF8FAFC),
    onInverseSurface: const Color(0xFF111827),
    inversePrimary: _brandPrimary,
    surfaceTint: const Color(0xFFAFC0FF),
  );

  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: _lightColorScheme,
      scaffoldBackgroundColor: _lightSurfaceTint,
      canvasColor: _lightSurfaceTint,
      fontFamily: 'SF Pro',
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _lightColorScheme.surface,
        foregroundColor: _lightColorScheme.onSurface,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: _lightColorScheme.onSurface),
        titleTextStyle: TextStyle(
          color: _lightColorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          fontFamily: 'SF Pro',
        ),
      ),
      cardTheme: CardThemeData(
        color: _lightColorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _lightColorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: _lightColorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _lightColorScheme.surface,
        indicatorColor: _lightColorScheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected
                ? _lightColorScheme.primary
                : _lightColorScheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? _lightColorScheme.primary
                : _lightColorScheme.onSurfaceVariant,
          );
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _lightColorScheme.primary,
          foregroundColor: _lightColorScheme.onPrimary,
          disabledBackgroundColor: _lightColorScheme.outlineVariant,
          disabledForegroundColor: _lightColorScheme.onSurfaceVariant,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _lightColorScheme.primary,
          side: BorderSide(color: _lightColorScheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _lightColorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _lightColorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _lightColorScheme.primary, width: 1.3),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _lightColorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _lightColorScheme.error, width: 1.2),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _lightColorScheme.primary;
          }
          return _lightColorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _lightColorScheme.primaryContainer;
          }
          return _lightColorScheme.outlineVariant;
        }),
      ),
      dividerTheme: DividerThemeData(
        color: _lightColorScheme.outlineVariant,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _lightColorScheme.inverseSurface,
        contentTextStyle: TextStyle(
          color: _lightColorScheme.onInverseSurface,
          fontFamily: 'SF Pro',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static ThemeData get darkTheme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: _darkColorScheme,
      scaffoldBackgroundColor: _darkSurface,
      canvasColor: _darkSurface,
      fontFamily: 'SF Pro',
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _darkSurface,
        foregroundColor: _darkColorScheme.onSurface,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: _darkColorScheme.onSurface),
        titleTextStyle: TextStyle(
          color: _darkColorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          fontFamily: 'SF Pro',
        ),
      ),
      cardTheme: CardThemeData(
        color: _darkColorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _darkColorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: _darkColorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _darkSurfaceContainer,
        indicatorColor: _darkColorScheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected
                ? _darkColorScheme.primary
                : _darkColorScheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? _darkColorScheme.primary
                : _darkColorScheme.onSurfaceVariant,
          );
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _darkColorScheme.primary,
          foregroundColor: _darkColorScheme.onPrimary,
          disabledBackgroundColor: _darkColorScheme.outlineVariant,
          disabledForegroundColor: _darkColorScheme.onSurfaceVariant,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _darkColorScheme.primary,
          side: BorderSide(color: _darkColorScheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF111827),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _darkColorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _darkColorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _darkColorScheme.primary, width: 1.3),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _darkColorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _darkColorScheme.error, width: 1.2),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _darkColorScheme.primary;
          }
          return _darkColorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _darkColorScheme.primaryContainer;
          }
          return _darkColorScheme.outlineVariant;
        }),
      ),
      dividerTheme: DividerThemeData(
        color: _darkColorScheme.outlineVariant,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _darkColorScheme.surface,
        contentTextStyle: TextStyle(
          color: _darkColorScheme.onSurface,
          fontFamily: 'SF Pro',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
