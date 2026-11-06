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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${r.nome} foi para a sua casa.'),
      action: SnackBarAction(label: 'Ver', onPressed: () => abrirMinhaCasa(context)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Resultado',
      passo: 4,
      filho: FutureBuilder<Resultado>(
        future: _resultado,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return MensagemErro(snap.error.toString(),
                tentarDeNovo: () => setState(() => _resultado = _calcular()));
          }
          final r = snap.data!;
          return ListView(
            children: [
              _DetalhesDoResultado(r),
              const SizedBox(height: 16),
              if (_adicionado)
                OutlinedButton.icon(
                  onPressed: () => abrirMinhaCasa(context),
                  icon: const Icon(Icons.check, color: Cores.amarelo),
                  label: const Text('Na sua casa - ver total'),
                )
              else
                FilledButton.icon(
                  onPressed: () => _adicionar(r),
                  icon: const Icon(Icons.add_home_outlined),
                  label: const Text('Adicionar à minha casa'),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => TelaSugestoes(consulta: widget.consulta)),
                ),
                icon: const Icon(Icons.trending_down, color: Cores.amarelo),
                label: const Text('Ver modelos mais econômicos'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.popUntil(context, (rota) => rota.isFirst),
                icon: const Icon(Icons.search),
                label: const Text('Calcular outro aparelho'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DetalhesDoResultado extends StatelessWidget {
  final Resultado r;

  const _DetalhesDoResultado(this.r);

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(r.nome, style: texto.titleLarge),
        if (r.detalhe.isNotEmpty) Text(r.detalhe, style: const TextStyle(color: Cores.cinza)),
        if (r.distribuidora != '-')
          Text('${r.distribuidora} - ${r.uf}', style: const TextStyle(color: Cores.cinza)),
        const SizedBox(height: 16),
        CartaoDestaque(titulo: 'Gasto por mês', valor: reais(r.custoMes), rodape: '${reais(r.custoAno)} por ano'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: CartaoInfo('Consumo', '${numero(r.kwhMes)} kWh/mês')),
            Expanded(child: CartaoInfo('Tarifa', '${reais(r.tarifaKwh, casas: 4)}/kWh')),
          ],
        ),
        const Titulo('Como calculamos'),
        Text(r.metodo),
        const Titulo('Fonte da tarifa'),
        Text(r.origemTarifa),
        const SizedBox(height: 16),
        ListaAvisos(r.avisos),
      ],
    );
  }
}
