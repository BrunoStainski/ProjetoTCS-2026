import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../tema.dart';
import 'comum.dart';
import 'sugestoes.dart';

/// Passo 4: chama POST /calcular e mostra quanto o aparelho custa.
/// Daqui o usuario adiciona o aparelho na casa ou procura um modelo mais economico.
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

  Future<Resultado> _calcular() => Api.calcular(widget.consulta.aparelho.id, widget.consulta.paraApi());

  void _adicionar(Resultado r) {
    casa.adicionar(widget.consulta, r);
    setState(() => _adicionado = true);
    final navegador = Navigator.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${r.nome} foi para a sua casa.'),
        // o aviso pode continuar na tela depois de sair daqui: usa o navegador, nao o context
        action: SnackBarAction(label: 'Ver', onPressed: () => abrirMinhaCasaNo(navegador)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Resultado>(
      future: _resultado,
      builder: (context, snap) {
        final r = snap.connectionState == ConnectionState.done && !snap.hasError ? snap.data : null;
        return Pagina(
          titulo: 'Resultado',
          passo: 4,
          rodape: r == null
              ? null
              : BotaoComConfirmacao(
                  feito: _adicionado,
                  textoAcao: 'Adicionar à minha casa',
                  iconeAcao: Icons.add_home_outlined,
                  onAcao: () => _adicionar(r),
                  textoFeito: 'Na sua casa - ver total',
                  onFeito: () => abrirMinhaCasa(context),
                ),
          filho: _corpo(snap),
        );
      },
    );
  }

  Widget _corpo(AsyncSnapshot<Resultado> snap) {
    if (snap.connectionState != ConnectionState.done) {
      return const Center(child: CircularProgressIndicator());
    }
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
        _DetalhesDoResultado(r),
        const SizedBox(height: Espaco.g),
        OutlinedButton.icon(
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => TelaSugestoes(consulta: widget.consulta))),
          icon: const Icon(Icons.trending_down, color: Cores.verde),
          label: const Text('Ver modelos mais econômicos'),
        ),
        const SizedBox(height: Espaco.p),
        TextButton.icon(
          onPressed: () => Navigator.popUntil(context, (rota) => rota.isFirst),
          icon: const Icon(Icons.search),
          label: const Text('Calcular outro aparelho'),
        ),
      ],
    );
  }
}

class _DetalhesDoResultado extends StatelessWidget {
  final Resultado r;

  const _DetalhesDoResultado(this.r);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(iconeDaCategoria(r.categoria), color: Cores.amarelo, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.nome, style: Estilos.titulo),
                  Text(
                    [
                      if (r.detalhe.isNotEmpty) r.detalhe,
                      if (r.distribuidora != '-') '${r.distribuidora} - ${r.uf}',
                    ].join(' · '),
                    style: Estilos.secundario,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Espaco.m),
        CartaoDestaque(
          titulo: 'Gasto por mês',
          valor: r.custoMes,
          formatar: reais,
          rodape: '${reais(r.custoAno)} por ano',
        ),
        const SizedBox(height: Espaco.p),
        Row(
          children: [
            Expanded(child: CartaoInfo('Consumo', '${numero(r.kwhMes)} kWh/mês')),
            const SizedBox(width: Espaco.p),
            Expanded(child: CartaoInfo('Tarifa', '${reais(r.tarifaKwh, casas: 4)}/kWh')),
          ],
        ),
        const Titulo('Como calculamos'),
        Text(r.metodo),
        const Titulo('Fonte da tarifa'),
        Text(r.origemTarifa),
        const SizedBox(height: Espaco.m),
        ListaAvisos(r.avisos),
      ],
    );
  }
}
