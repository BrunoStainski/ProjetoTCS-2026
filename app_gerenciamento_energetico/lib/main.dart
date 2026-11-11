import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'idioma.dart';
import 'tema.dart';
import 'telas/boas_vindas.dart';
import 'telas/inicio.dart';

void main() {
  runApp(const IampApp());
}

const rotaBoasVindas = '/boas-vindas';

class IampApp extends StatelessWidget {
  /// Abre com a tela de boas-vindas por cima das abas (os testes das abas podem pular).
  final bool boasVindas;

  const IampApp({super.key, this.boasVindas = true});

  @override
  Widget build(BuildContext context) {
    // trocar o idioma no menu troca o locale: os textos do Flutter (voltar, copiar...) acompanham
    return ValueListenableBuilder<Idioma>(
      valueListenable: idioma,
      builder: (context, atual, _) => MaterialApp(
        title: 'Iamp',
        debugShowCheckedModeBanner: false,
        theme: temaIamp(),
        locale: atual.locale,
        supportedLocales: [for (final i in Idioma.values) i.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // com '/boas-vindas' o Flutter monta '/' (as abas) e a boas-vindas por cima:
        // "Comece a economizar" so fecha a boas-vindas e as abas ja estao prontas
        initialRoute: boasVindas ? rotaBoasVindas : '/',
        routes: {'/': (_) => const TelaInicio(), rotaBoasVindas: (_) => const TelaBoasVindas(aoAbrir: true)},
      ),
    );
  }
}
