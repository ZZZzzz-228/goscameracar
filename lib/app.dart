import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/pass_repository.dart';
import 'screens/home_screen.dart';
import 'screens/session_screen.dart';

const ink = Color(0xFF172B35);
const muted = Color(0xFF5E6E75);
const canvas = Color(0xFFF4F5F1);
const accent = Color(0xFFE7BE67);

class PassApp extends StatelessWidget {
  const PassApp({super.key, this.repository});

  final PassRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Автопропуск',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: ink,
        ).copyWith(primary: ink, surface: canvas),
        scaffoldBackgroundColor: canvas,
        appBarTheme: const AppBarTheme(
          backgroundColor: canvas,
          foregroundColor: ink,
          scrolledUnderElevation: 0,
          centerTitle: false,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 36,
            height: 1.12,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
          titleLarge: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
          bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: ink),
          bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: muted),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.all(20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: repository == null
          ? const SessionScreen()
          : HomeScreen(repository: repository!),
    );
  }
}
