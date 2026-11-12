import 'package:flutter/material.dart';

import '../api.dart';
import '../idioma.dart';
import '../tema.dart';
import 'comum.dart';
import 'distribuidora.dart';

/// Etapa 3: pergunta como o aparelho e usado, so quando a API pede.
/// Se o Inmetro ja informa o consumo mensal, pula direto para o estado.
/// Ventilador: a velocidade e, depois, as horas por dia (o Inmetro mede 1 h por dia).
class UsageScreen extends StatefulWidget {
  final Query query;

  const UsageScreen({super.key, required this.query});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  final _value = TextEditingController();
  final _time = TimeControl();
  UsageQuestion? _question;
  String? _speed;
  bool _fanHours = false; // ja escolheu a velocidade, agora as horas
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _value.dispose();
    _time.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await Api.usageQuestion(widget.query.appliance.id);
      if (!mounted) return;
      if (p.question == null) {
        _follow(substitute: true);
        return;
      }
      setState(() {
        _question = p;
        if (p.question == 'velocidade') {
          _speed = p.defaults as String?;
        } else if (p.question == 'horas') {
          _time.define((p.defaults as num?)?.toDouble());
        } else if (p.defaults != null) {
          _value.text = number((p.defaults as num).toDouble(), homes: 0);
        }
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _follow({bool substitute = false}) {
    final route = MaterialPageRoute(builder: (_) => StateScreen(query: widget.query));
    substitute ? Navigator.pushReplacement(context, route) : Navigator.push(context, route);
  }

  void _chooseSpeed(String speed) {
    setState(() {
      _speed = speed;
      _error = null;
      _fanHours = _question!.askHours;
    });
    if (!_fanHours) _confirm();
  }

  void _confirm({bool skip = false}) {
    final c = widget.query;
    c.dailyHours = c.monthlyCycles = c.speed = null;
    switch (_question!.question) {
      case 'velocidade':
        c.speed = _speed;
        if (_question!.askHours) {
          final hours = _time.dailyHours;
          if (hours == null) {
            setState(
              () => _error = tr(
                'Informe quanto tempo por dia ele fica ligado. Ex.: 8 h e 0 min.',
                'Enter how long it stays on per day. E.g.: 8 h and 0 min.',
              ),
            );
            return;
          }
          c.dailyHours = hours;
        }
      case 'horas':
        if (skip) {
          _time.clear();
          break;
        }
        if (_question!.optional && _time.isEmpty) break;
        final hours = _time.dailyHours;
        if (hours == null) {
          setState(
            () => _error = tr(
              'Informe quanto tempo por dia, em horas e minutos. Ex.: 0 h e 15 min.',
              'Enter how long per day, in hours and minutes. E.g.: 0 h and 15 min.',
            ),
          );
          return;
        }
        c.dailyHours = hours;
      case 'ciclos':
        final cycles = readNumber(_value.text);
        if (cycles == null || cycles < 0) {
          setState(() => _error = tr('Informe quantas vezes por mês. Ex.: 12.', 'Enter how many times per month. E.g.: 12.'));
          return;
        }
        c.monthlyCycles = cycles;
    }
    setState(() => _error = null);
    _follow();
  }

  Widget? _footer(UsageQuestion? p) {
    if (p == null || (p.question == 'velocidade' && !_fanHours)) return null;
    final proceed = FilledButton(onPressed: _confirm, child: Text(tr('Continuar', 'Continue')));
    if (!(p.question == 'horas' && p.optional)) return proceed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        proceed,
        const SizedBox(height: Spacing.p),
        TextButton(
          onPressed: () => _confirm(skip: true),
          child: Text(tr('Não sei, usar o valor do Inmetro', "I don't know, use Inmetro's value")),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final p = _question;
    final appliance = widget.query.appliance;
    final page = AppPage(
      title: tr('Como você usa', 'How you use it'),
      step: calculationStep(widget.query, 3),
      footer: _footer(p),
      child: ListView(
        children: [
          MergeSemantics(
            child: Row(
              children: [
                Icon(categoryIcon(appliance.category), size: t.largeIcon),
                const SizedBox(width: Spacing.pm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(appliance.name, style: t.strong),
                      Text(
                        [
                          categoryName(appliance.category),
                          if (appliance.detail.isNotEmpty) appliance.detail,
                        ].join(' · '),
                        style: t.secondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.g),
          if (p == null && _error == null) const Loading(),
          if (p?.question == 'velocidade' && !_fanHours) ...[
            QuestionHeader(
              tr('Em qual velocidade você costuma usar?', 'Which speed do you usually use?'),
              help: tr('Toque na opção.', 'Tap an option.'),
            ),
            for (final o in p!.options)
              OptionCard(
                title: speedName(o),
                selected: o == _speed,
                onTap: () => _chooseSpeed(o),
              ),
          ],
          if (_fanHours) ...[
            QuestionHeader(
              tr('Quanto tempo por dia ele fica ligado?', 'How long does it stay on per day?'),
              help: tr(
                'Some o tempo de todos os usos do dia. Ex.: a noite toda = 8 h e 0 min.',
                'Add up every use in the day. E.g.: all night = 8 h and 0 min.',
              ),
            ),
            TimeField(control: _time, onConfirm: _confirm),
          ],
          if (p?.question == 'horas') ...[
            QuestionHeader(
              tr('Quanto tempo por dia ele fica ligado?', 'How long does it stay on per day?'),
              help: p!.optional
                  ? tr(
                      'Se não souber, toque em "Não sei" embaixo: usamos o consumo medido pelo Inmetro.',
                      'If you are not sure, tap "I don\'t know" below: we use the consumption measured by Inmetro.',
                    )
                  : p.defaults != null
                  ? tr(
                      'Já deixamos um valor comum preenchido. Troque pelo seu uso, se for diferente.',
                      'We filled in a typical value. Change it to your own use if it is different.',
                    )
                  : appliance.category == 'chuveiro'
                  ? tr(
                      'Some o tempo de todos os usos do dia. Ex.: dois banhos de 10 min = 0 h e 20 min.',
                      'Add up every use in the day. E.g.: two 10-minute showers = 0 h and 20 min.',
                    )
                  : tr(
                      'Some o tempo de todos os usos do dia. Ex.: a noite toda = 8 h e 0 min.',
                      'Add up every use in the day. E.g.: all night = 8 h and 0 min.',
                    ),
            ),
            TimeField(control: _time, onConfirm: _confirm),
          ],
          if (p?.question == 'ciclos') ...[
            QuestionHeader(
              tr('Quantas vezes por mês você lava roupa?', 'How many loads of laundry do you do per month?'),
              help: tr(
                'Já deixamos um valor comum preenchido. Troque pelo seu uso, se for diferente.',
                'We filled in a typical value. Change it to your own use if it is different.',
              ),
            ),
            TextField(
              controller: _value,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _confirm(),
              decoration: InputDecoration(
                labelText: tr('Lavagens por mês', 'Loads per month'),
                suffixText: tr('vezes', 'times'),
              ),
            ),
          ],
          const SizedBox(height: Spacing.m),
          if (_error != null) ErrorMessage(_error!, tryAgain: p == null ? _load : null),
        ],
      ),
    );
    // voltar nas horas do ventilador volta para a velocidade
    return PopScope(
      canPop: !_fanHours,
      onPopInvokedWithResult: (left, _) {
        if (!left) {
          setState(() {
            _fanHours = false;
            _error = null;
          });
        }
      },
      child: page,
    );
  }
}
