import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../idioma.dart';
import '../navegacao.dart';
import '../tema.dart';
import 'comum.dart';
import 'dicas.dart';
import 'sugestoes.dart';

/// Etapa 6: chama POST /calcular e mostra quanto o aparelho custa em reais.
/// Daqui a pessoa adiciona o aparelho na casa ou procura um modelo mais economico.
class ResultScreen extends StatefulWidget {
  final Query query;

  const ResultScreen({super.key, required this.query});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late Future<Result> _result;
  bool _added = false;

  @override
  void initState() {
    super.initState();
    _result = _calculate();
  }

  Future<Result> _calculate() {
    final c = widget.query;
    return c.estimated
        ? Api.estimate(c.estimation!.route, c.estimateBody())
        : Api.calculate(c.appliance.id, c.toApi());
  }

  void _add(Result r) {
    home.add(widget.query, r);
    setState(() => _added = true);
    notifyAdded(ScaffoldMessenger.of(context), tr('${r.name} foi para a sua casa.', '${r.name} was added to your home.'));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Result>(
      future: _result,
      builder: (context, snap) {
        final r = snap.connectionState == ConnectionState.done && !snap.hasError ? snap.data : null;
        return AppPage(
          title: tr('Quanto custa', 'How much it costs'),
          step: calculationStep(widget.query, 6),
          footer: r == null
              ? null
              : ConfirmButton(
                  done: _added,
                  actionText: tr('Adicionar à minha casa', 'Add to my home'),
                  actionIcon: Icons.add_home_outlined,
                  onAction: () => _add(r),
                  doneText: tr('Está na sua casa: ver o total', 'It is in your home: see the total'),
                  onDone: () => goTo(AppTab.home, closeCurrent: true),
                ),
          child: _body(snap),
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<Result> snap) {
    if (snap.connectionState != ConnectionState.done) return Loading(text: tr('Calculando...', 'Calculating...'));
    if (snap.hasError) {
      return ErrorMessage(
        snap.error.toString(),
        tryAgain: () => setState(() {
          _result = _calculate();
        }),
      );
    }
    final r = snap.data!;
    return ListView(
      children: [
        ResultDetails(r),
        const SizedBox(height: Spacing.g),
        if (!widget.query.smallAppliance)
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SuggestionScreen(query: widget.query, current: r)),
            ),
            icon: const Icon(Icons.trending_down),
            label: Text(tr('Ver modelos que gastam menos', 'See models that use less')),
          ),
        if (widget.query.smallAppliance)
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TipScreen(result: r))),
            icon: const Icon(Icons.tips_and_updates_outlined),
            label: Text(tr('Como gastar menos com ele', 'How to spend less on it')),
          ),
        const SizedBox(height: Spacing.p),
        TextButton.icon(
          onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
          icon: const Icon(Icons.restart_alt),
          label: Text(tr('Calcular outro aparelho', 'Calculate another appliance')),
        ),
      ],
    );
  }
}

class ResultDetails extends StatelessWidget {
  final Result r;

  const ResultDetails(this.r, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Row(
            children: [
              Icon(categoryIcon(r.category), size: t.largeIcon),
              const SizedBox(width: Spacing.pm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: t.strong),
                    Text(
                      [
                        if (r.detail.isNotEmpty) r.detail,
                        if (r.distributor != '-') '${r.distributor} (${r.uf})',
                      ].join(' · '),
                      style: t.secondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.m),
        HighlightCard(
          title: r.approximate
              ? tr('Gasto aproximado por mês', 'Approximate cost per month')
              : tr('Gasto por mês', 'Cost per month'),
          value: r.monthlyCost,
          format: reais,
          footer: [
            if (r.hasRange)
              tr(
                'Entre ${reais(r.monthlyMinCost!)} e ${reais(r.monthlyMaxCost!)}',
                'Between ${reais(r.monthlyMinCost!)} and ${reais(r.monthlyMaxCost!)}',
              ),
            tr('${reais(r.yearlyCost)} por ano', '${reais(r.yearlyCost)} per year'),
          ].join(' · '),
        ),
        const SizedBox(height: Spacing.p),
        Text(
          tr(
            'Consumo de ${number(r.monthlyKwh)} kWh por mês, com a energia a ${reais(r.tariffKwh, homes: 4)} o kWh.',
            'Uses ${number(r.monthlyKwh)} kWh per month, with electricity at ${reais(r.tariffKwh, homes: 4)} per kWh.',
          ),
          style: t.secondary,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Spacing.m),
        NoticeList(r.notices),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: const Icon(Icons.info_outline),
            title: Text(tr('Como calculamos', 'How we calculated'), style: t.strong),
            subtitle: Text(tr('Fórmula e fonte da tarifa', 'Formula and rate source'), style: t.secondary),
            childrenPadding: const EdgeInsets.fromLTRB(Spacing.m, 0, Spacing.m, Spacing.m),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.method, style: t.body),
              const SizedBox(height: Spacing.pm),
              Text(tr('Fonte da tarifa', 'Rate source'), style: t.label),
              Text(r.tariffOrigin, style: t.body),
            ],
          ),
        ),
      ],
    );
  }
}
