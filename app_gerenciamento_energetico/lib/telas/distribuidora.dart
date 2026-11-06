import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../tema.dart';
import 'comum.dart';
import 'resultado.dart';

/// Passo 3: estado + distribuidora, ou a tarifa da conta de luz.
/// Se o usuario ja escolheu uma tarifa antes, oferece usar a mesma.
class TelaDistribuidora extends StatefulWidget {
  final Consulta consulta;

  const TelaDistribuidora({super.key, required this.consulta});

  @override
  State<TelaDistribuidora> createState() => _TelaDistribuidoraState();
}

class _TelaDistribuidoraState extends State<TelaDistribuidora> {
  final _tarifa = TextEditingController();
  final _filtro = TextEditingController();
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
    _filtro.dispose();
    super.dispose();
  }

  Future<void> _carregarUfs() async {
    try {
      final ufs = await Api.ufs();
      if (!mounted) return;
      setState(() {
        _ufs = ufs;
        _erro = null;
      });
    } on ApiErro catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    }
  }

  Future<void> _escolherUf(String? uf) async {
    setState(() {
      _uf = uf;
      _distribuidoras = null;
      _filtro.clear();
    });
    if (uf == null) return;
    try {
      final lista = await Api.distribuidoras(uf: uf);
      if (mounted) setState(() => _distribuidoras = lista);
    } on ApiErro catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    }
  }

  void _calcular(EscolhaTarifa tarifa) {
    widget.consulta.tarifa = tarifa;
    casa.lembrarTarifa(tarifa);
    Navigator.push(context, MaterialPageRoute(builder: (_) => TelaResultado(consulta: widget.consulta)));
  }

  void _calcularComConta() {
    final tarifa = lerNumero(_tarifa.text);
    if (tarifa == null || tarifa <= 0) {
      setState(() => _erro = 'Informe a tarifa em R\$/kWh (ex.: 0,85).');
      return;
    }
    setState(() => _erro = null);
    _calcular(EscolhaTarifa.manual(tarifa));
  }

  List<Distribuidora> get _filtradas {
    final alvo = _filtro.text.trim().toLowerCase();
    final lista = _distribuidoras ?? const [];
    return alvo.isEmpty ? lista : lista.where((d) => d.nome.toLowerCase().contains(alvo)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ultima = casa.ultimaTarifa;
    return Pagina(
      titulo: 'Qual é a sua distribuidora?',
      passo: 3,
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ultima != null) ...[
            Card(
              color: Cores.amareloEscuro,
              child: ListTile(
                leading: const Icon(Icons.bolt),
                title: Text('Usar a mesma: ${ultima.descricao}'),
                subtitle: Text('${reais(ultima.tarifaKwh, casas: 4)} por kWh', style: const TextStyle(color: Cores.cinza)),
                trailing: const Icon(Icons.chevron_right, color: Cores.amarelo),
                onTap: () => _calcular(ultima),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Ou escolha outra:', style: TextStyle(color: Cores.cinza)),
          ] else
            const Text('A distribuidora aparece na sua conta de luz.', style: TextStyle(color: Cores.cinza)),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Distribuidora'), icon: Icon(Icons.map_outlined)),
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
                helperText: 'Valor total da conta dividido pelos kWh consumidos no mês.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _calcularComConta, child: const Text('Calcular')),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: _uf,
              dropdownColor: Cores.superficieAlta,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: [for (final uf in _ufs) DropdownMenuItem(value: uf, child: Text(uf))],
              onChanged: _escolherUf,
            ),
            const SizedBox(height: 12),
            if (_uf != null && _distribuidoras == null) const Center(child: CircularProgressIndicator()),
            if ((_distribuidoras?.length ?? 0) > 5) ...[
              TextField(
                controller: _filtro,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Filtrar pelo nome', prefixIcon: Icon(Icons.search)),
              ),
              const SizedBox(height: 8),
            ],
            if (_distribuidoras != null)
              Expanded(
                child: ListView.separated(
                  itemCount: _filtradas.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = _filtradas[i];
                    return ListTile(
                      title: Text(d.nome),
                      subtitle: Text('${reais(d.tarifaKwh, casas: 4)} por kWh', style: const TextStyle(color: Cores.cinza)),
                      trailing: const Icon(Icons.chevron_right, color: Cores.cinza),
                      onTap: () => _calcular(EscolhaTarifa.daDistribuidora(d)),
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
