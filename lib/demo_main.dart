import 'package:flutter/material.dart';

import 'app.dart';
import 'data/pantry_store.dart';
import 'pages/home_page.dart';

/// Local, Firebase-free preview used for visual QA of the Pantry UI.
void main() => runApp(const PantryDemoApp());

class PantryDemoApp extends StatelessWidget {
  const PantryDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pantry UI preview',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.dark,
    theme: pantryTheme(Brightness.light),
    darkTheme: pantryTheme(Brightness.dark),
    home: PantryHomePage(store: PantryStore.demo(), onSignOut: () {}),
  );
}
