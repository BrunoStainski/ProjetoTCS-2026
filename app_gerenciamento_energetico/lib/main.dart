import 'package:flutter/material.dart';

import 'tema.dart';
import 'telas/inicio.dart';

void main() {
  runApp(const IampApp());
}

class IampApp extends StatelessWidget {
  const IampApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Iamp', debugShowCheckedModeBanner: false, theme: temaIamp(), home: const TelaInicio());
  }
}
