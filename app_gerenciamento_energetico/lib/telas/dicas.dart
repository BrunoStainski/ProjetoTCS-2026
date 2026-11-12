import 'package:flutter/material.dart';

import '../api.dart';
import '../idioma.dart';
import '../tema.dart';
import 'comum.dart';
import 'eco_coach.dart';
import 'texto_plano.dart';

/// Dicas do Eco-Coach para um aparelho so (eletroportateis, que nao tem modelos para comparar).
class TipScreen extends StatefulWidget {
  final Result result;
  final Future<Tips> Function(Result) searchTips;

  const TipScreen({super.key, required this.result, this.searchTips = Api.tips});

  @override
  State<TipScreen> createState() => _TipScreenState();
}

class _TipScreenState extends State<TipScreen> {
  late Future<Tips> _tips;

  @override
  void initState() {
    super.initState();
    _tips = widget.searchTips(widget.result);
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final r = widget.result;
    return AppPage(
      title: tr('Como gastar menos', 'How to spend less'),
      child: FutureBuilder<Tips>(
        future: _tips,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Loading(
              text: tr(
                'O Eco-Coach está preparando dicas para o seu aparelho...',
                'The Eco-Coach is preparing tips for your appliance...',
              ),
            );
          }
          if (snap.hasError) {
            return ErrorMessage(
              snap.error.toString(),
              tryAgain: () => setState(() {
                _tips = widget.searchTips(r);
              }),
            );
          }
          final d = snap.data!;
          return ListView(
            children: [
              MergeSemantics(
                child: Card(
                  child: ListTile(
                    leading: Icon(categoryIcon(r.category)),
                    title: Text(r.name),
                    subtitle: Text(
                      tr(
                        '${reais(r.monthlyCost)} por mês · ${number(r.monthlyKwh)} kWh',
                        '${reais(r.monthlyCost)} per month · ${number(r.monthlyKwh)} kWh',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.m),
              PlanText(d.text),
              if (d.sources.isNotEmpty) ...[
                SectionTitle(tr('Fontes', 'Sources')),
                if (inEnglish) Text('The sources are Brazilian documents in Portuguese.', style: t.secondary),
                for (final f in d.sources) SourceCard(f),
              ],
              const SizedBox(height: Spacing.m),
              NoticeList([d.notice]),
              SizedBox(height: t.touchTarget),
            ],
          );
        },
      ),
    );
  }
}
