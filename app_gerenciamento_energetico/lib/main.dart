import 'package:flutter/material.dart';

import 'tema.dart';
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
      theme: temaIamp(),
      home: const TelaBusca(),
    );
  }
}
