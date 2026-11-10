import 'package:flutter/material.dart';

import '../api.dart';
import '../tema.dart';
import 'comum.dart';
import 'distribuidora.dart';

/// Etapa 3: pergunta como o aparelho e usado, so quando a API pede.
/// Se o Inmetro ja informa o consumo mensal, pula direto para o estado.
/// Ventilador: a velocidade e, depois, as horas por dia (o Inmetro mede 1 h por dia).
class TelaUso extends StatefulWidget {
  final Consulta consulta;

  const TelaUso({super.key, required this.consulta});

  @override
  State<TelaUso> createState() => _TelaUsoState();
}

class _TelaUsoState extends State<TelaUso> {
  final _valor = TextEditingController();
  final _tempo = ControleTempo();
  PerguntaDeUso? _pergunta;
  String? _velocidade;
  bool _horasDoVentilador = false; // ja escolheu a velocidade, agora as horas
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _valor.dispose();
    _tempo.dispose();
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
        } else if (p.pergunta == 'horas') {
          _tempo.definir((p.padrao as num?)?.toDouble());
        } else if (p.padrao != null) {
          _valor.text = numero((p.padrao as num).toDouble(), casas: 0);
        }
      });
    } on ApiErro catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    }
  }

  void _seguir({bool substituir = false}) {
    final rota = MaterialPageRoute(builder: (_) => TelaEstado(consulta: widget.consulta));
    substituir ? Navigator.pushReplacement(context, rota) : Navigator.push(context, rota);
  }

  void _escolherVelocidade(String velocidade) {
    setState(() {
      _velocidade = velocidade;
      _erro = null;
      _horasDoVentilador = _pergunta!.perguntarHoras;
    });
    if (!_horasDoVentilador) _confirmar();
  }

  void _confirmar({bool pular = false}) {
    final c = widget.consulta;
    c.horasDia = c.ciclosMes = c.velocidade = null;
    switch (_pergunta!.pergunta) {
      case 'velocidade':
        c.velocidade = _velocidade;
        if (_pergunta!.perguntarHoras) {
          final horas = _tempo.horasDia;
          if (horas == null) {
            setState(() => _erro = 'Informe quanto tempo por dia ele fica ligado. Ex.: 8 h e 0 min.');
            return;
          }
          c.horasDia = horas;
        }
      case 'horas':
        if (pular) {
          _tempo.limpar();
          break;
        }
        if (_pergunta!.opcional && _tempo.vazio) break;
        final horas = _tempo.horasDia;
        if (horas == null) {
          setState(() => _erro = 'Informe quanto tempo por dia, em horas e minutos. Ex.: 0 h e 15 min.');
          return;
        }
        c.horasDia = horas;
      case 'ciclos':
        final ciclos = lerNumero(_valor.text);
        if (ciclos == null || ciclos < 0) {
          setState(() => _erro = 'Informe quantas vezes por mês. Ex.: 12.');
          return;
        }
        c.ciclosMes = ciclos;
    }
    setState(() => _erro = null);
    _seguir();
  }

  Widget? _rodape(PerguntaDeUso? p) {
    if (p == null || (p.pergunta == 'velocidade' && !_horasDoVentilador)) return null;
    final continuar = FilledButton(onPressed: _confirmar, child: const Text('Continuar'));
    if (!(p.pergunta == 'horas' && p.opcional)) return continuar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        continuar,
        const SizedBox(height: Espaco.p),
        TextButton(onPressed: () => _confirmar(pular: true), child: const Text('Não sei, usar o valor do Inmetro')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final p = _pergunta;
    final aparelho = widget.consulta.aparelho;
    final pagina = Pagina(
      titulo: 'Como você usa',
      etapa: etapaDoCalculo(widget.consulta, 3),
      rodape: _rodape(p),
      filho: ListView(
        children: [
          MergeSemantics(
            child: Row(
              children: [
                Icon(iconeDaCategoria(aparelho.categoria), size: t.iconeGrande),
                const SizedBox(width: Espaco.pm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(aparelho.nome, style: t.forte),
                      Text(
                        [
                          nomeDaCategoria(aparelho.categoria),
                          if (aparelho.detalhe.isNotEmpty) aparelho.detalhe,
                        ].join(' · '),
                        style: t.secundario,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Espaco.g),
          if (p == null && _erro == null) const Carregando(),
          if (p?.pergunta == 'velocidade' && !_horasDoVentilador) ...[
            const CabecalhoPergunta('Em qual velocidade você costuma usar?', ajuda: 'Toque na opção.'),
            for (final o in p!.opcoes)
              CartaoOpcao(
                titulo: nomeDaVelocidade(o),
                selecionada: o == _velocidade,
                onTap: () => _escolherVelocidade(o),
              ),
          ],
          if (_horasDoVentilador) ...[
            const CabecalhoPergunta(
              'Quanto tempo por dia ele fica ligado?',
              ajuda: 'Some o tempo de todos os usos do dia. Ex.: a noite toda = 8 h e 0 min.',
            ),
            CampoTempo(controle: _tempo, aoConfirmar: _confirmar),
          ],
          if (p?.pergunta == 'horas') ...[
            CabecalhoPergunta(
              'Quanto tempo por dia ele fica ligado?',
              ajuda: p!.opcional
                  ? 'Se não souber, toque em "Não sei" embaixo: usamos o consumo medido pelo Inmetro.'
                  : p.padrao != null
                  ? 'Já deixamos um valor comum preenchido. Troque pelo seu uso, se for diferente.'
                  : aparelho.categoria == 'chuveiro'
                  ? 'Some o tempo de todos os usos do dia. Ex.: dois banhos de 10 min = 0 h e 20 min.'
                  : 'Some o tempo de todos os usos do dia. Ex.: a noite toda = 8 h e 0 min.',
            ),
            CampoTempo(controle: _tempo, aoConfirmar: _confirmar),
          ],
          if (p?.pergunta == 'ciclos') ...[
            const CabecalhoPergunta(
              'Quantas vezes por mês você lava roupa?',
              ajuda: 'Já deixamos um valor comum preenchido. Troque pelo seu uso, se for diferente.',
            ),
            TextField(
              controller: _valor,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _confirmar(),
              decoration: const InputDecoration(labelText: 'Lavagens por mês', suffixText: 'vezes'),
            ),
          ],
          const SizedBox(height: Espaco.m),
          if (_erro != null) MensagemErro(_erro!, tentarDeNovo: p == null ? _carregar : null),
        ],
      ),
    );
    // voltar nas horas do ventilador volta para a velocidade
    return PopScope(
      canPop: !_horasDoVentilador,
      onPopInvokedWithResult: (saiu, _) {
        if (!saiu) {
          setState(() {
            _horasDoVentilador = false;
            _erro = null;
          });
        }
      },
      child: pagina,
    );
  }
}
