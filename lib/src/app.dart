import 'package:flutter/material.dart';

import 'data/transit_repository.dart';
import 'screens/home_screen.dart';
import 'services/location_service.dart';

class VoieGoApp extends StatelessWidget {
  const VoieGoApp({
    super.key,
    required this.repository,
    required this.demoMode,
  });

  final TransitRepository repository;
  final bool demoMode;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF07182F);
    const cyan = Color(0xFF5FE3FF);
    final scheme = ColorScheme.fromSeed(
      seedColor: cyan,
      brightness: Brightness.dark,
      surface: const Color(0xFF102844),
    );

    return MaterialApp(
      title: 'VoieGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: background,
        fontFamily: 'Arial',
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 62,
            height: .9,
            fontWeight: FontWeight.w900,
          ),
          headlineLarge: TextStyle(
            fontSize: 30,
            height: 1.05,
            fontWeight: FontWeight.w800,
          ),
          headlineMedium: TextStyle(
            fontSize: 22,
            height: 1.1,
            fontWeight: FontWeight.w800,
          ),
          titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          bodyLarge: TextStyle(fontSize: 16, height: 1.35),
          bodyMedium: TextStyle(fontSize: 14, height: 1.35),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF183553),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
      ),
      home: HomeScreen(
        repository: repository,
        locationService: LocationService(),
        demoMode: demoMode,
      ),
    );
  }
}
