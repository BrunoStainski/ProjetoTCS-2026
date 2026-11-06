import 'package:flutter/material.dart';

import '../api.dart';
import 'comum.dart';
import 'distribuidora.dart';

/// Passo 2: pergunta como o aparelho e usado, so quando a API pede.
/// Se o Inmetro ja informa o consumo mensal, pula direto para a distribuidora.
class TelaUso extends StatefulWidget {
  final Consulta consulta;

  const TelaUso({super.key, required this.consulta});

  @override
  State<TelaUso> createState() => _TelaUsoState();
}

class _TelaUsoState extends State<TelaUso> {
  final _valor = TextEditingController();
  PerguntaDeUso? _pergunta;
  String? _velocidade;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _erro = null);
    try {
      final p = await Api.perguntaDeUso(widget.consulta.aparelho.id);
      if (!mounted) return;
      if (p.pergunta == null) {
        _seguir(substituir: true);
        return;
      }
      setState(() {
        _pergunta = p;
        if (p.pergunta == 'velocidade') {
          _velocidade = p.padrao as String?;
        } else if (p.padrao != null) {
          _valor.text = numero((p.padrao as num).toDouble(), casas: p.pergunta == 'ciclos' ? 0 : 2);
        }
      });
    } on ApiErro catch (e) {
      setState(() => _erro = e.mensagem);
    }
  }

  void _seguir({bool substituir = false}) {
    final rota = MaterialPageRoute(builder: (_) => TelaDistribuidora(consulta: widget.consulta));
    substituir ? Navigator.pushReplacement(context, rota) : Navigator.push(context, rota);
  }

  void _confirmar() {
    final c = widget.consulta;
    c.horasDia = c.ciclosMes = c.velocidade = null;
    switch (_pergunta!.pergunta) {
      case 'velocidade':
        c.velocidade = _velocidade;
      case 'horas':
        final horas = lerNumero(_valor.text);
        if (horas == null || horas < 0 || horas > 24) {
          setState(() => _erro = 'Informe as horas por dia, entre 0 e 24 (ex.: 0,25 = 15 minutos).');
          return;
        }
        c.horasDia = horas;
      case 'ciclos':
        final ciclos = lerNumero(_valor.text);
        if (ciclos == null || ciclos < 0) {
          setState(() => _erro = 'Informe quantas vezes por mês.');
          return;
        }
        c.ciclosMes = ciclos;
    }
    setState(() => _erro = null);
    _seguir();
  }

  @override
  Widget build(BuildContext context) {
    final p = _pergunta;
    final aparelho = widget.consulta.aparelho;
    return Pagina(
      titulo: 'Como você usa?',
      passo: 2,
      filho: ListView(
        children: [
          Text(aparelho.nome, style: Theme.of(context).textTheme.titleLarge),
          Text([aparelho.categoriaLegivel, if (aparelho.detalhe.isNotEmpty) aparelho.detalhe].join(' - ')),
          const SizedBox(height: 24),
          if (p == null && _erro == null) const Center(child: CircularProgressIndicator()),
          if (p?.pergunta == 'velocidade') ...[
            const Text('Em qual velocidade você costuma usar?'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [for (final o in p!.opcoes) ButtonSegment(value: o, label: Text(o))],
              selected: {?_velocidade},
              onSelectionChanged: (s) => setState(() => _velocidade = s.first),
            ),
          ],
          if (p?.pergunta == 'horas' || p?.pergunta == 'ciclos')
            TextField(
              controller: _valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSubmitted: (_) => _confirmar(),
              decoration: InputDecoration(
                labelText: p!.pergunta == 'horas' ? 'Horas por dia' : 'Lavagens por mês',
                helperText: p.padrao != null
                    ? 'Valor sugerido é uma estimativa. Troque pelo seu uso real.'
                    : 'Obrigatório para este aparelho. Ex.: 0,25 = 15 minutos.',
              ),
            ),
          const SizedBox(height: 16),
          if (_erro != null) MensagemErro(_erro!, tentarDeNovo: p == null ? _carregar : null),
          if (p != null) FilledButton(onPressed: _confirmar, child: const Text('Continuar')),
        ],
      ),
    );
  }
}
