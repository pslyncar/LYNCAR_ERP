import 'package:flutter/material.dart';

ThemeData buildPedeOnTheme() {
  const navy = Color(0xFF0C2538);
  const teal = Color(0xFF087681);
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: teal,
      primary: teal,
      secondary: navy,
    ),
    scaffoldBackgroundColor: const Color(0xFFF5F7FA),
    cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
