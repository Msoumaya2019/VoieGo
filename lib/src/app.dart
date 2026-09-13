import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/transit_repository.dart';
import 'screens/home_screen.dart';
import 'services/location_service.dart';
import 'services/push_notification_service.dart';

class VoieGoApp extends StatefulWidget {
  const VoieGoApp({
    super.key,
    required this.repository,
    required this.demoMode,
    this.pushNotifications,
  });

  final TransitRepository repository;
  final bool demoMode;
  final PushNotificationService? pushNotifications;

  @override
  State<VoieGoApp> createState() => _VoieGoAppState();
}

class _VoieGoAppState extends State<VoieGoApp> {
  bool _darkMode = true;
  late final PushNotificationService _pushNotifications;
  late final bool _ownsPushNotifications;

  @override
  void initState() {
    super.initState();
    _ownsPushNotifications = widget.pushNotifications == null;
    _pushNotifications =
        widget.pushNotifications ?? PushNotificationService();
    _loadTheme();
  }

  @override
  void dispose() {
    if (_ownsPushNotifications) _pushNotifications.dispose();
    super.dispose();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _darkMode = prefs.getBool('dark_mode') ?? true);
  }

  Future<void> _setDarkMode(bool value) async {
    setState(() => _darkMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoieGo',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      home: HomeScreen(
        repository: widget.repository,
        locationService: LocationService(),
        demoMode: widget.demoMode,
        darkMode: _darkMode,
        onDarkModeChanged: _setDarkMode,
        pushNotifications: _pushNotifications,
      ),
    );
  }
}

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF20C8E8),
    brightness: brightness,
    surface: dark ? const Color(0xFF102844) : Colors.white,
  ).copyWith(
    surfaceContainerHigh: dark
        ? const Color(0xFF173553)
        : const Color(0xFFE7F0F8),
    onSurfaceVariant: dark
        ? const Color(0xFFC4D4EE)
        : const Color(0xFF516478),
    outline: dark ? const Color(0xFF28496D) : const Color(0xFFB5C7D8),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF07182F)
        : const Color(0xFFF3F7FB),
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
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.surfaceContainerHigh,
      contentTextStyle: TextStyle(color: scheme.onSurface),
    ),
  );
}
