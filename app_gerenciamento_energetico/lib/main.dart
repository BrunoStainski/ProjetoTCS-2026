import 'package:flutter/material.dart';

import 'telas/busca.dart';

void main() {
  runApp(const IampApp());
}

class IampApp extends StatelessWidget {
  const IampApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iamp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: const TelaBusca(),
    );
  }
}
