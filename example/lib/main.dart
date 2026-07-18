import 'package:flutter/material.dart';
import 'package:glint_showcase/configurator.dart';

void main() => runApp(const ConfiguratorApp());

class ConfiguratorApp extends StatelessWidget {
  const ConfiguratorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffffb000),
        brightness: Brightness.dark,
      ),
    ),
    home: const ConfiguratorPage(),
  );
}
