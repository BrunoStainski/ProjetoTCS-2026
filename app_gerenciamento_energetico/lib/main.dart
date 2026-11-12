import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'idioma.dart';
import 'tema.dart';
import 'telas/boas_vindas.dart';
import 'telas/inicio.dart';

void main() {
  Api.wakeUp(); // servidor na nuvem pode estar dormindo: acorda enquanto a pessoa ve as boas-vindas
  runApp(const IampApp());
}

const welcomeRoute = '/boas-vindas';

class IampApp extends StatelessWidget {
  /// Abre com a tela de boas-vindas por cima das abas (os testes das abas podem pular).
  final bool showWelcome;

  const IampApp({super.key, this.showWelcome = true});

  @override
  Widget build(BuildContext context) {
    // trocar o idioma no menu troca o locale: os textos do Flutter (voltar, copiar...) acompanham
    // trocar o modo claro/escuro no menu troca o tema (o MaterialApp anima a troca das cores)
    return ListenableBuilder(
      listenable: Listenable.merge([language, lightMode]),
      builder: (context, _) => MaterialApp(
        title: 'Iamp',
        debugShowCheckedModeBanner: false,
        theme: iampTheme(light: lightMode.value),
        locale: language.value.locale,
        supportedLocales: [for (final i in Language.values) i.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // com '/boas-vindas' o Flutter monta '/' (as abas) e a boas-vindas por cima:
        // "Comece a economizar" so fecha a boas-vindas e as abas ja estao prontas
        initialRoute: showWelcome ? welcomeRoute : '/',
        routes: {'/': (_) => const StartScreen(), welcomeRoute: (_) => const WelcomeScreen(onOpen: true)},
      ),
    );
  }
}
