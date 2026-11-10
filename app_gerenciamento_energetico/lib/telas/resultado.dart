import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
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
    avisarAdicionado(ScaffoldMessenger.of(context), '${r.nome} foi para a sua casa.');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Resultado>(
      future: _resultado,
      builder: (context, snap) {
        final r = snap.connectionState == ConnectionState.done && !snap.hasError ? snap.data : null;
        return Pagina(
          titulo: 'Quanto custa',
          etapa: etapaDoCalculo(widget.consulta, 6),
          rodape: r == null
              ? null
              : BotaoComConfirmacao(
                  feito: _adicionado,
                  textoAcao: 'Adicionar à minha casa',
                  iconeAcao: Icons.add_home_outlined,
                  onAcao: () => _adicionar(r),
                  textoFeito: 'Está na sua casa: ver o total',
                  onFeito: () => irPara(Aba.casa, fecharAtual: true),
                ),
          filho: _corpo(snap),
        );
      },
    );
  }

  Widget _corpo(AsyncSnapshot<Resultado> snap) {
    if (snap.connectionState != ConnectionState.done) return const Carregando(texto: 'Calculando...');
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
            label: const Text('Ver modelos que gastam menos'),
          ),
        if (widget.consulta.portatil)
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TelaDicas(resultado: r))),
            icon: const Icon(Icons.tips_and_updates_outlined),
            label: const Text('Como gastar menos com ele'),
          ),
        const SizedBox(height: Espaco.p),
        TextButton.icon(
          onPressed: () => Navigator.popUntil(context, (rota) => rota.isFirst),
          icon: const Icon(Icons.restart_alt),
          label: const Text('Calcular outro aparelho'),
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
          titulo: r.aproximado ? 'Gasto aproximado por mês' : 'Gasto por mês',
          valor: r.custoMes,
          formatar: reais,
          rodape: [
            if (r.temFaixa) 'Entre ${reais(r.custoMinMes!)} e ${reais(r.custoMaxMes!)}',
            '${reais(r.custoAno)} por ano',
          ].join(' · '),
        ),
        const SizedBox(height: Espaco.p),
        Text(
          'Consumo de ${numero(r.kwhMes)} kWh por mês, com a energia a ${reais(r.tarifaKwh, casas: 4)} o kWh.',
          style: t.secundario,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Espaco.m),
        ListaAvisos(r.avisos),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: const Icon(Icons.info_outline),
            title: Text('Como calculamos', style: t.forte),
            subtitle: Text('Fórmula e fonte da tarifa', style: t.secundario),
            childrenPadding: const EdgeInsets.fromLTRB(Espaco.m, 0, Espaco.m, Espaco.m),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.metodo, style: t.corpo),
              const SizedBox(height: Espaco.pm),
              Text('Fonte da tarifa', style: t.rotulo),
              Text(r.origemTarifa, style: t.corpo),
            ],
          ),
        ),
      ],
    );
  }
}
