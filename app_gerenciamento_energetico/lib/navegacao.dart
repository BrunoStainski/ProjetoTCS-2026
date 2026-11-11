// Navegacao do app: 3 abas na barra de baixo (Calcular, Minha casa, Economizar).
// Cada aba tem a propria pilha de telas: a barra continua visivel durante o calculo
// e trocar de aba nao perde o que a pessoa estava fazendo.

import 'package:flutter/widgets.dart';

enum AppTab { calculate, home, save }

/// Aba aberta agora. A barra de baixo escuta este valor.
final currentTab = ValueNotifier<AppTab>(AppTab.calculate);

/// Pilha de telas de cada aba.
final tabKeys = {for (final tab in AppTab.values) tab: GlobalKey<NavigatorState>()};

/// Volta a aba para a primeira tela dela.
void restartTab(AppTab tab) => tabKeys[tab]!.currentState?.popUntil((route) => route.isFirst);

/// Abre outra aba. `recomecar` volta a aba de destino para a primeira tela;
/// `closeCurrent` encerra o fluxo da aba de onde a pessoa saiu (ex.: depois de adicionar o aparelho).
void goTo(AppTab tab, {bool restart = false, bool closeCurrent = false}) {
  final origin = currentTab.value;
  if (restart) restartTab(tab);
  currentTab.value = tab;
  if (closeCurrent && origin != tab) restartTab(origin);
}
