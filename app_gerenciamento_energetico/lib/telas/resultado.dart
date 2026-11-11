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
class TelaResultado extends StatefulWidget {
  final Consulta consulta;

  const TelaResultado({super.key, required this.consulta});

  @override
  State<TelaResultado> createState() => _TelaResultadoState();
}

class _TelaResultadoState extends State<TelaResultado> {
  late Future<Resultado> _resultado;
  bool _adicionado = false;

  @override
  void initState() {
    super.initState();
    _resultado = _calcular();
  }

  Future<Resultado> _calcular() {
    final c = widget.consulta;
    return c.estimado
        ? Api.estimar(c.estimativa!.rota, c.corpoDaEstimativa())
        : Api.calcular(c.aparelho.id, c.paraApi());
  }

  void _adicionar(Resultado r) {
    casa.adicionar(widget.consulta, r);
    setState(() => _adicionado = true);
    avisarAdicionado(ScaffoldMessenger.of(context), tr('${r.nome} foi para a sua casa.', '${r.nome} was added to your home.'));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Resultado>(
      future: _resultado,
      builder: (context, snap) {
        final r = snap.connectionState == ConnectionState.done && !snap.hasError ? snap.data : null;
        return Pagina(
          titulo: tr('Quanto custa', 'How much it costs'),
          etapa: etapaDoCalculo(widget.consulta, 6),
          rodape: r == null
              ? null
              : BotaoComConfirmacao(
                  feito: _adicionado,
                  textoAcao: tr('Adicionar à minha casa', 'Add to my home'),
                  iconeAcao: Icons.add_home_outlined,
                  onAcao: () => _adicionar(r),
                  textoFeito: tr('Está na sua casa: ver o total', 'It is in your home: see the total'),
                  onFeito: () => irPara(Aba.casa, fecharAtual: true),
                ),
          filho: _corpo(snap),
        );
      },
    );
  }

  Widget _corpo(AsyncSnapshot<Resultado> snap) {
    if (snap.connectionState != ConnectionState.done) return Carregando(texto: tr('Calculando...', 'Calculating...'));
    if (snap.hasError) {
      return MensagemErro(
        snap.error.toString(),
        tentarDeNovo: () => setState(() {
          _resultado = _calcular();
        }),
      );
    }
    final r = snap.data!;
    return ListView(
      children: [
        DetalhesDoResultado(r),
        const SizedBox(height: Espaco.g),
        if (!widget.consulta.portatil)
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TelaSugestoes(consulta: widget.consulta, atual: r)),
            ),
            icon: const Icon(Icons.trending_down),
            label: Text(tr('Ver modelos que gastam menos', 'See models that use less')),
          ),
        if (widget.consulta.portatil)
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TelaDicas(resultado: r))),
            icon: const Icon(Icons.tips_and_updates_outlined),
            label: Text(tr('Como gastar menos com ele', 'How to spend less on it')),
          ),
        const SizedBox(height: Espaco.p),
        TextButton.icon(
          onPressed: () => Navigator.popUntil(context, (rota) => rota.isFirst),
          icon: const Icon(Icons.restart_alt),
          label: Text(tr('Calcular outro aparelho', 'Calculate another appliance')),
        ),
      ],
    );
  }
}

class DetalhesDoResultado extends StatelessWidget {
  final Resultado r;

  const DetalhesDoResultado(this.r, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Row(
            children: [
              Icon(iconeDaCategoria(r.categoria), size: t.iconeGrande),
              const SizedBox(width: Espaco.pm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.nome, style: t.forte),
                    Text(
                      [
                        if (r.detalhe.isNotEmpty) r.detalhe,
                        if (r.distribuidora != '-') '${r.distribuidora} (${r.uf})',
                      ].join(' · '),
                      style: t.secundario,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Espaco.m),
        CartaoDestaque(
          titulo: r.aproximado
              ? tr('Gasto aproximado por mês', 'Approximate cost per month')
              : tr('Gasto por mês', 'Cost per month'),
          valor: r.custoMes,
          formatar: reais,
          rodape: [
            if (r.temFaixa)
              tr(
                'Entre ${reais(r.custoMinMes!)} e ${reais(r.custoMaxMes!)}',
                'Between ${reais(r.custoMinMes!)} and ${reais(r.custoMaxMes!)}',
              ),
            tr('${reais(r.custoAno)} por ano', '${reais(r.custoAno)} per year'),
          ].join(' · '),
        ),
        const SizedBox(height: Espaco.p),
        Text(
          tr(
            'Consumo de ${numero(r.kwhMes)} kWh por mês, com a energia a ${reais(r.tarifaKwh, casas: 4)} o kWh.',
            'Uses ${numero(r.kwhMes)} kWh per month, with electricity at ${reais(r.tarifaKwh, casas: 4)} per kWh.',
          ),
          style: t.secundario,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Espaco.m),
        ListaAvisos(r.avisos),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: const Icon(Icons.info_outline),
            title: Text(tr('Como calculamos', 'How we calculated'), style: t.forte),
            subtitle: Text(tr('Fórmula e fonte da tarifa', 'Formula and rate source'), style: t.secundario),
            childrenPadding: const EdgeInsets.fromLTRB(Espaco.m, 0, Espaco.m, Espaco.m),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.metodo, style: t.corpo),
              const SizedBox(height: Espaco.pm),
              Text(tr('Fonte da tarifa', 'Rate source'), style: t.rotulo),
              Text(r.origemTarifa, style: t.corpo),
            ],
          ),
        ),
      ],
    );
  }
}
