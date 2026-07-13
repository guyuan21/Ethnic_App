import 'dart:async';

import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'services/legacy_tts_cleanup_service.dart';

void main() {
  runApp(const EthnicCultureApp());
  unawaited(LegacyTtsCleanupService.removeCopiedOfflineModel());
}

class EthnicCultureApp extends StatelessWidget {
  const EthnicCultureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '民族文化识别助手',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB84A39),
          primary: const Color(0xFFB84A39),
          secondary: const Color(0xFF2F6F73),
          surface: const Color(0xFFFFFAF7),
        ),
        scaffoldBackgroundColor: const Color(0xFFFFFAF7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFE8DF),
          foregroundColor: Color(0xFF241815),
          elevation: 0,
          centerTitle: false,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
