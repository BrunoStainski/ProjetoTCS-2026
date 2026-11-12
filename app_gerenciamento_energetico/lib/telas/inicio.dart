// Casca do app: barra de baixo com 3 abas (icone + texto) e uma pilha de telas por aba.
// Calcular = escolher um aparelho e ver quanto custa; Minha casa = soma da conta;
// Economizar = plano do Eco-Coach.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../casa.dart';
import '../idioma.dart';
import '../navegacao.dart';
import 'busca.dart';
import 'eco_coach.dart';
import 'menu.dart';
import 'minha_casa.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  static const _screens = {
    AppTab.calculate: SearchScreen(),
    AppTab.home: MyHomeScreen(),
    AppTab.save: EcoCoachScreen(),
  };

  /// Voltar do Android: primeiro volta dentro da aba; na primeira tela de outra aba, vai para Calcular;
  /// na primeira tela de Calcular, fecha o app.
  void _back() {
    final stack = tabKeys[currentTab.value]!.currentState;
    if (stack != null && stack.canPop()) {
      stack.maybePop();
    } else if (currentTab.value != AppTab.calculate) {
      goTo(AppTab.calculate);
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (left, _) {
        if (!left) _back();
      },
      child: ValueListenableBuilder<AppTab>(
        valueListenable: currentTab,
        builder: (context, tab, _) => Scaffold(
          body: IndexedStack(
            index: tab.index,
            children: [
              for (final a in AppTab.values)
                // cada aba com o proprio messenger: o aviso aparece na tela da aba, acima do botao dela
                ScaffoldMessenger(
                  child: HeroControllerScope.none(
                    child: Navigator(
                      key: tabKeys[a],
                      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _screens[a]!),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: const _TabBar(),
          drawer: const MenuIamp(), // menu de acesso rapido (botao no topo da 1a tela de cada aba)
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar();

  @override
  Widget build(BuildContext context) {
    // a barra cresce com a fonte do sistema ate 1,5x; acima disso os rotulos ficariam cortados
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: Builder(
        builder: (context) {
          final height = MediaQuery.textScalerOf(context).scale(80).clamp(80.0, 104.0);
          return ListenableBuilder(
            listenable: Listenable.merge([currentTab, homes]),
            builder: (context, _) => NavigationBar(
              height: height,
              selectedIndex: currentTab.value.index,
              onDestinationSelected: (i) {
                final tab = AppTab.values[i];
                // tocar na aba que ja esta aberta volta para a primeira tela dela
                goTo(tab, restart: tab == currentTab.value);
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.calculate_outlined),
                  selectedIcon: const Icon(Icons.calculate),
                  label: tr('Calcular', 'Calculate'),
                  tooltip: tr('Calcular o gasto de um aparelho', 'Calculate what an appliance costs'),
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: !home.isEmpty,
                    label: Text('${home.totalAppliances}'),
                    child: const Icon(Icons.home_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: !home.isEmpty,
                    label: Text('${home.totalAppliances}'),
                    child: const Icon(Icons.home),
                  ),
                  label: tr('Minha casa', 'My home'),
                  tooltip: home.isEmpty
                      ? tr('Minha casa, nenhum aparelho', 'My home, no appliances')
                      : tr(
                          'Minha casa, ${home.totalAppliances} ${home.totalAppliances == 1 ? 'aparelho' : 'aparelhos'}',
                          'My home, ${home.totalAppliances} ${home.totalAppliances == 1 ? 'appliance' : 'appliances'}',
                        ),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.savings_outlined),
                  selectedIcon: const Icon(Icons.savings),
                  label: tr('Economizar', 'Save'),
                  tooltip: tr('Dicas para gastar menos', 'Tips to spend less'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
