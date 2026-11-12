// Estimativa de aparelho fora do catalogo do Inmetro (antigo ou sem modelo), uma pergunta por tela.
// As perguntas dependem das respostas (geladeira pergunta o ano; eletroportatil, a potencia...).
// Eletro grande: tipo e tamanho (servem para comparar com modelos novos) e depois o numero escrito no
// proprio aparelho (vale para aparelho antigo); sem ele, o gasto sai dos modelos parecidos do catalogo.
// Voltar (seta ou botao do celular) volta uma pergunta, sem perder o que ja foi respondido.

import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../idioma.dart';
import '../tema.dart';
import 'comum.dart';
import 'distribuidora.dart';

enum Group { heavy, smallAppliance }

Map<String, String> get fridgeTypes => {
  'duplex': tr('Geladeira duplex (2 portas)', 'Two-door fridge (top freezer)'),
  '1_porta': tr('Geladeira 1 porta', 'One-door fridge'),
  'frigobar': tr('Frigobar', 'Mini fridge'),
  'freezer_vertical': tr('Freezer vertical', 'Upright freezer'),
  'freezer_horizontal': tr('Freezer horizontal', 'Chest freezer'),
};

/// Uma pergunta da estimativa. Sem `validar`, e uma escolha: tocar numa opcao ja avanca.
class _Question {
  final String title;
  final String? help;
  final List<Widget> fields;
  final String? Function()? validate;
  final String? skipText;
  final VoidCallback? onSkip;

  const _Question(this.title, {this.help, required this.fields, this.validate, this.skipText, this.onSkip});
}

class EstimateScreen extends StatefulWidget {
  final Future<List<EstimableCategory>> Function() loadCategories;
  final Future<List<Resistive>> Function() loadResistive;

  const EstimateScreen({
    super.key,
    this.loadCategories = Api.estimableCategories,
    this.loadResistive = Api.resistive,
  });

  @override
  State<EstimateScreen> createState() => _EstimateScreenState();
}

class _EstimateScreenState extends State<EstimateScreen> {
  int _index = 0;
  bool _forward = true; // sentido da ultima troca de pergunta (define de que lado a proxima entra)
  String? _error;
  bool _failedLoad = false;

  Group? _group;
  List<EstimableCategory>? _categories;
  EstimableCategory? _category;

  String? _fridgeType;
  bool? _frostFree;
  final _freezer = TextEditingController();
  final _year = TextEditingController();

  EntryMode? _shape; // numero que a pessoa achou no aparelho
  bool _withoutNumber = false; // nao achou: usa tipo e tamanho
  String? _type;
  double? _size;
  bool _otherSize = false;
  final _measure = TextEditingController();
  final _label = TextEditingController();
  final _time = TimeControl();
  final _cycles = TextEditingController();
  String? _speed;
  final _name = TextEditingController();

  List<Resistive>? _resistiveItems;
  Resistive? _resistive;
  final _power = TextEditingController();
  final _smallApplianceTime = TimeControl();
  final _days = TextEditingController();

  bool get _fridge => _category?.special ?? false;
  bool get _freezerOnly => _fridgeType?.startsWith('freezer') ?? false;
  bool get _withPower => _shape?.field == 'potencia_w';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_freezer, _year, _measure, _label, _cycles, _name, _power, _days]) {
      c.dispose();
    }
    _time.dispose();
    _smallApplianceTime.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _failedLoad = false;
    });
    try {
      final categories = await widget.loadCategories();
      final resistive = await widget.loadResistive();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _resistiveItems = resistive;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failedLoad = true;
          _error = tr(
            'Não consegui carregar a lista de aparelhos. Confira a internet e tente de novo.',
            'Could not load the list of appliances. Check your internet connection and try again.',
          );
        });
      }
    }
  }

  // ---------- respostas ----------

  void _chooseGroup(Group g) {
    if (_group != g) {
      _category = null;
      _resistive = null;
    }
    _group = g;
    _advance();
  }

  void _chooseCategory(EstimableCategory c) {
    if (_category?.category != c.category) {
      _shape = c.requiredValue && c.shapes.isNotEmpty ? c.shapes.first : null;
      _withoutNumber = false;
      _type = null;
      _size = null;
      _otherSize = false;
      _fridgeType = null;
      _frostFree = null;
      _measure.clear();
      _label.clear();
      final usage = c.usage;
      _time.define(usage.question == 'horas' ? (usage.defaults as num?)?.toDouble() : null);
      _cycles.text = usage.question == 'ciclos' && usage.defaults != null
          ? number((usage.defaults as num).toDouble(), homes: 0)
          : '';
      _speed = usage.question == 'velocidade' ? usage.defaults as String? : null;
    }
    _category = c;
    _advance();
  }

  void _chooseResistive(Resistive r) {
    if (_resistive?.category != r.category) {
      _power.clear();
      _smallApplianceTime.define(r.dailyHours);
      _days.text = number(r.daysPerMonth, homes: 0);
    }
    _resistive = r;
    _advance();
  }

  void _chooseShape(EntryMode? shape) {
    if (shape?.field != _shape?.field) _label.clear();
    _shape = shape;
    _withoutNumber = shape == null;
    _advance();
  }

  void _chooseSize(double? size) {
    _size = size;
    _otherSize = size == null;
    _advance();
  }

  void _choose(VoidCallback applyChange) {
    applyChange();
    _advance();
  }

  double? _optional(TextEditingController c) => c.text.trim().isEmpty ? null : readNumber(c.text);

  bool _invalid(TextEditingController c, {double minimum = 0, double maximum = double.infinity}) {
    if (c.text.trim().isEmpty) return false;
    final v = readNumber(c.text);
    return v == null || v <= minimum || v > maximum;
  }

  (String?, String?) _brandAndModel() {
    final parts = _name.text.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return (null, null);
    return (parts.first, parts.length > 1 ? parts.skip(1).join(' ') : null);
  }

  // ---------- navegacao entre as perguntas ----------

  void _advance() {
    final last = _index >= _questions().length - 1;
    setState(() {
      _error = null;
      _forward = true;
      if (!last) _index++;
    });
    if (last) _finish();
  }

  void _back() => setState(() {
    _error = null;
    _forward = false;
    _index--;
  });

  void _continue(_Question p) {
    final error = p.validate!();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _advance();
  }

  void _skip(_Question p) {
    p.onSkip?.call();
    _advance();
  }

  void _finish() {
    final query = switch (_group) {
      Group.smallAppliance => _smallApplianceQuery(),
      _ => _fridge ? _fridgeQuery() : _heavyQuery(_category!),
    };
    Navigator.push(context, MaterialPageRoute(builder: (_) => StateScreen(query: query)));
  }

  Query _fridgeQuery() {
    final (brand, model) = _brandAndModel();
    return Query(
      Appliance(id: 0, category: 'refrigerador', brand: brand ?? tr('Geladeira', 'Fridge'), model: model ?? ''),
      estimation: Estimate(fridgeRoute, {
        'tipo': _fridgeType,
        'frost_free': _frostFree ?? false,
        'volume_total_l': readNumber(_measure.text),
        'volume_congelador_l': _freezerOnly ? null : _optional(_freezer),
        'ano_compra': int.tryParse(_year.text.trim()),
        'kwh_etiqueta': _optional(_label),
        'marca': brand,
        'modelo': model,
      }),
    );
  }

  Query _heavyQuery(EstimableCategory c) {
    final (brand, model) = _brandAndModel();
    final asksHours = c.usage.question == 'horas' || c.usage.askHours;
    return Query(
      Appliance(id: 0, category: c.category, brand: brand ?? c.name, model: model ?? ''),
      estimation: Estimate(estimatedRoute, {
        'categoria': c.category,
        'tipo': _type,
        'medida': c.measure == null ? null : (_otherSize ? _optional(_measure) : _size),
        'valor_etiqueta': _shape == null ? null : _optional(_label),
        'campo_etiqueta': _shape?.field,
        'marca': brand,
        'modelo': model,
      }),
      dailyHours: asksHours ? _time.dailyHours : null,
      monthlyCycles: c.usage.question == 'ciclos' ? readNumber(_cycles.text) : null,
      speed: c.usage.question == 'velocidade' && _withoutNumber ? _speed : null,
    );
  }

  Query _smallApplianceQuery() {
    final r = _resistive!;
    return Query(
      Appliance(id: 0, category: r.category, brand: r.name, model: ''),
      estimation: Estimate(resistiveRoute, {
        'categoria': r.category,
        'potencia_w': _optional(_power),
        'dias_mes': _optional(_days),
      }),
      dailyHours: _smallApplianceTime.dailyHours,
    );
  }

  // ---------- as perguntas ----------

  List<_Question> _questions() {
    return [
      _groupQuestion(),
      if (_group == Group.smallAppliance) ..._smallApplianceQuestions(),
      if (_group == Group.heavy) ...[
        _heavyApplianceQuestion(),
        if (_category != null) ...(_fridge ? _fridgeQuestions() : _categoryQuestions(_category!)),
        if (_category != null) _nameQuestion(),
      ],
    ];
  }

  _Question _groupQuestion() => _Question(
    tr('Que tipo de aparelho é?', 'What kind of appliance is it?'),
    help: tr(
      'Para aparelhos que não estão no catálogo do Inmetro. Calculamos um gasto aproximado '
          'com o que você souber.',
      "For appliances that are not in Inmetro's catalog. We calculate an approximate cost "
          'with whatever you know.',
    ),
    fields: [
      OptionCard(
        icon: Icons.kitchen,
        title: tr('Eletrodoméstico grande', 'Large appliance'),
        subtitle: tr(
          'Geladeira, máquina de lavar, ar-condicionado, chuveiro, TV...',
          'Fridge, washing machine, air conditioner, electric shower, TV...',
        ),
        selected: _group == Group.heavy,
        onTap: () => _chooseGroup(Group.heavy),
      ),
      OptionCard(
        icon: Icons.blender_outlined,
        title: tr('Eletroportátil', 'Small appliance'),
        subtitle: tr(
          'Air fryer, secador de cabelo, ferro de passar, cafeteira...',
          'Air fryer, hair dryer, clothes iron, coffee maker...',
        ),
        selected: _group == Group.smallAppliance,
        onTap: () => _chooseGroup(Group.smallAppliance),
      ),
    ],
  );

  _Question _heavyApplianceQuestion() => _Question(
    tr('Qual é o aparelho?', 'Which appliance is it?'),
    fields: [
      for (final c in _categories!)
        OptionCard(
          icon: categoryIcon(c.category),
          title: c.name,
          selected: _category?.category == c.category,
          onTap: () => _chooseCategory(c),
        ),
    ],
  );

  List<_Question> _fridgeQuestions() => [
    _Question(
      tr('Qual é o tipo?', 'What type is it?'),
      fields: [
        for (final MapEntry(key: kind, value: name) in fridgeTypes.entries)
          OptionCard(
            title: name,
            selected: _fridgeType == kind,
            onTap: () => _choose(() => _fridgeType = kind),
          ),
      ],
    ),
    _Question(
      tr('Ela forma gelo nas paredes?', 'Does ice build up on the walls?'),
      help: tr(
        'Quem não forma gelo é "frost-free" e não precisa degelar.',
        'If no ice builds up, it is "frost-free" and never needs defrosting.',
      ),
      fields: [
        OptionCard(
          title: tr('Não forma gelo (frost-free)', 'No ice builds up (frost-free)'),
          subtitle: tr('Não precisa degelar.', 'No defrosting needed.'),
          selected: _frostFree == true,
          onTap: () => _choose(() => _frostFree = true),
        ),
        OptionCard(
          title: tr('Forma gelo', 'Ice builds up'),
          subtitle: tr('Precisa degelar de vez em quando.', 'Needs defrosting now and then.'),
          selected: _frostFree == false,
          onTap: () => _choose(() => _frostFree = false),
        ),
      ],
    ),
    _Question(
      tr('Qual é a capacidade total?', 'What is the total capacity?'),
      help: tr(
        'Em litros. Está na etiqueta dentro da porta ou no manual.',
        'In liters. It is on the label inside the door or in the manual.',
      ),
      fields: [
        _field(
          _measure,
          tr('Capacidade total', 'Total capacity'),
          suffix: tr('litros', 'liters'),
          example: tr('Ex.: 407', 'E.g.: 407'),
        ),
      ],
      validate: () {
        final volume = readNumber(_measure.text);
        return volume == null || volume <= 0 || volume > 1000
            ? tr(
                'Digite a capacidade total em litros (está na etiqueta ou no manual).',
                'Enter the total capacity in liters (it is on the label or in the manual).',
              )
            : null;
      },
    ),
    if (!_freezerOnly)
      _Question(
        tr('Quantos litros tem o freezer?', 'How many liters is the freezer?'),
        help: tr(
          'Melhora a estimativa. Se não souber, toque em "Não sei".',
          'It improves the estimate. If you are not sure, tap "I don\'t know".',
        ),
        fields: [
          _field(
            _freezer,
            tr('Litros do freezer', 'Freezer liters'),
            suffix: tr('litros', 'liters'),
            example: tr('Ex.: 90', 'E.g.: 90'),
          ),
        ],
        validate: () {
          final volume = readNumber(_measure.text) ?? 0;
          final freezer = _optional(_freezer);
          return _invalid(_freezer, minimum: -1) || (freezer ?? 0) > volume
              ? tr(
                  'Os litros do freezer precisam ser menores que a capacidade total.',
                  'The freezer liters must be less than the total capacity.',
                )
              : null;
        },
        skipText: tr('Não sei', "I don't know"),
        onSkip: _freezer.clear,
      ),
    _Question(
      tr('Em que ano você comprou?', 'What year did you buy it?'),
      help: tr('Geladeiras mais antigas costumam gastar mais.', 'Older fridges usually use more energy.'),
      fields: [_field(_year, tr('Ano de compra', 'Year of purchase'), example: tr('Ex.: 2014', 'E.g.: 2014'), whole: true)],
      validate: () {
        final year = int.tryParse(_year.text.trim());
        final currentYear = DateTime.now().year;
        return year == null || year < 1980 || year > currentYear
            ? tr(
                'Digite o ano de compra entre 1980 e $currentYear. Ex.: 2014.',
                'Enter a year of purchase between 1980 and $currentYear. E.g.: 2014.',
              )
            : null;
      },
    ),
    _Question(
      tr('Tem a etiqueta amarela do Inmetro?', "Does it have Inmetro's yellow energy label?"),
      help: tr(
        'É o número em kWh por mês da etiqueta colada no aparelho. Com ele o resultado fica bem mais preciso.',
        'It is the kWh per month number on the label stuck to the appliance. With it the result is much more accurate.',
      ),
      fields: [
        _field(
          _label,
          tr('Consumo da etiqueta', 'Consumption on the label'),
          suffix: tr('kWh/mês', 'kWh/month'),
          example: tr('Ex.: 52,5', 'E.g.: 52.5'),
        ),
      ],
      validate: () => _invalid(_label, maximum: 300)
          ? tr('Digite o número em kWh por mês. Ex.: 52,5.', 'Enter the number in kWh per month. E.g.: 52.5.')
          : null,
      skipText: tr('Não tenho a etiqueta', "I don't have the label"),
      onSkip: _label.clear,
    ),
  ];

  List<_Question> _categoryQuestions(EstimableCategory c) {
    final shape = _shape;
    return [
      if (c.types.isNotEmpty)
        _Question(
          tr('Qual destes é o seu?', 'Which of these is yours?'),
          fields: [
            for (final kind in c.types)
              OptionCard(
                title: kind.name,
                subtitle: kind.description,
                selected: _type == kind.value,
                onTap: () => _choose(() => _type = kind.value),
              ),
          ],
        ),
      if (c.measure != null) _sizeQuestion(c),
      if (c.measure != null && _otherSize)
        _Question(
          tr('Digite o tamanho', 'Enter the size'),
          help: tr(
            '${readable(c.measure!)}. Costuma estar escrito no aparelho, na caixa ou no manual.',
            '${readable(c.measure!)}. It is usually written on the appliance, the box or in the manual.',
          ),
          fields: [_field(_measure, readable(c.measure!).split(' (').first, suffix: c.measureUnit)],
          validate: () => _optional(_measure) == null || _invalid(_measure)
              ? tr(
                  'Digite o número, como está escrito. Se não souber, volte e escolha um dos tamanhos.',
                  'Enter the number as it is written. If you are not sure, go back and pick one of the sizes.',
                )
              : null,
        ),
      if (!c.requiredValue) _shapeQuestion(c),
      if (shape != null) _valueQuestion(shape),
      ..._usageQuestions(c.usage, requiredHours: _withPower, withoutSpeed: !_withoutNumber),
    ];
  }

  _Question _shapeQuestion(EstimableCategory c) => _Question(
    tr('Você consegue ver algum destes no aparelho?', 'Can you see any of these on the appliance?'),
    help: tr(
      'Com o número do próprio aparelho o cálculo fica certo, mesmo se ele for antigo.',
      "With the appliance's own number the calculation is accurate, even if it is old.",
    ),
    fields: [
      for (final f in c.shapes)
        OptionCard(
          icon: f.field == 'potencia_w' ? Icons.bolt : Icons.receipt_long_outlined,
          title: f.name,
          subtitle: f.where,
          selected: _shape?.field == f.field,
          onTap: () => _chooseShape(f),
        ),
      OptionCard(
        icon: Icons.help_outline,
        title: tr('Não consigo ver nenhum', "I can't see any"),
        subtitle: c.measure == null
            ? tr(
                'Tudo bem: calculamos com os modelos do catálogo do Inmetro.',
                "That's fine: we calculate with the models in Inmetro's catalog.",
              )
            : tr(
                'Tudo bem: calculamos com os modelos parecidos do Inmetro.',
                "That's fine: we calculate with similar models from Inmetro.",
              ),
        selected: _withoutNumber,
        onTap: () => _chooseShape(null),
      ),
    ],
  );

  _Question _valueQuestion(EntryMode f) => _Question(
    f.field == 'potencia_w'
        ? tr('Qual é a potência?', 'What is the power?')
        : tr('Qual é o consumo de energia?', 'What is the energy consumption?'),
    help: [f.where, if (f.tip != null) f.tip!].join(' '),
    fields: [_field(_label, f.label, suffix: f.unit, example: f.example)],
    validate: () {
      final v = _optional(_label);
      return v == null || _invalid(_label, maximum: f.maximum)
          ? tr(
              'Digite o número em ${f.unit}, como está escrito. ${f.example}.',
              'Enter the number in ${f.unit}, as it is written. ${f.example}.',
            )
          : null;
    },
  );

  _Question _sizeQuestion(EstimableCategory c) => _Question(
    tr('Qual é o tamanho?', 'What size is it?'),
    help: tr(
      '${readable(c.measure!)}. Costuma estar escrito no aparelho, na caixa ou no manual.',
      '${readable(c.measure!)}. It is usually written on the appliance, the box or in the manual.',
    ),
    fields: [
      for (final t in c.sizes)
        OptionCard(
          title: t.name,
          selected: !_otherSize && _size == t.value,
          onTap: () => _chooseSize(t.value),
        ),
      OptionCard(
        icon: Icons.edit_outlined,
        title: tr('Outro tamanho', 'Another size'),
        subtitle: tr('Digitar o número', 'Type the number'),
        selected: _otherSize,
        onTap: () => _chooseSize(null),
      ),
    ],
  );

  /// requiredHours: com a potencia da plaqueta, so as horas dizem quanto gasta.
  /// withoutSpeed: com a potencia, a velocidade do ventilador nao entra na conta.
  List<_Question> _usageQuestions(UsageQuestion usage, {bool requiredHours = false, bool withoutSpeed = false}) {
    final optional = usage.optional && !requiredHours;
    final hours = _Question(
      tr('Quanto tempo por dia ele fica ligado?', 'How long does it stay on per day?'),
      help: usage.askHours
          ? tr(
              'Some o tempo de todos os usos do dia. Ex.: a noite toda = 8 h e 0 min.',
              'Add up every use in the day. E.g.: all night = 8 h and 0 min.',
            )
          : optional
          ? tr(
              'Se não souber, toque em "Não sei": usamos o consumo do ensaio do Inmetro.',
              'If you are not sure, tap "I don\'t know": we use the consumption from Inmetro\'s test.',
            )
          : usage.defaults != null
          ? tr(
              'Já deixamos um valor comum preenchido. Troque pelo seu uso, se for diferente.',
              'We filled in a typical value. Change it to your own use if it is different.',
            )
          : tr(
              'Some o tempo de todos os usos do dia. Ex.: 0 h e 15 min.',
              'Add up every use in the day. E.g.: 0 h and 15 min.',
            ),
      fields: [TimeField(control: _time)],
      validate: () {
        if (!_time.valid) {
          return tr(
            'Confira o tempo: minutos de 0 a 59 e no máximo 24 horas por dia.',
            'Check the time: minutes from 0 to 59 and at most 24 hours per day.',
          );
        }
        if (_time.dailyHours == null && !optional) return tr('Digite o tempo de uso por dia.', 'Enter the time of use per day.');
        return null;
      },
      skipText: optional ? tr('Não sei, usar o valor do Inmetro', "I don't know, use Inmetro's value") : null,
      onSkip: _time.clear,
    );
    return switch (usage.question) {
      'horas' => [hours],
      'ciclos' => [
        _Question(
          tr('Quantas vezes por mês você lava roupa?', 'How many loads of laundry do you do per month?'),
          help: tr(
            'Já deixamos um valor comum preenchido. Troque pelo seu uso, se for diferente.',
            'We filled in a typical value. Change it to your own use if it is different.',
          ),
          fields: [_field(_cycles, tr('Lavagens por mês', 'Loads per month'), suffix: tr('vezes', 'times'), whole: true)],
          validate: () {
            final cycles = readNumber(_cycles.text);
            return cycles == null || cycles < 0
                ? tr('Digite quantas lavagens por mês. Ex.: 12.', 'Enter how many loads per month. E.g.: 12.')
                : null;
          },
        ),
      ],
      'velocidade' => [
        if (!withoutSpeed)
          _Question(
            tr('Em qual velocidade você costuma usar?', 'Which speed do you usually use?'),
            fields: [
              for (final o in usage.options)
                OptionCard(
                  title: speedName(o),
                  selected: _speed == o,
                  onTap: () => _choose(() => _speed = o),
                ),
            ],
          ),
        if (usage.askHours) hours,
      ],
      _ => const [],
    };
  }

  _Question _nameQuestion() => _Question(
    tr('Qual é a marca e o modelo?', 'What is the brand and model?'),
    help: tr(
      'Opcional. Serve só para você reconhecer o aparelho na sua casa.',
      'Optional. It only helps you recognize the appliance in your home.',
    ),
    fields: [_field(_name, tr('Marca e modelo', 'Brand and model'), example: tr('Ex.: Consul CRM45', 'E.g.: Consul CRM45'), text: true)],
    validate: () => null,
    skipText: tr('Pular', 'Skip'),
    onSkip: _name.clear,
  );

  List<_Question> _smallApplianceQuestions() {
    final r = _resistive;
    return [
      _Question(
        tr('Qual é o aparelho?', 'Which appliance is it?'),
        fields: [
          for (final x in _resistiveItems!)
            OptionCard(
              icon: categoryIcon(x.category),
              title: x.name,
              subtitle: tr('Típica: ${number(x.powerW, homes: 0)} W', 'Typical: ${number(x.powerW, homes: 0)} W'),
              selected: _resistive?.category == x.category,
              onTap: () => _chooseResistive(x),
            ),
        ],
      ),
      if (r != null) ...[
        _Question(
          tr('Qual é a potência?', 'What is the power?'),
          help: tr(
            'Em watts (W). Está na etiqueta embaixo ou atrás do aparelho.',
            'In watts (W). It is on the label under or behind the appliance.',
          ),
          fields: [
            _field(
              _power,
              tr('Potência', 'Power'),
              suffix: 'W',
              example: tr('Típica: ${number(r.powerW, homes: 0)} W', 'Typical: ${number(r.powerW, homes: 0)} W'),
            ),
          ],
          validate: () => _invalid(_power, maximum: 10000)
              ? tr('Digite a potência em watts. Ex.: 1500.', 'Enter the power in watts. E.g.: 1500.')
              : null,
          skipText: tr(
            'Não sei, usar a típica (${number(r.powerW, homes: 0)} W)',
            "I don't know, use the typical one (${number(r.powerW, homes: 0)} W)",
          ),
          onSkip: _power.clear,
        ),
        _Question(
          tr('Quanto tempo por dia você usa?', 'How long do you use it per day?'),
          help: tr(
            'Sugerido: ${duration(r.dailyHours)}. Troque pelo seu uso real.',
            'Suggested: ${duration(r.dailyHours)}. Change it to your real use.',
          ),
          fields: [TimeField(control: _smallApplianceTime)],
          validate: () => _smallApplianceTime.valid
              ? null
              : tr(
                  'Confira o tempo: minutos de 0 a 59 e no máximo 24 horas por dia.',
                  'Check the time: minutes from 0 to 59 and at most 24 hours per day.',
                ),
        ),
        _Question(
          tr('Em quantos dias do mês você usa?', 'On how many days a month do you use it?'),
          fields: [_field(_days, tr('Dias de uso no mês', 'Days of use per month'), suffix: tr('dias', 'days'), whole: true)],
          validate: () => _invalid(_days, minimum: -1, maximum: 31)
              ? tr('Digite um número de dias entre 0 e 31.', 'Enter a number of days between 0 and 31.')
              : null,
        ),
      ],
    ];
  }

  Widget _field(
    TextEditingController control,
    String label, {
    String? example,
    String? suffix,
    bool whole = false,
    bool text = false,
  }) {
    return TextField(
      controller: control,
      autofocus: true,
      keyboardType: text ? TextInputType.text : TextInputType.numberWithOptions(decimal: !whole),
      decoration: InputDecoration(labelText: label, hintText: example, suffixText: suffix),
    );
  }

  // ---------- tela ----------

  @override
  Widget build(BuildContext context) {
    final loaded = _categories != null && _resistiveItems != null;
    if (!loaded) {
      return AppPage(
        title: tr('Estimar o gasto', 'Estimate the cost'),
        child: _failedLoad ? ErrorMessage(_error!, tryAgain: _load) : const Loading(),
      );
    }
    final questions = _questions();
    final index = _index.clamp(0, questions.length - 1);
    final p = questions[index];
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (left, _) {
        if (!left) _back();
      },
      child: AppPage(
        title: tr('Estimar o gasto', 'Estimate the cost'),
        step: FlowStep(index + 1, questions.length),
        footer: p.validate == null ? null : _footer(p),
        // as perguntas ficam na mesma tela: a troca imita a transicao entre telas (StepTransition)
        child: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : StepTransition.duration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (current, previous) => Stack(children: [...previous, ?current]),
          transitionBuilder: (child, animation) {
            // a pergunta que entra vem do lado para onde a pessoa esta indo; a que sai so apaga
            final entering = child.key == ValueKey(index);
            final from = Offset(entering ? (_forward ? 0.16 : -0.16) : 0, 0);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: Tween(begin: from, end: Offset.zero).animate(animation), child: child),
            );
          },
          child: ListView(
            key: ValueKey(index), // cada pergunta comeca do topo
            children: [
              QuestionHeader(p.title, help: p.help),
              ...p.fields,
              if (_error != null) ...[
                const SizedBox(height: Spacing.m),
                ErrorMessage(_error!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(_Question p) {
    final proceed = FilledButton(onPressed: () => _continue(p), child: Text(tr('Continuar', 'Continue')));
    if (p.skipText == null) return proceed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        proceed,
        const SizedBox(height: Spacing.p),
        TextButton(onPressed: () => _skip(p), child: Text(p.skipText!)),
      ],
    );
  }
}
