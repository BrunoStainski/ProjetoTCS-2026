// Menu de acesso rapido (gaveta lateral). Abre pelo botao de menu no topo da primeira tela de cada
// aba ou arrastando da borda esquerda. Topo: a marca (icone com contorno amarelo e o nome).
// Itens feitos com ListTile (e nao NavigationDrawerDestination) porque o texto precisa quebrar a
// linha com a fonte do sistema grande (o app aceita ate 2x).
// No fim, o idioma: o app sempre abre em portugues e aqui troca para o ingles (apresentacao para
// estrangeiros). O titulo da secao e os nomes dos idiomas aparecem nas duas linguas, para quem nao
// entende o idioma atual tambem achar a opcao.

import 'package:flutter/material.dart';

import '../casa.dart';
import '../idioma.dart';
import '../navegacao.dart';
import '../tema.dart';
import 'boas_vindas.dart';
import 'comum.dart';
import 'estimar.dart';

enum _Item { start, calculate, estimate, home, save }

class MenuIamp extends StatelessWidget {
  const MenuIamp({super.key});

  static const _tabItem = {AppTab.calculate: _Item.calculate, AppTab.home: _Item.home, AppTab.save: _Item.save};

  void _choose(BuildContext context, _Item item) {
    final navigator = Navigator.of(context); // o navegador de fora das abas
    Scaffold.of(context).closeDrawer();
    // como na barra de baixo: tocar na aba que ja esta aberta volta para a primeira tela dela
    void open(AppTab tab) => goTo(tab, restart: tab == currentTab.value);
    switch (item) {
      case _Item.start:
        navigator.push(
          PageRouteBuilder(
            pageBuilder: (_, _, _) => const WelcomeScreen(),
            transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
          ),
        );
      case _Item.calculate:
        open(AppTab.calculate);
      case _Item.estimate:
        goTo(AppTab.calculate, restart: true);
        tabKeys[AppTab.calculate]!.currentState?.push(MaterialPageRoute(builder: (_) => const EstimateScreen()));
      case _Item.home:
        open(AppTab.home);
      case _Item.save:
        open(AppTab.save);
    }
  }

  void _swapLanguage(BuildContext context, Language rewritten) {
    Scaffold.of(context).closeDrawer();
    if (rewritten == language.value) return;
    // telas abertas guardam respostas da API no idioma anterior (resultado, sugestoes...):
    // cada aba volta para a primeira tela e o perfil e o plano sao pedidos de novo. A casa continua.
    for (final tab in AppTab.values) {
      restartTab(tab);
    }
    home.forgetApiTexts();
    changeLanguage(rewritten);
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Drawer(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([currentTab, home]),
          builder: (context, _) {
            final openItem = _tabItem[currentTab.value];
            Widget item(_Item i, IconData icon, IconData openIcon, String text, {Widget Function(Widget)? brand}) {
              final selected = i == openItem;
              final symbol = Icon(selected ? openIcon : icon);
              return _ItemMenu(
                icon: brand == null ? symbol : brand(symbol),
                text: text,
                selected: selected,
                onTap: () => _choose(context, i),
              );
            }

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.pm),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(Spacing.m, Spacing.g, Spacing.m, Spacing.m),
                  child: Align(alignment: Alignment.centerLeft, child: IampBrand()),
                ),
                const Divider(indent: Spacing.m, endIndent: Spacing.m),
                const SizedBox(height: Spacing.p),
                item(_Item.start, Icons.bolt_outlined, Icons.bolt, tr('Início', 'Start')),
                item(_Item.calculate, Icons.calculate_outlined, Icons.calculate, tr('Calcular um aparelho', 'Calculate an appliance')),
                item(_Item.estimate, Icons.tune_outlined, Icons.tune, tr('Estimar um aparelho', 'Estimate an appliance')),
                item(
                  _Item.home,
                  Icons.home_outlined,
                  Icons.home,
                  tr('Minha casa', 'My home'),
                  brand: (symbol) => Badge(
                    isLabelVisible: !home.isEmpty,
                    label: Text('${home.totalAppliances}'),
                    child: symbol,
                  ),
                ),
                item(_Item.save, Icons.savings_outlined, Icons.savings, tr('Economizar', 'Save energy')),
                const SizedBox(height: Spacing.p),
                const Divider(indent: Spacing.m, endIndent: Spacing.m),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.m, Spacing.pm, Spacing.m, Spacing.pp),
                  child: Semantics(
                    header: true,
                    child: Row(
                      children: [
                        Icon(Icons.language, color: t.highlight),
                        const SizedBox(width: Spacing.pm),
                        Expanded(child: Text('Idioma · Language', style: t.label)),
                      ],
                    ),
                  ),
                ),
                for (final i in Language.values)
                  _ItemLanguage(i, chosen: i == language.value, onTap: () => _swapLanguage(context, i)),
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
  final Widget icon;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _ItemMenu({required this.icon, required this.text, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.pp),
      child: ListTile(
        leading: icon,
        title: Text(text, style: selected ? t.strong.copyWith(color: AppColors.black) : t.body),
        selected: selected,
        selectedTileColor: t.highlight,
        selectedColor: AppColors.black,
        iconColor: t.highlight,
        minTileHeight: 56,
        shape: const StadiumBorder(),
        onTap: onTap,
      ),
    );
  }
}

/// Idioma no menu: escolha entre opcoes (como um botao de radio). O escolhido tem o sinal de "certo"
/// e o nome em negrito; a faixa amarela fica so para a aba aberta.
class _ItemLanguage extends StatelessWidget {
  final Language option;
  final bool chosen;
  final VoidCallback onTap;

  const _ItemLanguage(this.option, {required this.chosen, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    // o leitor de tela anuncia "selecionado" e que e uma escolha entre opcoes (como um botao de radio)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.pp),
      child: MergeSemantics(
        child: Semantics(
          inMutuallyExclusiveGroup: true,
          child: ListTile(
            leading: Icon(chosen ? Icons.check_circle : Icons.circle_outlined),
            title: Text(option.name, style: chosen ? t.strong : t.body),
            selected: chosen,
            iconColor: t.highlight,
            selectedColor: t.highlight,
            minTileHeight: 56,
            shape: const StadiumBorder(),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
