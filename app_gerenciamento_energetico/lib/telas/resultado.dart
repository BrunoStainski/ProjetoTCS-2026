import 'package:flutter/material.dart';

import '../api.dart';
import 'comum.dart';

/// Passo 4: chama POST /calcular e mostra quanto o aparelho custa.
class TelaResultado extends StatefulWidget {
  final Consulta consulta;
  final int? distribuidoraId;
  final double? tarifaManual;

  const TelaResultado({super.key, required this.consulta, this.distribuidoraId, this.tarifaManual});

  @override
  State<TelaResultado> createState() => _TelaResultadoState();
}

class _TelaResultadoState extends State<TelaResultado> {
  late Future<Resultado> _resultado;

  @override
  void initState() {
    super.initState();
    _resultado = _calcular();
  }

  Future<Resultado> _calcular() {
    final c = widget.consulta;
    return Api.calcular(
      aparelhoId: c.aparelho.id,
      distribuidoraId: widget.distribuidoraId,
      tarifaManual: widget.tarifaManual,
      horasDia: c.horasDia,
      ciclosMes: c.ciclosMes,
      velocidade: c.velocidade,
    );
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
          return _Conteudo(snap.data!);
        },
      ),
    );
  }
}

class _Conteudo extends StatelessWidget {
  final Resultado r;

  const _Conteudo(this.r);

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final cores = Theme.of(context).colorScheme;
    return ListView(
      children: [
        Text('${r.marca} ${r.modelo}', style: texto.titleLarge),
        if (r.detalhe.isNotEmpty) Text(r.detalhe),
        if (r.distribuidora != '-') Text('${r.distribuidora} - ${r.uf}'),
        const SizedBox(height: 16),
        Card(
          color: cores.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text('Gasto por mês', style: texto.titleMedium),
                Text(reais(r.custoMes), style: texto.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
                Text('${reais(r.custoAno)} por ano'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _Info('Consumo', '${numero(r.kwhMes)} kWh/mês')),
            Expanded(child: _Info('Tarifa', '${reais(r.tarifaKwh, casas: 4)}/kWh')),
          ],
        ),
        const SizedBox(height: 16),
        Text('Como calculamos', style: texto.titleSmall),
        Text(r.metodo),
        const SizedBox(height: 8),
        Text('Fonte da tarifa', style: texto.titleSmall),
        Text(r.origemTarifa),
        const SizedBox(height: 16),
        for (final aviso in r.avisos)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: cores.outline),
                const SizedBox(width: 8),
                Expanded(child: Text(aviso, style: texto.bodySmall)),
              ],
            ),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => Navigator.popUntil(context, (rota) => rota.isFirst),
          icon: const Icon(Icons.search),
          label: const Text('Calcular outro aparelho'),
        ),
      ],
    );
  }
}

class _Info extends StatelessWidget {
  final String titulo;
  final String valor;

  const _Info(this.titulo, this.valor);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(titulo, style: Theme.of(context).textTheme.labelMedium),
            Text(valor, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
