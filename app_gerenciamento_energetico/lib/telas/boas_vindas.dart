// Boas-vindas: primeira tela ao abrir o app (e pelo menu, em "Início").
// So a marca (icone grande com o nome ao lado) e o botao "Comece a economizar",
// que leva para o calculo (aba Calcular, etapa 1).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../idioma.dart';
import '../navegacao.dart';
import '../tema.dart';
import 'comum.dart';

class WelcomeScreen extends StatelessWidget {
  /// Aberta junto com o app: o voltar do Android fecha o app (em vez de mostrar as abas por baixo).
  final bool onOpen;

  const WelcomeScreen({super.key, this.onOpen = false});

  void _start(BuildContext context) {
    goTo(AppTab.calculate, restart: true);
    Navigator.pop(context); // as abas ja estao embaixo desta tela
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return PopScope(
      canPop: !onOpen,
      onPopInvokedWithResult: (left, _) {
        if (!left) SystemNavigator.pop();
      },
      child: Scaffold(
        body: const SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(Spacing.g),
              child: IampBrand(size: 120, nameSize: 56),
            ),
          ),
        ),
        // acao principal embaixo, na zona do polegar (mesmo padrao do rodape das outras telas)
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: t.border)),
          ),
          child: SafeArea(
            top: false,
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: t.maxWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.m, Spacing.pm, Spacing.m, Spacing.m),
                  child: FilledButton.icon(
                    onPressed: () => _start(context),
                    icon: const Icon(Icons.bolt),
                    label: Text(tr('Comece a economizar', 'Start saving')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
