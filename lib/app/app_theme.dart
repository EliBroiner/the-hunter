import 'package:flutter/material.dart';

/// ערכת צבעים כהה
ThemeData get appThemeDark => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6366F1),
        brightness: Brightness.dark,
        surface: const Color(0xFF0F0F23),
        primary: const Color(0xFF818CF8),
        secondary: const Color(0xFF34D399),
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF0F0F23),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E1E3F),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: const Color(0xFF1E1E3F),
        headerBackgroundColor: const Color(0xFF6366F1),
        headerForegroundColor: Colors.white,
        headerHeadlineStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        headerHelpStyle: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
        yearStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        dayForegroundColor: WidgetStateProperty.all(Colors.white),
        yearForegroundColor: WidgetStateProperty.all(Colors.white),
        surfaceTintColor: Colors.transparent,
        rangePickerBackgroundColor: const Color(0xFF1E1E3F),
        rangeSelectionBackgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.3),
      ),
    );

/// ערכת צבעים בהירה
ThemeData get appThemeLight => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6366F1),
        brightness: Brightness.light,
        surface: const Color(0xFFFAFAFC),
        onSurface: const Color(0xFF1E293B),
        primary: const Color(0xFF6366F1),
        onPrimary: Colors.white,
        secondary: const Color(0xFF10B981),
        onSecondary: Colors.white,
        surfaceContainerHighest: const Color(0xFFF8FAFC),
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF1F5F9),
        elevation: 0,
        centerTitle: true,
        foregroundColor: Color(0xFF1E293B),
        iconTheme: IconThemeData(color: Color(0xFF6366F1)),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFFAFAFC),
        elevation: 0,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: const Color(0xFFFAFAFC),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: Color(0xFF1E293B),
        iconColor: Color(0xFF6366F1),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Color(0xFF1E293B)),
        bodyMedium: TextStyle(color: Color(0xFF475569)),
        titleLarge: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: const Color(0xFFF8FAFC),
        headerBackgroundColor: const Color(0xFF6366F1),
        headerForegroundColor: Colors.white,
        headerHeadlineStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        headerHelpStyle: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
        yearStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        surfaceTintColor: Colors.transparent,
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          if (states.contains(WidgetState.disabled)) return const Color(0xFFCBD5E1);
          return const Color(0xFF1E293B);
        }),
        yearForegroundColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
        weekdayStyle: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        dayStyle: const TextStyle(color: Color(0xFF1E293B)),
        todayForegroundColor: WidgetStateProperty.all(const Color(0xFF6366F1)),
        todayBackgroundColor: WidgetStateProperty.all(Colors.transparent),
        rangePickerHeaderForegroundColor: Colors.white,
        rangePickerHeaderBackgroundColor: const Color(0xFF6366F1),
        rangePickerBackgroundColor: const Color(0xFFF8FAFC),
        rangeSelectionBackgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
        dividerColor: const Color(0xFFE2E8F0),
        inputDecorationTheme: const InputDecorationTheme(
          labelStyle: TextStyle(color: Color(0xFF64748B)),
          hintStyle: TextStyle(color: Color(0xFF94A3B8)),
        ),
        cancelButtonStyle: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(const Color(0xFF64748B)),
        ),
        confirmButtonStyle: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(const Color(0xFF6366F1)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFFFAFAFC),
        titleTextStyle: const TextStyle(color: Color(0xFF1E293B), fontSize: 20, fontWeight: FontWeight.bold),
        contentTextStyle: const TextStyle(color: Color(0xFF475569)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1E293B),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF1F5F9),
        labelStyle: const TextStyle(color: Color(0xFF475569)),
        selectedColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFFFAFAFC),
      ),
    );
