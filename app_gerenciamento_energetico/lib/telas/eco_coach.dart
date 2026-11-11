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
class TelaEcoCoach extends StatefulWidget {
  const TelaEcoCoach({super.key});

  @override
  State<TelaEcoCoach> createState() => _TelaEcoCoachState();
}

class _TelaEcoCoachState extends State<TelaEcoCoach> {
  bool _gerando = false;
  String? _erro;

  Future<void> _gerar() async {
    setState(() {
      _gerando = true;
      _erro = null;
    });
    try {
      casa.guardarPlano(await Api.ecoCoach(casa.moradores, casa.itensParaEcoCoach(), casa.trocas));
    } on ApiErro catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: casa,
      builder: (context, _) {
        final plano = casa.plano;
        return Pagina(titulo: tr('Economizar', 'Save energy'), rodape: _rodape(plano), filho: _corpo(plano));
      },
    );
  }

  Widget? _rodape(EcoCoach? plano) {
    if (_gerando) return null;
    if (casa.vazia) {
      return FilledButton.icon(
        onPressed: () => irPara(Aba.calcular, recomecar: true),
        icon: const Icon(Icons.calculate_outlined),
        label: Text(tr('Calcular um aparelho', 'Calculate an appliance')),
      );
    }
    if (plano != null) {
      return OutlinedButton.icon(
        onPressed: _gerar,
        icon: const Icon(Icons.refresh),
        label: Text(tr('Montar outro plano', 'Build another plan')),
      );
    }
    return FilledButton.icon(
      onPressed: _gerar,
      icon: const Icon(Icons.auto_awesome),
      label: Text(tr('Montar meu plano', 'Build my plan')),
    );
  }

  Widget _corpo(EcoCoach? plano) {
    if (_gerando) return const _Pensando();
    if (casa.vazia) return const _SemAparelhos();
    return ListView(
      children: [
        if (_erro != null) ...[MensagemErro(_erro!, tentarDeNovo: _gerar), const SizedBox(height: Espaco.m)],
        if (plano != null) _Conteudo(plano) else const _Apresentacao(),
      ],
    );
  }
}

class _SemAparelhos extends StatelessWidget {
  const _SemAparelhos();

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.savings_outlined, size: t.iconeEnorme),
            const SizedBox(height: Espaco.m),
            Semantics(
              header: true,
              child: Text(
                tr('Primeiro, calcule seus aparelhos', 'First, calculate your appliances'),
                style: t.titulo,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: Espaco.p),
            Text(
              tr(
                'Com os aparelhos da sua casa, o Eco-Coach monta um plano para gastar menos, '
                    'com dicas oficiais do Inmetro e da Cemig.',
                'With the appliances in your home, the Eco-Coach builds a plan to spend less, '
                    'with official tips from Inmetro and Cemig.',
              ),
              style: t.corpo,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Apresentacao extends StatelessWidget {
  const _Apresentacao();

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final n = casa.totalAparelhos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CabecalhoPergunta(
          tr('Seu plano para gastar menos', 'Your plan to spend less'),
          ajuda: tr(
            'O Eco-Coach lê as dicas oficiais do Inmetro e da Cemig e monta um plano '
                'para os aparelhos que mais pesam na sua conta.',
            'The Eco-Coach reads the official tips from Inmetro and Cemig and builds a plan '
                'for the appliances that weigh most on your bill.',
          ),
        ),
        CartaoDestaque(
          titulo: tr('Sua conta com estes aparelhos', 'Your bill with these appliances'),
          valor: casa.custoMes,
          formatar: (v) => tr('${reais(v)} por mês', '${reais(v)} per month'),
          rodape: tr(
            '$n ${n == 1 ? 'aparelho' : 'aparelhos'} · ${casa.moradores} '
                '${casa.moradores == 1 ? 'morador' : 'moradores'}',
            '$n ${n == 1 ? 'appliance' : 'appliances'} · ${casa.moradores} '
                '${casa.moradores == 1 ? 'resident' : 'residents'}',
          ),
        ),
        if (casa.trocas.isNotEmpty) ...[
          const SizedBox(height: Espaco.p),
          Text(
            tr(
              'O plano também considera ${casa.trocas.length == 1 ? 'a troca' : 'as ${casa.trocas.length} trocas'} '
                  'de aparelho que você avaliou.',
              'The plan also considers the ${casa.trocas.length == 1 ? 'appliance replacement' : '${casa.trocas.length} appliance replacements'} '
                  'you evaluated.',
            ),
            style: t.secundario,
          ),
        ],
        const SizedBox(height: Espaco.m),
        ListaAvisos([
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
class _Pensando extends StatefulWidget {
  const _Pensando();

  @override
  State<_Pensando> createState() => _PensandoState();
}

class _PensandoState extends State<_Pensando> with SingleTickerProviderStateMixin {
  late final AnimationController _pulso = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulso.dispose();
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
              scale: Tween(begin: 0.85, end: 1.15).animate(CurvedAnimation(parent: _pulso, curve: Curves.easeInOut)),
              child: Container(
                padding: const EdgeInsets.all(Espaco.g),
                decoration: t.cartaoDestaque(t.destaque, circulo: true),
                child: Icon(Icons.bolt, size: t.iconeGrande + 16, color: t.destaque),
              ),
            ),
            const SizedBox(height: Espaco.g),
            Semantics(liveRegion: true, child: Text(tr('Montando seu plano', 'Building your plan'), style: t.titulo)),
            const SizedBox(height: Espaco.p),
            Text(
              tr('Lendo as dicas do Inmetro e da Cemig. Leva alguns segundos.', 'Reading the tips from Inmetro and Cemig. It takes a few seconds.'),
              textAlign: TextAlign.center,
              style: t.corpo,
            ),
          ],
        ),
      ),
    );
  }
}

class _Conteudo extends StatelessWidget {
  final EcoCoach p;

  const _Conteudo(this.p);

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final cor = switch (p.perfil) {
      'Consciente' => t.economia,
      'Ineficiente' => t.alerta,
      _ => t.destaque,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // resumo calculado pelo Iamp (nao pela IA)
        if (p.custoTotal != null)
          CartaoDestaque(
            titulo: tr('Sua conta com estes aparelhos', 'Your bill with these appliances'),
            valor: p.custoTotal!,
            formatar: (v) => tr('${reais(v)} por mês', '${reais(v)} per month'),
            rodape: tr('${numero(p.kwhTotal)} kWh por mês', '${numero(p.kwhTotal)} kWh per month'),
          ),
        const SizedBox(height: Espaco.p),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Espaco.pm, vertical: Espaco.pp),
            decoration: t.selo(cor),
            child: Text(
              tr('Perfil da casa: ${nomeDoPerfil(p.perfil)}', 'Home profile: ${nomeDoPerfil(p.perfil)}'),
              style: t.rotulo.copyWith(color: cor),
            ),
          ),
        ),
        Titulo(tr('O que mais pesa', 'What weighs most')),
        for (final m in p.maioresConsumos) _LinhaConsumo(m),
        Titulo(tr('Seu plano de economia', 'Your savings plan')),
        Container(
          padding: const EdgeInsets.all(Espaco.m),
          decoration: t.cartaoDestaque(t.destaque),
          child: TextoPlano(p.plano),
        ),
        if (p.fontes.isNotEmpty) ...[
          Titulo(tr('Fontes citadas', 'Sources cited')),
          if (emIngles) Text('The sources are Brazilian documents in Portuguese.', style: t.secundario),
          for (final f in p.fontes) CartaoFonte(f),
        ],
        const SizedBox(height: Espaco.m),
        ListaAvisos([
          p.aviso,
          tr(
            'Escrito por inteligência artificial (${p.modelo}): pode errar, confira as fontes.',
            'Written by artificial intelligence (${p.modelo}): it can make mistakes, check the sources.',
          ),
        ]),
      ],
    );
  }
}

class _LinhaConsumo extends StatelessWidget {
  final MaiorConsumo m;

  const _LinhaConsumo(this.m);

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final parte = '${numero(m.percentual, casas: 0)}%';
    return Padding(
      padding: const EdgeInsets.only(bottom: Espaco.pm),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(iconeDaCategoria(m.categoria)),
                const SizedBox(width: Espaco.p),
                Expanded(child: Text(_maiuscula(m.nome), style: t.forte)),
              ],
            ),
            if (m.custoMes != null) Text(tr('${reais(m.custoMes!)} por mês', '${reais(m.custoMes!)} per month'), style: t.numero),
            Text(tr('$parte do consumo · ${numero(m.kwhMes)} kWh', '$parte of consumption · ${numero(m.kwhMes)} kWh'), style: t.secundario),
            const SizedBox(height: Espaco.pp),
            ExcludeSemantics(
              child: BarraParte(m.percentual / 100, descricao: tr('$parte do consumo', '$parte of consumption')),
            ),
          ],
        ),
      ),
    );
  }

  static String _maiuscula(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Fonte citada no texto: o numero [n], o documento e o endereco (pode ser selecionado e copiado).
class CartaoFonte extends StatelessWidget {
  final FonteCitada f;

  const CartaoFonte(this.f, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final onde = [
      if (f.secao != null && f.secao!.isNotEmpty) f.secao!,
      if (f.pagina != null) tr('página ${f.pagina}', 'page ${f.pagina}'),
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Espaco.pm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              constraints: BoxConstraints(minWidth: t.iconeGrande, minHeight: t.iconeGrande),
              padding: const EdgeInsets.symmetric(horizontal: Espaco.p),
              alignment: Alignment.center,
              decoration: t.selo(t.destaque),
              child: Text(
                '${f.n}',
                style: t.forte.copyWith(color: t.destaque),
                semanticsLabel: tr('Fonte ${f.n}', 'Source ${f.n}'),
              ),
            ),
            const SizedBox(width: Espaco.pm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${f.orgao} · ${f.documento}', style: t.forte),
                  if (onde.isNotEmpty) Text(onde, style: t.secundario),
                  const SizedBox(height: Espaco.pp),
                  // sem pacote para abrir links: o endereco pode ser selecionado e copiado
                  SelectableText(f.url, style: t.secundario.copyWith(color: t.destaque)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
