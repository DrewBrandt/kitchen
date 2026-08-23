import 'package:flutter/material.dart';

import 'data/pantry_store.dart';
import 'pages/home_page.dart';

class PantryApp extends StatefulWidget {
  const PantryApp({super.key});

  @override
  State<PantryApp> createState() => _PantryAppState();
}

class _PantryAppState extends State<PantryApp> {
  late final PantryStore store = PantryStore.demo();

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF5D7C50);
    return MaterialApp(
      title: 'Pantry',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F5EF),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Color(0xFFFFFDF7),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF10140F),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Color(0xFF191E17),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF10140F),
          surfaceTintColor: Colors.transparent,
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: Color(0xFF10140F),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Color(0xFF1C221A),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFF30382D)),
      ),
      home: PantryHomePage(store: store),
    );
  }
}
