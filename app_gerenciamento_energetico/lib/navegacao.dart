// Navegacao do app: 3 abas na barra de baixo (Calcular, Minha casa, Economizar).
// Cada aba tem a propria pilha de telas: a barra continua visivel durante o calculo
// e trocar de aba nao perde o que a pessoa estava fazendo.

import 'package:flutter/widgets.dart';

enum Aba { calcular, casa, economizar }

/// Aba aberta agora. A barra de baixo escuta este valor.
final abaAtual = ValueNotifier<Aba>(Aba.calcular);

/// Pilha de telas de cada aba.
final chavesDasAbas = {for (final aba in Aba.values) aba: GlobalKey<NavigatorState>()};

/// Volta a aba para a primeira tela dela.
void recomecarAba(Aba aba) => chavesDasAbas[aba]!.currentState?.popUntil((rota) => rota.isFirst);

/// Abre outra aba. `recomecar` volta a aba de destino para a primeira tela;
/// `fecharAtual` encerra o fluxo da aba de onde a pessoa saiu (ex.: depois de adicionar o aparelho).
void irPara(Aba aba, {bool recomecar = false, bool fecharAtual = false}) {
  final origem = abaAtual.value;
  if (recomecar) recomecarAba(aba);
  abaAtual.value = aba;
  if (fecharAtual && origem != aba) recomecarAba(origem);
}
