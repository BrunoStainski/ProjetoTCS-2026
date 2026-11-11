// Boas-vindas: primeira tela ao abrir o app (e pelo menu, em "Início").
// So a marca (icone grande com o nome ao lado) e o botao "Comece a economizar",
// que leva para o calculo (aba Calcular, etapa 1).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../idioma.dart';
import '../navegacao.dart';
import '../tema.dart';
import 'comum.dart';

class TelaBoasVindas extends StatelessWidget {
  /// Aberta junto com o app: o voltar do Android fecha o app (em vez de mostrar as abas por baixo).
  final bool aoAbrir;

  const TelaBoasVindas({super.key, this.aoAbrir = false});

  void _comecar(BuildContext context) {
    irPara(Aba.calcular, recomecar: true);
    Navigator.pop(context); // as abas ja estao embaixo desta tela
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return PopScope(
      canPop: !aoAbrir,
      onPopInvokedWithResult: (saiu, _) {
        if (!saiu) SystemNavigator.pop();
      },
      child: Scaffold(
        body: const SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(Espaco.g),
              child: MarcaIamp(tamanho: 120, tamanhoNome: 56),
            ),
          ),
        ),
        // acao principal embaixo, na zona do polegar (mesmo padrao do rodape das outras telas)
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: t.borda)),
          ),
          child: SafeArea(
            top: false,
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: t.larguraMaxima),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Espaco.m, Espaco.pm, Espaco.m, Espaco.m),
                  child: FilledButton.icon(
                    onPressed: () => _comecar(context),
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
