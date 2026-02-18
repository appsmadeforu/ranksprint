import 'package:flutter/material.dart';

class AppTheme {
  static const primaryColor = Color(0xFF2F3E8F);

  static ThemeData lightTheme = ThemeData(
    scaffoldBackgroundColor: const Color(0xFFF5F6FA),
    primaryColor: primaryColor,
    fontFamily: "SF Pro",
    appBarTheme: const AppBarTheme(
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
    ),
  );
}
