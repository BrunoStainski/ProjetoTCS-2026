// Casca do app: barra de baixo com 3 abas (icone + texto) e uma pilha de telas por aba.
// Calcular = escolher um aparelho e ver quanto custa; Minha casa = soma da conta;
// Economizar = plano do Eco-Coach.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../casa.dart';
import '../navegacao.dart';
import 'busca.dart';
import 'eco_coach.dart';
import 'minha_casa.dart';

class TelaInicio extends StatelessWidget {
  const TelaInicio({super.key});

  static const _telas = {
    Aba.calcular: TelaBusca(),
    Aba.casa: TelaMinhaCasa(),
    Aba.economizar: TelaEcoCoach(),
  };

  /// Voltar do Android: primeiro volta dentro da aba; na primeira tela de outra aba, vai para Calcular;
  /// na primeira tela de Calcular, fecha o app.
  void _voltar() {
    final pilha = chavesDasAbas[abaAtual.value]!.currentState;
    if (pilha != null && pilha.canPop()) {
      pilha.maybePop();
    } else if (abaAtual.value != Aba.calcular) {
      irPara(Aba.calcular);
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (saiu, _) {
        if (!saiu) _voltar();
      },
      child: ValueListenableBuilder<Aba>(
        valueListenable: abaAtual,
        builder: (context, aba, _) => Scaffold(
          body: IndexedStack(
            index: aba.index,
            children: [
              for (final a in Aba.values)
                // cada aba com o proprio messenger: o aviso aparece na tela da aba, acima do botao dela
                ScaffoldMessenger(
                  child: HeroControllerScope.none(
                    child: Navigator(
                      key: chavesDasAbas[a],
                      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _telas[a]!),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: const _BarraDeAbas(),
        ),
      ),
    );
  }
}

class _BarraDeAbas extends StatelessWidget {
  const _BarraDeAbas();

  @override
  Widget build(BuildContext context) {
    // a barra cresce com a fonte do sistema ate 1,5x; acima disso os rotulos ficariam cortados
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: Builder(
        builder: (context) {
          final altura = MediaQuery.textScalerOf(context).scale(80).clamp(80.0, 104.0);
          return ListenableBuilder(
            listenable: Listenable.merge([abaAtual, casa]),
            builder: (context, _) => NavigationBar(
              height: altura,
              selectedIndex: abaAtual.value.index,
              onDestinationSelected: (i) {
                final aba = Aba.values[i];
                // tocar na aba que ja esta aberta volta para a primeira tela dela
                irPara(aba, recomecar: aba == abaAtual.value);
              },
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.calculate_outlined),
                  selectedIcon: Icon(Icons.calculate),
                  label: 'Calcular',
                  tooltip: 'Calcular o gasto de um aparelho',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: !casa.vazia,
                    label: Text('${casa.totalAparelhos}'),
                    child: const Icon(Icons.home_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: !casa.vazia,
                    label: Text('${casa.totalAparelhos}'),
                    child: const Icon(Icons.home),
                  ),
                  label: 'Minha casa',
                  tooltip: casa.vazia
                      ? 'Minha casa, nenhum aparelho'
                      : 'Minha casa, ${casa.totalAparelhos} ${casa.totalAparelhos == 1 ? 'aparelho' : 'aparelhos'}',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.savings_outlined),
                  selectedIcon: Icon(Icons.savings),
                  label: 'Economizar',
                  tooltip: 'Dicas para gastar menos',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
