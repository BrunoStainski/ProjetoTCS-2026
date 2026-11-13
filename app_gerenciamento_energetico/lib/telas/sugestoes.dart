import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../idioma.dart';
import '../tema.dart';
import 'comparar.dart';
import 'comum.dart';

/// Modelos equivalentes que gastam menos (POST /sugestoes), com o mesmo uso e a mesma tarifa.
/// item: quando veio de "Minha casa", permite trocar o aparelho la.
class SuggestionScreen extends StatefulWidget {
  final Query query;
  final ItemHome? item;
  final Result? current;

  const SuggestionScreen({super.key, required this.query, this.item, this.current});

  @override
  State<SuggestionScreen> createState() => _SuggestionScreenState();
}

class _SuggestionScreenState extends State<SuggestionScreen> {
  late Future<Suggestions> _suggestions;

  @override
  void initState() {
    super.initState();
    _suggestions = _search();
  }

  Future<Suggestions> _search() async {
    if (widget.query.estimated) return Api.estimatedSuggestions(widget.current!, widget.query.toApi());
    // casa salva cujo modelo saiu do catalogo (a API devolve o item com id 0): sem ele nao ha com o que comparar
    if (widget.query.appliance.id <= 0) {
      throw ApiError(
        tr(
          'Este modelo não está mais no catálogo do Inmetro, então não dá para comparar. Calcule de novo '
              'escolhendo o modelo para ver os que gastam menos.',
          'This model is no longer in Inmetro\'s catalog, so it cannot be compared. Calculate again choosing '
              'the model to see the ones that use less.',
        ),
      );
    }
    return Api.suggestions(widget.query.appliance.id, widget.query.toApi());
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final appliance = widget.query.appliance;
    final name = widget.current?.name ?? appliance.name;
    return AppPage(
      title: tr('Gastar menos', 'Spend less'),
      child: FutureBuilder<Suggestions>(
        future: _suggestions,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Loading(text: tr('Procurando modelos que gastam menos...', 'Looking for models that use less...'));
          }
          if (snap.hasError) {
            return ErrorMessage(
              snap.error.toString(),
              tryAgain: () => setState(() {
                _suggestions = _search();
              }),
            );
          }
          final s = snap.data!;
          return ListView(
            children: [
              QuestionHeader(
                tr('Modelos parecidos que gastam menos', 'Similar models that use less'),
                help: tr(
                  'Mesmo tamanho, mesmo uso e a mesma tarifa do seu aparelho. Toque num modelo para comparar.',
                  'Same size, same use and the same rate as your appliance. Tap a model to compare.',
                ),
              ),
              MergeSemantics(
                child: Card(
                  child: ListTile(
                    leading: Icon(categoryIcon(appliance.category)),
                    title: Text(tr('Seu aparelho: $name', 'Your appliance: $name')),
                    subtitle: Text(
                      tr(
                        '${reais(s.currentCost)} por mês · ${number(s.currentKwh)} kWh',
                        '${reais(s.currentCost)} per month · ${number(s.currentKwh)} kWh',
                      ),
                    ),
                  ),
                ),
              ),
              if (s.criterion != null) ...[
                SectionTitle(tr('Comparando com modelos de', 'Comparing with models of')),
                Text(s.criterion!, style: t.body),
              ],
              const SizedBox(height: Spacing.pm),
              if (s.message != null)
                Card(
                  color: t.highlightBackground,
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.m),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.tips_and_updates_outlined),
                        const SizedBox(width: Spacing.pm),
                        Expanded(child: Text(s.message!, style: t.body)),
                      ],
                    ),
                  ),
                ),
              for (final suggested in s.suggestions) _SuggestionCard(suggested, onTap: () => _open(suggested)),
              if (s.discardedSuspects > 0) ...[
                const SizedBox(height: Spacing.p),
                NoticeList([
                  tr(
                    '${s.discardedSuspects} modelo(s) com consumo irreal (erro do Inmetro) ficaram de fora.',
                    '${s.discardedSuspects} model(s) with unrealistic consumption (Inmetro data error) were left out.',
                  ),
                ]),
              ],
            ],
          );
        },
      ),
    );
  }

  void _open(SuggestedAppliance suggested) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CompareScreen(query: widget.query, suggested: suggested, item: widget.item, current: widget.current),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final SuggestedAppliance s;
  final VoidCallback onTap;

  const _SuggestionCard(this.s, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final a = s.appliance;
    final savings = tr('${reais(s.monthlySavings)} a menos por mês', '${reais(s.monthlySavings)} less per month');
    return MergeSemantics(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.m),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name, style: t.strong),
                      if (a.detail.isNotEmpty || s.kind.isNotEmpty)
                        Text([if (a.detail.isNotEmpty) a.detail, if (s.kind.isNotEmpty) s.kind].join(' · '),
                            style: t.secondary),
                      const SizedBox(height: Spacing.p),
                      // economia em verde e escrita por extenso ("a menos"), nao so pela cor
                      Text(savings, style: t.averageValue.copyWith(color: t.savings)),
                      const SizedBox(height: Spacing.pp),
                      Wrap(
                        spacing: Spacing.p,
                        runSpacing: Spacing.pp,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: Spacing.p, vertical: 2),
                            decoration: t.badge(t.savings),
                            child: Text(
                              tr('${number(s.percentageSavings, homes: 0)}% menos', '${number(s.percentageSavings, homes: 0)}% less'),
                              style: t.label.copyWith(color: t.savings),
                            ),
                          ),
                          Text(tr('Gasta ${reais(s.monthlyCost)} por mês', 'Costs ${reais(s.monthlyCost)} per month'), style: t.secondary),
                        ],
                      ),
                      Text(tr('${number(s.monthlyKwh)} kWh por mês', '${number(s.monthlyKwh)} kWh per month'), style: t.secondary),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.p),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
