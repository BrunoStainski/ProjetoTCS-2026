// Menu de acesso rapido (gaveta lateral). Abre pelo botao de menu no topo da primeira tela de cada
// aba ou arrastando da borda esquerda. Topo: a marca (icone com contorno amarelo e o nome).
// Itens feitos com ListTile (e nao NavigationDrawerDestination) porque o texto precisa quebrar a
// linha com a fonte do sistema grande (o app aceita ate 2x).

import 'package:flutter/material.dart';

import '../casa.dart';
import '../navegacao.dart';
import '../tema.dart';
import 'boas_vindas.dart';
import 'comum.dart';
import 'estimar.dart';

enum _Item { inicio, calcular, estimar, casa, economizar }

class MenuIamp extends StatelessWidget {
  const MenuIamp({super.key});

  static const _itemDaAba = {Aba.calcular: _Item.calcular, Aba.casa: _Item.casa, Aba.economizar: _Item.economizar};

  void _escolher(BuildContext context, _Item item) {
    final navegador = Navigator.of(context); // o navegador de fora das abas
    Scaffold.of(context).closeDrawer();
    // como na barra de baixo: tocar na aba que ja esta aberta volta para a primeira tela dela
    void abrir(Aba aba) => irPara(aba, recomecar: aba == abaAtual.value);
    switch (item) {
      case _Item.inicio:
        navegador.push(
          PageRouteBuilder(
            pageBuilder: (_, _, _) => const TelaBoasVindas(),
            transitionsBuilder: (_, animacao, _, filho) => FadeTransition(opacity: animacao, child: filho),
          ),
        );
      case _Item.calcular:
        abrir(Aba.calcular);
      case _Item.estimar:
        irPara(Aba.calcular, recomecar: true);
        chavesDasAbas[Aba.calcular]!.currentState?.push(MaterialPageRoute(builder: (_) => const TelaEstimar()));
      case _Item.casa:
        abrir(Aba.casa);
      case _Item.economizar:
        abrir(Aba.economizar);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Drawer(
      backgroundColor: t.superficie,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([abaAtual, casa]),
          builder: (context, _) {
            final aberto = _itemDaAba[abaAtual.value];
            Widget item(_Item i, IconData icone, IconData iconeAberto, String texto, {Widget Function(Widget)? marca}) {
              final selecionado = i == aberto;
              final simbolo = Icon(selecionado ? iconeAberto : icone);
              return _ItemMenu(
                icone: marca == null ? simbolo : marca(simbolo),
                texto: texto,
                selecionado: selecionado,
                aoTocar: () => _escolher(context, i),
              );
            }

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: Espaco.pm),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(Espaco.m, Espaco.g, Espaco.m, Espaco.m),
                  child: Align(alignment: Alignment.centerLeft, child: MarcaIamp()),
                ),
                const Divider(indent: Espaco.m, endIndent: Espaco.m),
                const SizedBox(height: Espaco.p),
                item(_Item.inicio, Icons.bolt_outlined, Icons.bolt, 'Início'),
                item(_Item.calcular, Icons.calculate_outlined, Icons.calculate, 'Calcular um aparelho'),
                item(_Item.estimar, Icons.tune_outlined, Icons.tune, 'Estimar um aparelho'),
                item(
                  _Item.casa,
                  Icons.home_outlined,
                  Icons.home,
                  'Minha casa',
                  marca: (simbolo) => Badge(
                    isLabelVisible: !casa.vazia,
                    label: Text('${casa.totalAparelhos}'),
                    child: simbolo,
                  ),
                ),
                item(_Item.economizar, Icons.savings_outlined, Icons.savings, 'Economizar'),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Item do menu: faixa amarela com texto e icone pretos quando e a aba aberta; senao, icone amarelo.
class _ItemMenu extends StatelessWidget {
  final Widget icone;
  final String texto;
  final bool selecionado;
  final VoidCallback aoTocar;

  const _ItemMenu({required this.icone, required this.texto, required this.selecionado, required this.aoTocar});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espaco.pp),
      child: ListTile(
        leading: icone,
        title: Text(texto, style: selecionado ? t.forte.copyWith(color: Cores.preto) : t.corpo),
        selected: selecionado,
        selectedTileColor: t.destaque,
        selectedColor: Cores.preto,
        iconColor: t.destaque,
        minTileHeight: 56,
        shape: const StadiumBorder(),
        onTap: aoTocar,
      ),
    );
  }
}
