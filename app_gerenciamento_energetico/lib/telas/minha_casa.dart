import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../idioma.dart';
import '../navegacao.dart';
import '../tema.dart';
import 'casas.dart';
import 'comum.dart';
import 'dicas.dart';
import 'sugestoes.dart';

/// Aba "Minha casa": soma os aparelhos calculados, mostra o que mais pesa na conta
/// e compara a casa com casas parecidas (perfil de consumo, POST /classificar).
class MyHomeScreen extends StatefulWidget {
  const MyHomeScreen({super.key});

  @override
  State<MyHomeScreen> createState() => _MyHomeScreenState();
}

class _MyHomeScreenState extends State<MyHomeScreen> {
  bool _classifying = false;
  String? _profileError;
  final _profileKey = GlobalKey();

  Future<void> _classify() async {
    setState(() {
      _classifying = true;
      _profileError = null;
    });
    try {
      home.storeProfile(await Api.classify(home.residents, home.itemsForProfile()));
      // leva a tela ate o cartao do perfil, que aparece no fim da lista
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _profileKey.currentContext;
        if (target != null && target.mounted) {
          Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
        }
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _profileError = e.message);
    } finally {
      if (mounted) setState(() => _classifying = false);
    }
  }

  void _remove(ItemHome item) {
    final notices = ScaffoldMessenger.of(context);
    final from = home; // "Desfazer" devolve para esta casa, mesmo que a pessoa tenha trocado de casa
    final position = from.remove(item);
    notices
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(tr('${item.result.name} saiu da sua casa.', '${item.result.name} was removed from your home.')),
          duration: noticeDuration,
          persist: false,
          action: SnackBarAction(label: tr('Desfazer', 'Undo'), onPressed: () => from.reinsert(item, position)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: homes,
      builder: (context, _) => AppPage(
        title: tr('Minha casa', 'My home'),
        footer: _footer(),
        // casa aberta no topo: tocar leva para a lista de casas (trocar, criar, renomear, apagar)
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const HomeSwitcher(),
            const SizedBox(height: Spacing.m),
            Expanded(child: home.isEmpty ? const _EmptyHome() : _list()),
          ],
        ),
      ),
    );
  }

  /// Acao principal embaixo: calcular (casa vazia), ver o perfil e, depois do perfil, economizar.
  Widget _footer() {
    if (home.isEmpty) {
      return FilledButton.icon(
        onPressed: () => goTo(AppTab.calculate, restart: true),
        icon: const Icon(Icons.calculate_outlined),
        label: Text(tr('Calcular um aparelho', 'Calculate an appliance')),
      );
    }
    if (home.profile != null) {
      return FilledButton.icon(
        onPressed: () => goTo(AppTab.save),
        icon: const Icon(Icons.savings_outlined),
        label: Text(tr('Ver como economizar', 'See how to save')),
      );
    }
    return FilledButton.icon(
      onPressed: _classifying ? null : _classify,
      icon: _classifying
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.insights),
      label: Text(_classifying ? tr('Comparando...', 'Comparing...') : tr('Comparar com outras casas', 'Compare with other homes')),
    );
  }

  Widget _list() {
    final t = Iamp.de(context);
    final total = home.monthlyKwh;
    final n = home.totalAppliances;
    return ListView(
      children: [
        HighlightCard(
          title: tr('Sua conta de luz com estes aparelhos', 'Your electricity bill with these appliances'),
          value: home.monthlyCost,
          format: (v) => tr('${reais(v)} por mês', '${reais(v)} per month'),
          footer: tr(
            '${reais(home.yearlyCost)} por ano · $n ${n == 1 ? 'aparelho' : 'aparelhos'}',
            '${reais(home.yearlyCost)} per year · $n ${n == 1 ? 'appliance' : 'appliances'}',
          ),
        ),
        Text(
          tr('Consumo de ${number(total)} kWh por mês.', 'Uses ${number(total)} kWh per month.'),
          style: t.secondary,
          textAlign: TextAlign.center,
        ),
        if (home.mixedTariffs)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.p),
            child: NoticeList([
              tr(
                'Alguns aparelhos foram calculados com tarifas diferentes; o total soma os dois.',
                'Some appliances were calculated with different rates; the total adds them together.',
              ),
            ]),
          ),
        SectionTitle(tr('O que mais pesa na conta', 'What weighs most on the bill')),
        for (final item in home.byCost)
          _ItemCard(item, fraction: total > 0 ? item.monthlyKwh / total : 0, onRemove: () => _remove(item)),
        const SizedBox(height: Spacing.p),
        OutlinedButton.icon(
          onPressed: () => goTo(AppTab.calculate, restart: true),
          icon: const Icon(Icons.add),
          label: Text(tr('Adicionar outro aparelho', 'Add another appliance')),
        ),
        SectionTitle(tr('Quantas pessoas moram na casa?', 'How many people live in the home?')),
        Text(
          tr('Usamos para comparar a sua casa com casas parecidas.', 'We use it to compare your home with similar homes.'),
          style: t.secondary,
        ),
        const SizedBox(height: Spacing.p),
        _Counter(
          value: home.residents,
          label: home.residents == 1 ? tr('morador', 'resident') : tr('moradores', 'residents'),
          description: tr('moradores', 'residents'),
          minimum: 1,
          maximum: 20,
          onChange: home.changeResidents,
        ),
        if (_profileError != null) ErrorMessage(_profileError!, tryAgain: _classify),
        if (home.profile != null)
          Padding(
            key: _profileKey,
            padding: const EdgeInsets.only(top: Spacing.m),
            child: _ProfileCard(home.profile!, largest: home.byCost.first, total: total),
          ),
        const SizedBox(height: Spacing.g),
      ],
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_outlined, size: t.hugeIcon),
            const SizedBox(height: Spacing.m),
            Semantics(
              header: true,
              child: Text(tr('Sua casa ainda está vazia', 'Your home is still empty'), style: t.title, textAlign: TextAlign.center),
            ),
            const SizedBox(height: Spacing.p),
            Text(
              tr(
                'Calcule um aparelho e toque em "Adicionar à minha casa". '
                    'Com alguns aparelhos, o Iamp mostra o total da conta e onde dá para economizar.',
                'Calculate an appliance and tap "Add to my home". '
                    'With a few appliances, Iamp shows the bill total and where you can save.',
              ),
              textAlign: TextAlign.center,
              style: t.body,
            ),
          ],
        ),
      ),
    );
  }
}

/// Botoes - e + com o numero no meio. Cada botao diz ao leitor de tela o que muda.
class _Counter extends StatelessWidget {
  final int value;
  final String label;
  final String description;
  final int minimum;
  final int maximum;
  final void Function(int) onChange;

  const _Counter({
    required this.value,
    required this.label,
    required this.description,
    required this.minimum,
    required this.maximum,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Spacing.p,
      children: [
        IconButton.outlined(
          tooltip: tr('Diminuir $description', 'Decrease $description'),
          onPressed: value > minimum ? () => onChange(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        Semantics(
          liveRegion: true,
          child: Text('$value $label', style: t.number),
        ),
        IconButton.outlined(
          tooltip: tr('Aumentar $description', 'Increase $description'),
          onPressed: value < maximum ? () => onChange(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  final ItemHome item;
  final double fraction;
  final VoidCallback onRemove;

  const _ItemCard(this.item, {required this.fraction, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final r = item.result;
    final piece = '${number(fraction * 100, homes: 0)}%';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // o leitor de tela le o resumo inteiro de uma vez: nome, valor e parte da conta
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(categoryIcon(r.category), size: t.largeIcon),
                      const SizedBox(width: Spacing.pm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.name, style: t.strong, maxLines: 3, overflow: TextOverflow.ellipsis),
                            Text(
                              [categoryName(r.category), if (r.detail.isNotEmpty) r.detail].join(' · '),
                              style: t.secondary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.pm),
                  Text(tr('${reais(item.monthlyCost)} por mês', '${reais(item.monthlyCost)} per month'), style: t.averageValue),
                  Text(
                    tr('$piece da conta · ${number(item.monthlyKwh)} kWh', '$piece of the bill · ${number(item.monthlyKwh)} kWh'),
                    style: t.secondary,
                  ),
                  const SizedBox(height: Spacing.p),
                  ExcludeSemantics(child: PartBar(fraction, description: tr('$piece da conta', '$piece of the bill'))),
                ],
              ),
            ),
            const SizedBox(height: Spacing.pm),
            Text(tr('Quantidade', 'Quantity'), style: t.label),
            _Counter(
              value: item.quantity,
              label: item.quantity == 1 ? tr('unidade', 'unit') : tr('unidades', 'units'),
              description: tr('a quantidade de ${r.name}', 'the quantity of ${r.name}'),
              minimum: 1,
              maximum: 99,
              onChange: (q) => home.changeQuantity(item, q),
            ),
            const Divider(height: Spacing.g),
            Wrap(
              spacing: Spacing.p,
              runSpacing: Spacing.p,
              children: [
                if (!item.query.smallAppliance)
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SuggestionScreen(query: item.query, item: item, current: item.result),
                      ),
                    ),
                    icon: const Icon(Icons.trending_down),
                    label: Text(tr('Ver modelos que gastam menos', 'See models that use less')),
                  ),
                if (item.query.smallAppliance)
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => TipScreen(result: item.result))),
                    icon: const Icon(Icons.tips_and_updates_outlined),
                    label: Text(tr('Como gastar menos', 'How to spend less')),
                  ),
                Semantics(
                  label: tr('Remover ${r.name} da casa', 'Remove ${r.name} from the home'),
                  excludeSemantics: true,
                  button: true,
                  onTap: onRemove,
                  child: TextButton.icon(
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(tr('Remover', 'Remove')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final Classification c;
  final ItemHome largest;
  final double total;

  const _ProfileCard(this.c, {required this.largest, required this.total});

  static const _icons = {
    'Consciente': Icons.eco_outlined,
    'Moderado': Icons.balance,
    'Ineficiente': Icons.warning_amber_rounded,
  };

  static String? _explanation(String profile) => switch (profile) {
    'Consciente' => tr('A sua casa gasta pouco por pessoa.', 'Your home uses little per person.'),
    'Moderado' => tr('A sua casa gasta perto da média por pessoa.', 'Your home uses close to the average per person.'),
    'Ineficiente' => tr('A sua casa gasta mais que a média por pessoa.', 'Your home uses more than the average per person.'),
    _ => null,
  };

  static Map<String, String> get _fractionNames => {
    'frac_chuveiro': tr('Chuveiro', 'Electric shower'),
    'frac_ar': tr('Ar-condicionado', 'Air conditioner'),
    'frac_refrigerador': tr('Geladeira', 'Fridge'),
  };

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    // verde = bom, amarelo = neutro, vermelho = alerta (sempre com o nome e um icone diferente)
    final cor = switch (c.profile) {
      'Consciente' => t.savings,
      'Ineficiente' => t.alert,
      _ => t.highlight,
    };
    final above = c.percentageDifference > 0;
    // a tarifa media da casa transforma o kWh por morador em reais
    final meanTariff = total > 0 ? home.monthlyCost / total : 0.0;
    return Container(
      padding: const EdgeInsets.all(Spacing.g),
      decoration: t.highlightCard(cor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                Icon(_icons[c.profile] ?? Icons.insights, color: cor, size: t.largeIcon + 8),
                const SizedBox(width: Spacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Perfil da casa', 'Home profile'), style: t.label),
                      Text(profileName(c.profile), style: t.value.copyWith(color: cor)),
                      if (_explanation(c.profile) case final explanation?) Text(explanation, style: t.body),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.m),
          SideBySide(
            InfoCard(
              tr('Sua casa, por pessoa', 'Your home, per person'),
              tr('${reais(c.kwhPerResident * meanTariff)} por mês', '${reais(c.kwhPerResident * meanTariff)} per month'),
              detail: '${number(c.kwhPerResident, homes: 1)} kWh',
            ),
            InfoCard(
              tr('Casas parecidas, por pessoa', 'Similar homes, per person'),
              tr('cerca de ${reais(c.medianKwhPerResident * meanTariff)}', 'about ${reais(c.medianKwhPerResident * meanTariff)}'),
              detail: '${number(c.medianKwhPerResident, homes: 1)} kWh',
            ),
          ),
          const SizedBox(height: Spacing.pm),
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // a seta muda junto com a cor: acima da media = para cima
                Icon(above ? Icons.arrow_upward : Icons.arrow_downward, color: above ? t.alert : t.savings),
                const SizedBox(width: Spacing.p),
                Expanded(child: Text(_capitalizeFirst(c.textComparison), style: t.body)),
              ],
            ),
          ),
          SectionTitle(tr('Quanto cada um pesa no consumo', 'How much each one weighs in consumption')),
          for (final e in _fractionNames.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.pm),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${e.value}: ${number((c.fractions[e.key] ?? 0) * 100, homes: 0)}%', style: t.body),
                    const SizedBox(height: Spacing.pp),
                    ExcludeSemantics(child: PartBar(c.fractions[e.key] ?? 0, description: e.value)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Spacing.p),
          Text(
            tr(
              'O que mais pesa: ${largest.result.name} '
                  '(${number(total > 0 ? largest.monthlyKwh / total * 100 : 0, homes: 0)}% do consumo). '
                  'Veja no cartão dele se existe um modelo que gasta menos.',
              'What weighs most: ${largest.result.name} '
                  '(${number(total > 0 ? largest.monthlyKwh / total * 100 : 0, homes: 0)}% of consumption). '
                  'Check its card to see if there is a model that uses less.',
            ),
            style: t.body,
          ),
          const SizedBox(height: Spacing.m),
          NoticeList([
            c.notice,
            tr('O perfil considera só os aparelhos que você adicionou.', 'The profile only counts the appliances you added.'),
          ]),
        ],
      ),
    );
  }

  static String _capitalizeFirst(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
