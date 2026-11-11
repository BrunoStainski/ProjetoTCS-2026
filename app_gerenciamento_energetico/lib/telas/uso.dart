import 'package:flutter/material.dart';

import '../api.dart';
import '../idioma.dart';
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
            setState(
              () => _erro = tr(
                'Informe quanto tempo por dia ele fica ligado. Ex.: 8 h e 0 min.',
                'Enter how long it stays on per day. E.g.: 8 h and 0 min.',
              ),
            );
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
          setState(
            () => _erro = tr(
              'Informe quanto tempo por dia, em horas e minutos. Ex.: 0 h e 15 min.',
              'Enter how long per day, in hours and minutes. E.g.: 0 h and 15 min.',
            ),
          );
          return;
        }
        c.horasDia = horas;
      case 'ciclos':
        final ciclos = lerNumero(_valor.text);
        if (ciclos == null || ciclos < 0) {
          setState(() => _erro = tr('Informe quantas vezes por mês. Ex.: 12.', 'Enter how many times per month. E.g.: 12.'));
          return;
        }
        c.ciclosMes = ciclos;
    }
    setState(() => _erro = null);
    _seguir();
  }

  Widget? _rodape(PerguntaDeUso? p) {
    if (p == null || (p.pergunta == 'velocidade' && !_horasDoVentilador)) return null;
    final continuar = FilledButton(onPressed: _confirmar, child: Text(tr('Continuar', 'Continue')));
    if (!(p.pergunta == 'horas' && p.opcional)) return continuar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        continuar,
        const SizedBox(height: Espaco.p),
        TextButton(
          onPressed: () => _confirmar(pular: true),
          child: Text(tr('Não sei, usar o valor do Inmetro', "I don't know, use Inmetro's value")),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final p = _pergunta;
    final aparelho = widget.consulta.aparelho;
    final pagina = Pagina(
      titulo: tr('Como você usa', 'How you use it'),
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
            CabecalhoPergunta(
              tr('Em qual velocidade você costuma usar?', 'Which speed do you usually use?'),
              ajuda: tr('Toque na opção.', 'Tap an option.'),
            ),
            for (final o in p!.opcoes)
              CartaoOpcao(
                titulo: nomeDaVelocidade(o),
                selecionada: o == _velocidade,
                onTap: () => _escolherVelocidade(o),
              ),
          ],
          if (_horasDoVentilador) ...[
            CabecalhoPergunta(
              tr('Quanto tempo por dia ele fica ligado?', 'How long does it stay on per day?'),
              ajuda: tr(
                'Some o tempo de todos os usos do dia. Ex.: a noite toda = 8 h e 0 min.',
                'Add up every use in the day. E.g.: all night = 8 h and 0 min.',
              ),
            ),
            CampoTempo(controle: _tempo, aoConfirmar: _confirmar),
          ],
          if (p?.pergunta == 'horas') ...[
            CabecalhoPergunta(
              tr('Quanto tempo por dia ele fica ligado?', 'How long does it stay on per day?'),
              ajuda: p!.opcional
                  ? tr(
                      'Se não souber, toque em "Não sei" embaixo: usamos o consumo medido pelo Inmetro.',
                      'If you are not sure, tap "I don\'t know" below: we use the consumption measured by Inmetro.',
                    )
                  : p.padrao != null
                  ? tr(
                      'Já deixamos um valor comum preenchido. Troque pelo seu uso, se for diferente.',
                      'We filled in a typical value. Change it to your own use if it is different.',
                    )
                  : aparelho.categoria == 'chuveiro'
                  ? tr(
                      'Some o tempo de todos os usos do dia. Ex.: dois banhos de 10 min = 0 h e 20 min.',
                      'Add up every use in the day. E.g.: two 10-minute showers = 0 h and 20 min.',
                    )
                  : tr(
                      'Some o tempo de todos os usos do dia. Ex.: a noite toda = 8 h e 0 min.',
                      'Add up every use in the day. E.g.: all night = 8 h and 0 min.',
                    ),
            ),
            CampoTempo(controle: _tempo, aoConfirmar: _confirmar),
          ],
          if (p?.pergunta == 'ciclos') ...[
            CabecalhoPergunta(
              tr('Quantas vezes por mês você lava roupa?', 'How many loads of laundry do you do per month?'),
              ajuda: tr(
                'Já deixamos um valor comum preenchido. Troque pelo seu uso, se for diferente.',
                'We filled in a typical value. Change it to your own use if it is different.',
              ),
            ),
            TextField(
              controller: _valor,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _confirmar(),
              decoration: InputDecoration(
                labelText: tr('Lavagens por mês', 'Loads per month'),
                suffixText: tr('vezes', 'times'),
              ),
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
