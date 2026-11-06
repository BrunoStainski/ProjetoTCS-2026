import 'package:flutter/material.dart';

import '../api.dart';
import 'comum.dart';
import 'resultado.dart';

/// Passo 3: estado + distribuidora, ou a tarifa da conta de luz.
class TelaDistribuidora extends StatefulWidget {
  final Consulta consulta;

  const TelaDistribuidora({super.key, required this.consulta});

  @override
  State<TelaDistribuidora> createState() => _TelaDistribuidoraState();
}

class _TelaDistribuidoraState extends State<TelaDistribuidora> {
  final _tarifa = TextEditingController();
  List<String> _ufs = [];
  String? _uf;
  List<Distribuidora>? _distribuidoras;
  bool _usarConta = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarUfs();
  }

  @override
  void dispose() {
    _tarifa.dispose();
    super.dispose();
  }

  Future<void> _carregarUfs() async {
    try {
      final ufs = await Api.ufs();
      setState(() {
        _ufs = ufs;
        _erro = null;
      });
    } on ApiErro catch (e) {
      setState(() => _erro = e.mensagem);
    }
  }

  Future<void> _escolherUf(String? uf) async {
    setState(() {
      _uf = uf;
      _distribuidoras = null;
    });
    if (uf == null) return;
    try {
      final lista = await Api.distribuidoras(uf: uf);
      setState(() => _distribuidoras = lista);
    } on ApiErro catch (e) {
      setState(() => _erro = e.mensagem);
    }
  }

  void _calcular({Distribuidora? distribuidora, double? tarifaManual}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TelaResultado(
          consulta: widget.consulta,
          distribuidoraId: distribuidora?.id,
          tarifaManual: tarifaManual,
        ),
      ),
    );
  }

  void _calcularComConta() {
    final tarifa = lerNumero(_tarifa.text);
    if (tarifa == null || tarifa <= 0) {
      setState(() => _erro = 'Informe a tarifa em R\$/kWh (ex.: 0,85).');
      return;
    }
    setState(() => _erro = null);
    _calcular(tarifaManual: tarifa);
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Qual é a sua distribuidora?',
      passo: 3,
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('A distribuidora aparece na sua conta de luz.'),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Escolher distribuidora'), icon: Icon(Icons.map)),
              ButtonSegment(value: true, label: Text('Tarifa da conta'), icon: Icon(Icons.receipt_long)),
            ],
            selected: {_usarConta},
            onSelectionChanged: (s) => setState(() {
              _usarConta = s.first;
              _erro = null;
            }),
          ),
          const SizedBox(height: 16),
          if (_erro != null) MensagemErro(_erro!, tentarDeNovo: _ufs.isEmpty ? _carregarUfs : null),
          if (_usarConta) ...[
            TextField(
              controller: _tarifa,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSubmitted: (_) => _calcularComConta(),
              decoration: const InputDecoration(
                labelText: 'Tarifa em R\$ por kWh',
                hintText: 'Ex.: 0,85',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _calcularComConta, child: const Text('Calcular')),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: _uf,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: [for (final uf in _ufs) DropdownMenuItem(value: uf, child: Text(uf))],
              onChanged: _escolherUf,
            ),
            const SizedBox(height: 12),
            if (_uf != null && _distribuidoras == null) const Center(child: CircularProgressIndicator()),
            if (_distribuidoras != null)
              Expanded(
                child: ListView.separated(
                  itemCount: _distribuidoras!.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = _distribuidoras![i];
                    return ListTile(
                      title: Text(d.nome),
                      subtitle: Text('${reais(d.tarifaKwh, casas: 4)} por kWh'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _calcular(distribuidora: d),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}
