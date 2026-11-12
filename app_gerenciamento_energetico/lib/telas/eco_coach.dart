import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../idioma.dart';
import '../navegacao.dart';
import '../tema.dart';
import 'comum.dart';
import 'texto_plano.dart';

/// Aba "Economizar" (POST /eco-coach): plano de economia escrito por IA a partir de dicas oficiais
/// (Inmetro e Cemig). Os numeros sao calculados pelo Iamp; a IA so escreve e cita as fontes [n].
/// O plano so e pedido quando a pessoa toca no botao (o plano gratuito do Gemini tem limite de uso)
/// e fica guardado ate a casa mudar.
class EcoCoachScreen extends StatefulWidget {
  const EcoCoachScreen({super.key});

  @override
  State<EcoCoachScreen> createState() => _EcoCoachScreenState();
}

class _EcoCoachScreenState extends State<EcoCoachScreen> {
  bool _generating = false;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      home.storePlan(await Api.ecoCoach(home.residents, home.itemsForEcoCoach(), home.swaps));
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: homes,
      builder: (context, _) {
        final plan = home.plan;
        return AppPage(title: tr('Economizar', 'Save energy'), footer: _footer(plan), child: _body(plan));
      },
    );
  }

  Widget? _footer(EcoCoach? plan) {
    if (_generating) return null;
    if (home.isEmpty) {
      return FilledButton.icon(
        onPressed: () => goTo(AppTab.calculate, restart: true),
        icon: const Icon(Icons.calculate_outlined),
        label: Text(tr('Calcular um aparelho', 'Calculate an appliance')),
      );
    }
    if (plan != null) {
      return OutlinedButton.icon(
        onPressed: _generate,
        icon: const Icon(Icons.refresh),
        label: Text(tr('Montar outro plano', 'Build another plan')),
      );
    }
    return FilledButton.icon(
      onPressed: _generate,
      icon: const Icon(Icons.auto_awesome),
      label: Text(tr('Montar meu plano', 'Build my plan')),
    );
  }

  Widget _body(EcoCoach? plan) {
    if (_generating) return const _Thinking();
    if (home.isEmpty) return const _NoAppliances();
    return ListView(
      children: [
        if (_error != null) ...[ErrorMessage(_error!, tryAgain: _generate), const SizedBox(height: Spacing.m)],
        if (plan != null) _Content(plan) else const _Presentation(),
      ],
    );
  }
}

class _NoAppliances extends StatelessWidget {
  const _NoAppliances();

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.savings_outlined, size: t.hugeIcon),
            const SizedBox(height: Spacing.m),
            Semantics(
              header: true,
              child: Text(
                tr('Primeiro, calcule seus aparelhos', 'First, calculate your appliances'),
                style: t.title,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: Spacing.p),
            Text(
              tr(
                'Com os aparelhos da sua casa, o Eco-Coach monta um plano para gastar menos, '
                    'com dicas oficiais do Inmetro e da Cemig.',
                'With the appliances in your home, the Eco-Coach builds a plan to spend less, '
                    'with official tips from Inmetro and Cemig.',
              ),
              style: t.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Presentation extends StatelessWidget {
  const _Presentation();

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final n = home.totalAppliances;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuestionHeader(
          tr('Seu plano para gastar menos', 'Your plan to spend less'),
          help: tr(
            'O Eco-Coach lê as dicas oficiais do Inmetro e da Cemig e monta um plano '
                'para os aparelhos que mais pesam na sua conta.',
            'The Eco-Coach reads the official tips from Inmetro and Cemig and builds a plan '
                'for the appliances that weigh most on your bill.',
          ),
        ),
        HighlightCard(
          title: tr('Sua conta com estes aparelhos', 'Your bill with these appliances'),
          value: home.monthlyCost,
          format: (v) => tr('${reais(v)} por mês', '${reais(v)} per month'),
          footer: tr(
            '$n ${n == 1 ? 'aparelho' : 'aparelhos'} · ${home.residents} '
                '${home.residents == 1 ? 'morador' : 'moradores'}',
            '$n ${n == 1 ? 'appliance' : 'appliances'} · ${home.residents} '
                '${home.residents == 1 ? 'resident' : 'residents'}',
          ),
        ),
        if (home.swaps.isNotEmpty) ...[
          const SizedBox(height: Spacing.p),
          Text(
            tr(
              'O plano também considera ${home.swaps.length == 1 ? 'a troca' : 'as ${home.swaps.length} trocas'} '
                  'de aparelho que você avaliou.',
              'The plan also considers the ${home.swaps.length == 1 ? 'appliance replacement' : '${home.swaps.length} appliance replacements'} '
                  'you evaluated.',
            ),
            style: t.secondary,
          ),
        ],
        const SizedBox(height: Spacing.m),
        NoticeList([
          tr(
            'O texto é escrito por inteligência artificial e pode levar alguns segundos.',
            'The text is written by artificial intelligence and may take a few seconds.',
          ),
        ]),
      ],
    );
  }
}

/// Espera da IA: raio pulsando e o que esta acontecendo (pode levar alguns segundos).
class _Thinking extends StatefulWidget {
  const _Thinking();

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: Tween(begin: 0.85, end: 1.15).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
              child: Container(
                padding: const EdgeInsets.all(Spacing.g),
                decoration: t.highlightCard(t.highlight, circle: true),
                child: Icon(Icons.bolt, size: t.largeIcon + 16, color: t.highlight),
              ),
            ),
            const SizedBox(height: Spacing.g),
            Semantics(liveRegion: true, child: Text(tr('Montando seu plano', 'Building your plan'), style: t.title)),
            const SizedBox(height: Spacing.p),
            Text(
              tr('Lendo as dicas do Inmetro e da Cemig. Leva alguns segundos.', 'Reading the tips from Inmetro and Cemig. It takes a few seconds.'),
              textAlign: TextAlign.center,
              style: t.body,
            ),
          ],
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  final EcoCoach p;

  const _Content(this.p);

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final cor = switch (p.profile) {
      'Consciente' => t.savings,
      'Ineficiente' => t.alert,
      _ => t.highlight,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // resumo calculado pelo Iamp (nao pela IA)
        if (p.totalCost != null)
          HighlightCard(
            title: tr('Sua conta com estes aparelhos', 'Your bill with these appliances'),
            value: p.totalCost!,
            format: (v) => tr('${reais(v)} por mês', '${reais(v)} per month'),
            footer: tr('${number(p.kwhTotal)} kWh por mês', '${number(p.kwhTotal)} kWh per month'),
          ),
        const SizedBox(height: Spacing.p),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.pm, vertical: Spacing.pp),
            decoration: t.badge(cor),
            child: Text(
              tr('Perfil da casa: ${profileName(p.profile)}', 'Home profile: ${profileName(p.profile)}'),
              style: t.label.copyWith(color: cor),
            ),
          ),
        ),
        SectionTitle(tr('O que mais pesa', 'What weighs most')),
        for (final m in p.largestConsumptions) _ConsumptionLine(m),
        SectionTitle(tr('Seu plano de economia', 'Your savings plan')),
        Container(
          padding: const EdgeInsets.all(Spacing.m),
          decoration: t.highlightCard(t.highlight),
          child: PlanText(p.plan),
        ),
        if (p.sources.isNotEmpty) ...[
          SectionTitle(tr('Fontes citadas', 'Sources cited')),
          if (inEnglish) Text('The sources are Brazilian documents in Portuguese.', style: t.secondary),
          for (final f in p.sources) SourceCard(f),
        ],
        const SizedBox(height: Spacing.m),
        NoticeList([
          p.notice,
          tr(
            'Escrito por inteligência artificial (${p.model}): pode errar, confira as fontes.',
            'Written by artificial intelligence (${p.model}): it can make mistakes, check the sources.',
          ),
        ]),
      ],
    );
  }
}

class _ConsumptionLine extends StatelessWidget {
  final LargestConsumption m;

  const _ConsumptionLine(this.m);

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final piece = '${number(m.percentage, homes: 0)}%';
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.pm),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(categoryIcon(m.category)),
                const SizedBox(width: Spacing.p),
                Expanded(child: Text(_capitalized(m.name), style: t.strong)),
              ],
            ),
            if (m.monthlyCost != null) Text(tr('${reais(m.monthlyCost!)} por mês', '${reais(m.monthlyCost!)} per month'), style: t.number),
            Text(tr('$piece do consumo · ${number(m.monthlyKwh)} kWh', '$piece of consumption · ${number(m.monthlyKwh)} kWh'), style: t.secondary),
            const SizedBox(height: Spacing.pp),
            ExcludeSemantics(
              child: PartBar(m.percentage / 100, description: tr('$piece do consumo', '$piece of consumption')),
            ),
          ],
        ),
      ),
    );
  }

  static String _capitalized(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Fonte citada no texto: o numero [n], o documento e o endereco (pode ser selecionado e copiado).
class SourceCard extends StatelessWidget {
  final CitedSource f;

  const SourceCard(this.f, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final where = [
      if (f.section != null && f.section!.isNotEmpty) f.section!,
      if (f.page != null) tr('página ${f.page}', 'page ${f.page}'),
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.pm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              constraints: BoxConstraints(minWidth: t.largeIcon, minHeight: t.largeIcon),
              padding: const EdgeInsets.symmetric(horizontal: Spacing.p),
              alignment: Alignment.center,
              decoration: t.badge(t.highlight),
              child: Text(
                '${f.n}',
                style: t.strong.copyWith(color: t.highlight),
                semanticsLabel: tr('Fonte ${f.n}', 'Source ${f.n}'),
              ),
            ),
            const SizedBox(width: Spacing.pm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${f.agency} · ${f.document}', style: t.strong),
                  if (where.isNotEmpty) Text(where, style: t.secondary),
                  const SizedBox(height: Spacing.pp),
                  // sem pacote para abrir links: o endereco pode ser selecionado e copiado
                  SelectableText(f.url, style: t.secondary.copyWith(color: t.highlight)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
