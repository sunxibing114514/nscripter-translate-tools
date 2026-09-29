import 'package:flutter/material.dart';

import 'src/settings.dart';
import 'src/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(MyApp(settings: settings));
}

class MyApp extends StatefulWidget {
  final AppSettings settings;
  const MyApp({super.key, required this.settings});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.settings.themeMode;
  }

  void _onThemeChanged(ThemeMode m) {
    setState(() => _themeMode = m);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NScripter 翻译工具',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A6FE3)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A6FE3),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(settings: widget.settings, onThemeChanged: _onThemeChanged),
    );
  }
}