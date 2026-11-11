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

enum Grupo { pesado, portatil }

Map<String, String> get tiposDeGeladeira => {
  'duplex': tr('Geladeira duplex (2 portas)', 'Two-door fridge (top freezer)'),
  '1_porta': tr('Geladeira 1 porta', 'One-door fridge'),
  'frigobar': tr('Frigobar', 'Mini fridge'),
  'freezer_vertical': tr('Freezer vertical', 'Upright freezer'),
  'freezer_horizontal': tr('Freezer horizontal', 'Chest freezer'),
};

/// Uma pergunta da estimativa. Sem `validar`, e uma escolha: tocar numa opcao ja avanca.
class _Pergunta {
  final String titulo;
  final String? ajuda;
  final List<Widget> campos;
  final String? Function()? validar;
  final String? textoPular;
  final VoidCallback? aoPular;

  const _Pergunta(this.titulo, {this.ajuda, required this.campos, this.validar, this.textoPular, this.aoPular});
}

class TelaEstimar extends StatefulWidget {
  final Future<List<CategoriaEstimavel>> Function() carregarCategorias;
  final Future<List<Resistivo>> Function() carregarResistivos;

  const TelaEstimar({
    super.key,
    this.carregarCategorias = Api.categoriasEstimaveis,
    this.carregarResistivos = Api.resistivos,
  });

  @override
  State<TelaEstimar> createState() => _TelaEstimarState();
}

class _TelaEstimarState extends State<TelaEstimar> {
  int _indice = 0;
  String? _erro;
  bool _falhouCarga = false;

  Grupo? _grupo;
  List<CategoriaEstimavel>? _categorias;
  CategoriaEstimavel? _categoria;

  String? _tipoGeladeira;
  bool? _frostFree;
  final _congelador = TextEditingController();
  final _ano = TextEditingController();

  FormaDeInformar? _forma; // numero que a pessoa achou no aparelho
  bool _semNumero = false; // nao achou: usa tipo e tamanho
  String? _tipo;
  double? _tamanho;
  bool _outroTamanho = false;
  final _medida = TextEditingController();
  final _etiqueta = TextEditingController();
  final _tempo = ControleTempo();
  final _ciclos = TextEditingController();
  String? _velocidade;
  final _nome = TextEditingController();

  List<Resistivo>? _resistivos;
  Resistivo? _resistivo;
  final _potencia = TextEditingController();
  final _tempoPortatil = ControleTempo();
  final _dias = TextEditingController();

  bool get _geladeira => _categoria?.especial ?? false;
  bool get _soFreezer => _tipoGeladeira?.startsWith('freezer') ?? false;
  bool get _comPotencia => _forma?.campo == 'potencia_w';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in [_congelador, _ano, _medida, _etiqueta, _ciclos, _nome, _potencia, _dias]) {
      c.dispose();
    }
    _tempo.dispose();
    _tempoPortatil.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _erro = null;
      _falhouCarga = false;
    });
    try {
      final categorias = await widget.carregarCategorias();
      final resistivos = await widget.carregarResistivos();
      if (!mounted) return;
      setState(() {
        _categorias = categorias;
        _resistivos = resistivos;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _falhouCarga = true;
          _erro = tr(
            'Não consegui carregar a lista de aparelhos. Confira a internet e tente de novo.',
            'Could not load the list of appliances. Check your internet connection and try again.',
          );
        });
      }
    }
  }

  // ---------- respostas ----------

  void _escolherGrupo(Grupo g) {
    if (_grupo != g) {
      _categoria = null;
      _resistivo = null;
    }
    _grupo = g;
    _avancar();
  }

  void _escolherCategoria(CategoriaEstimavel c) {
    if (_categoria?.categoria != c.categoria) {
      _forma = c.valorObrigatorio && c.formas.isNotEmpty ? c.formas.first : null;
      _semNumero = false;
      _tipo = null;
      _tamanho = null;
      _outroTamanho = false;
      _tipoGeladeira = null;
      _frostFree = null;
      _medida.clear();
      _etiqueta.clear();
      final uso = c.uso;
      _tempo.definir(uso.pergunta == 'horas' ? (uso.padrao as num?)?.toDouble() : null);
      _ciclos.text = uso.pergunta == 'ciclos' && uso.padrao != null
          ? numero((uso.padrao as num).toDouble(), casas: 0)
          : '';
      _velocidade = uso.pergunta == 'velocidade' ? uso.padrao as String? : null;
    }
    _categoria = c;
    _avancar();
  }

  void _escolherResistivo(Resistivo r) {
    if (_resistivo?.categoria != r.categoria) {
      _potencia.clear();
      _tempoPortatil.definir(r.horasDia);
      _dias.text = numero(r.diasMes, casas: 0);
    }
    _resistivo = r;
    _avancar();
  }

  void _escolherForma(FormaDeInformar? forma) {
    if (forma?.campo != _forma?.campo) _etiqueta.clear();
    _forma = forma;
    _semNumero = forma == null;
    _avancar();
  }

  void _escolherTamanho(double? tamanho) {
    _tamanho = tamanho;
    _outroTamanho = tamanho == null;
    _avancar();
  }

  void _escolher(VoidCallback mudar) {
    mudar();
    _avancar();
  }

  double? _opcional(TextEditingController c) => c.text.trim().isEmpty ? null : lerNumero(c.text);

  bool _invalido(TextEditingController c, {double minimo = 0, double maximo = double.infinity}) {
    if (c.text.trim().isEmpty) return false;
    final v = lerNumero(c.text);
    return v == null || v <= minimo || v > maximo;
  }

  (String?, String?) _marcaEModelo() {
    final partes = _nome.text.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return (null, null);
    return (partes.first, partes.length > 1 ? partes.skip(1).join(' ') : null);
  }

  // ---------- navegacao entre as perguntas ----------

  void _avancar() {
    final ultima = _indice >= _perguntas().length - 1;
    setState(() {
      _erro = null;
      if (!ultima) _indice++;
    });
    if (ultima) _concluir();
  }

  void _voltar() => setState(() {
    _erro = null;
    _indice--;
  });

  void _continuar(_Pergunta p) {
    final erro = p.validar!();
    if (erro != null) {
      setState(() => _erro = erro);
      return;
    }
    _avancar();
  }

  void _pular(_Pergunta p) {
    p.aoPular?.call();
    _avancar();
  }

  void _concluir() {
    final consulta = switch (_grupo) {
      Grupo.portatil => _consultaPortatil(),
      _ => _geladeira ? _consultaGeladeira() : _consultaPesado(_categoria!),
    };
    Navigator.push(context, MaterialPageRoute(builder: (_) => TelaEstado(consulta: consulta)));
  }

  Consulta _consultaGeladeira() {
    final (marca, modelo) = _marcaEModelo();
    return Consulta(
      Aparelho(id: 0, categoria: 'refrigerador', marca: marca ?? tr('Geladeira', 'Fridge'), modelo: modelo ?? ''),
      estimativa: Estimativa(rotaGeladeira, {
        'tipo': _tipoGeladeira,
        'frost_free': _frostFree ?? false,
        'volume_total_l': lerNumero(_medida.text),
        'volume_congelador_l': _soFreezer ? null : _opcional(_congelador),
        'ano_compra': int.tryParse(_ano.text.trim()),
        'kwh_etiqueta': _opcional(_etiqueta),
        'marca': marca,
        'modelo': modelo,
      }),
    );
  }

  Consulta _consultaPesado(CategoriaEstimavel c) {
    final (marca, modelo) = _marcaEModelo();
    final pedeHoras = c.uso.pergunta == 'horas' || c.uso.perguntarHoras;
    return Consulta(
      Aparelho(id: 0, categoria: c.categoria, marca: marca ?? c.nome, modelo: modelo ?? ''),
      estimativa: Estimativa(rotaEstimado, {
        'categoria': c.categoria,
        'tipo': _tipo,
        'medida': c.medida == null ? null : (_outroTamanho ? _opcional(_medida) : _tamanho),
        'valor_etiqueta': _forma == null ? null : _opcional(_etiqueta),
        'campo_etiqueta': _forma?.campo,
        'marca': marca,
        'modelo': modelo,
      }),
      horasDia: pedeHoras ? _tempo.horasDia : null,
      ciclosMes: c.uso.pergunta == 'ciclos' ? lerNumero(_ciclos.text) : null,
      velocidade: c.uso.pergunta == 'velocidade' && _semNumero ? _velocidade : null,
    );
  }

  Consulta _consultaPortatil() {
    final r = _resistivo!;
    return Consulta(
      Aparelho(id: 0, categoria: r.categoria, marca: r.nome, modelo: ''),
      estimativa: Estimativa(rotaResistivo, {
        'categoria': r.categoria,
        'potencia_w': _opcional(_potencia),
        'dias_mes': _opcional(_dias),
      }),
      horasDia: _tempoPortatil.horasDia,
    );
  }

  // ---------- as perguntas ----------

  List<_Pergunta> _perguntas() {
    return [
      _perguntaGrupo(),
      if (_grupo == Grupo.portatil) ..._perguntasPortatil(),
      if (_grupo == Grupo.pesado) ...[
        _perguntaAparelhoPesado(),
        if (_categoria != null) ...(_geladeira ? _perguntasGeladeira() : _perguntasCategoria(_categoria!)),
        if (_categoria != null) _perguntaNome(),
      ],
    ];
  }

  _Pergunta _perguntaGrupo() => _Pergunta(
    tr('Que tipo de aparelho é?', 'What kind of appliance is it?'),
    ajuda: tr(
      'Para aparelhos que não estão no catálogo do Inmetro. Calculamos um gasto aproximado '
          'com o que você souber.',
      "For appliances that are not in Inmetro's catalog. We calculate an approximate cost "
          'with whatever you know.',
    ),
    campos: [
      CartaoOpcao(
        icone: Icons.kitchen,
        titulo: tr('Eletrodoméstico grande', 'Large appliance'),
        subtitulo: tr(
          'Geladeira, máquina de lavar, ar-condicionado, chuveiro, TV...',
          'Fridge, washing machine, air conditioner, electric shower, TV...',
        ),
        selecionada: _grupo == Grupo.pesado,
        onTap: () => _escolherGrupo(Grupo.pesado),
      ),
      CartaoOpcao(
        icone: Icons.blender_outlined,
        titulo: tr('Eletroportátil', 'Small appliance'),
        subtitulo: tr(
          'Air fryer, secador de cabelo, ferro de passar, cafeteira...',
          'Air fryer, hair dryer, clothes iron, coffee maker...',
        ),
        selecionada: _grupo == Grupo.portatil,
        onTap: () => _escolherGrupo(Grupo.portatil),
      ),
    ],
  );

  _Pergunta _perguntaAparelhoPesado() => _Pergunta(
    tr('Qual é o aparelho?', 'Which appliance is it?'),
    campos: [
      for (final c in _categorias!)
        CartaoOpcao(
          icone: iconeDaCategoria(c.categoria),
          titulo: c.nome,
          selecionada: _categoria?.categoria == c.categoria,
          onTap: () => _escolherCategoria(c),
        ),
    ],
  );

  List<_Pergunta> _perguntasGeladeira() => [
    _Pergunta(
      tr('Qual é o tipo?', 'What type is it?'),
      campos: [
        for (final MapEntry(key: tipo, value: nome) in tiposDeGeladeira.entries)
          CartaoOpcao(
            titulo: nome,
            selecionada: _tipoGeladeira == tipo,
            onTap: () => _escolher(() => _tipoGeladeira = tipo),
          ),
      ],
    ),
    _Pergunta(
      tr('Ela forma gelo nas paredes?', 'Does ice build up on the walls?'),
      ajuda: tr(
        'Quem não forma gelo é "frost-free" e não precisa degelar.',
        'If no ice builds up, it is "frost-free" and never needs defrosting.',
      ),
      campos: [
        CartaoOpcao(
          titulo: tr('Não forma gelo (frost-free)', 'No ice builds up (frost-free)'),
          subtitulo: tr('Não precisa degelar.', 'No defrosting needed.'),
          selecionada: _frostFree == true,
          onTap: () => _escolher(() => _frostFree = true),
        ),
        CartaoOpcao(
          titulo: tr('Forma gelo', 'Ice builds up'),
          subtitulo: tr('Precisa degelar de vez em quando.', 'Needs defrosting now and then.'),
          selecionada: _frostFree == false,
          onTap: () => _escolher(() => _frostFree = false),
        ),
      ],
    ),
    _Pergunta(
      tr('Qual é a capacidade total?', 'What is the total capacity?'),
      ajuda: tr(
        'Em litros. Está na etiqueta dentro da porta ou no manual.',
        'In liters. It is on the label inside the door or in the manual.',
      ),
      campos: [
        _campo(
          _medida,
          tr('Capacidade total', 'Total capacity'),
          sufixo: tr('litros', 'liters'),
          exemplo: tr('Ex.: 407', 'E.g.: 407'),
        ),
      ],
      validar: () {
        final volume = lerNumero(_medida.text);
        return volume == null || volume <= 0 || volume > 1000
            ? tr(
                'Digite a capacidade total em litros (está na etiqueta ou no manual).',
                'Enter the total capacity in liters (it is on the label or in the manual).',
              )
            : null;
      },
    ),
    if (!_soFreezer)
      _Pergunta(
        tr('Quantos litros tem o freezer?', 'How many liters is the freezer?'),
        ajuda: tr(
          'Melhora a estimativa. Se não souber, toque em "Não sei".',
          'It improves the estimate. If you are not sure, tap "I don\'t know".',
        ),
        campos: [
          _campo(
            _congelador,
            tr('Litros do freezer', 'Freezer liters'),
            sufixo: tr('litros', 'liters'),
            exemplo: tr('Ex.: 90', 'E.g.: 90'),
          ),
        ],
        validar: () {
          final volume = lerNumero(_medida.text) ?? 0;
          final congelador = _opcional(_congelador);
          return _invalido(_congelador, minimo: -1) || (congelador ?? 0) > volume
              ? tr(
                  'Os litros do freezer precisam ser menores que a capacidade total.',
                  'The freezer liters must be less than the total capacity.',
                )
              : null;
        },
        textoPular: tr('Não sei', "I don't know"),
        aoPular: _congelador.clear,
      ),
    _Pergunta(
      tr('Em que ano você comprou?', 'What year did you buy it?'),
      ajuda: tr('Geladeiras mais antigas costumam gastar mais.', 'Older fridges usually use more energy.'),
      campos: [_campo(_ano, tr('Ano de compra', 'Year of purchase'), exemplo: tr('Ex.: 2014', 'E.g.: 2014'), inteiro: true)],
      validar: () {
        final ano = int.tryParse(_ano.text.trim());
        final anoAtual = DateTime.now().year;
        return ano == null || ano < 1980 || ano > anoAtual
            ? tr(
                'Digite o ano de compra entre 1980 e $anoAtual. Ex.: 2014.',
                'Enter a year of purchase between 1980 and $anoAtual. E.g.: 2014.',
              )
            : null;
      },
    ),
    _Pergunta(
      tr('Tem a etiqueta amarela do Inmetro?', "Does it have Inmetro's yellow energy label?"),
      ajuda: tr(
        'É o número em kWh por mês da etiqueta colada no aparelho. Com ele o resultado fica bem mais preciso.',
        'It is the kWh per month number on the label stuck to the appliance. With it the result is much more accurate.',
      ),
      campos: [
        _campo(
          _etiqueta,
          tr('Consumo da etiqueta', 'Consumption on the label'),
          sufixo: tr('kWh/mês', 'kWh/month'),
          exemplo: tr('Ex.: 52,5', 'E.g.: 52.5'),
        ),
      ],
      validar: () => _invalido(_etiqueta, maximo: 300)
          ? tr('Digite o número em kWh por mês. Ex.: 52,5.', 'Enter the number in kWh per month. E.g.: 52.5.')
          : null,
      textoPular: tr('Não tenho a etiqueta', "I don't have the label"),
      aoPular: _etiqueta.clear,
    ),
  ];

  List<_Pergunta> _perguntasCategoria(CategoriaEstimavel c) {
    final forma = _forma;
    return [
      if (c.tipos.isNotEmpty)
        _Pergunta(
          tr('Qual destes é o seu?', 'Which of these is yours?'),
          campos: [
            for (final tipo in c.tipos)
              CartaoOpcao(
                titulo: tipo.nome,
                subtitulo: tipo.descricao,
                selecionada: _tipo == tipo.valor,
                onTap: () => _escolher(() => _tipo = tipo.valor),
              ),
          ],
        ),
      if (c.medida != null) _perguntaTamanho(c),
      if (c.medida != null && _outroTamanho)
        _Pergunta(
          tr('Digite o tamanho', 'Enter the size'),
          ajuda: tr(
            '${legivel(c.medida!)}. Costuma estar escrito no aparelho, na caixa ou no manual.',
            '${legivel(c.medida!)}. It is usually written on the appliance, the box or in the manual.',
          ),
          campos: [_campo(_medida, legivel(c.medida!).split(' (').first, sufixo: c.unidadeMedida)],
          validar: () => _opcional(_medida) == null || _invalido(_medida)
              ? tr(
                  'Digite o número, como está escrito. Se não souber, volte e escolha um dos tamanhos.',
                  'Enter the number as it is written. If you are not sure, go back and pick one of the sizes.',
                )
              : null,
        ),
      if (!c.valorObrigatorio) _perguntaForma(c),
      if (forma != null) _perguntaValor(forma),
      ..._perguntasUso(c.uso, horasObrigatorias: _comPotencia, semVelocidade: !_semNumero),
    ];
  }

  _Pergunta _perguntaForma(CategoriaEstimavel c) => _Pergunta(
    tr('Você consegue ver algum destes no aparelho?', 'Can you see any of these on the appliance?'),
    ajuda: tr(
      'Com o número do próprio aparelho o cálculo fica certo, mesmo se ele for antigo.',
      "With the appliance's own number the calculation is accurate, even if it is old.",
    ),
    campos: [
      for (final f in c.formas)
        CartaoOpcao(
          icone: f.campo == 'potencia_w' ? Icons.bolt : Icons.receipt_long_outlined,
          titulo: f.nome,
          subtitulo: f.onde,
          selecionada: _forma?.campo == f.campo,
          onTap: () => _escolherForma(f),
        ),
      CartaoOpcao(
        icone: Icons.help_outline,
        titulo: tr('Não consigo ver nenhum', "I can't see any"),
        subtitulo: c.medida == null
            ? tr(
                'Tudo bem: calculamos com os modelos do catálogo do Inmetro.',
                "That's fine: we calculate with the models in Inmetro's catalog.",
              )
            : tr(
                'Tudo bem: calculamos com os modelos parecidos do Inmetro.',
                "That's fine: we calculate with similar models from Inmetro.",
              ),
        selecionada: _semNumero,
        onTap: () => _escolherForma(null),
      ),
    ],
  );

  _Pergunta _perguntaValor(FormaDeInformar f) => _Pergunta(
    f.campo == 'potencia_w'
        ? tr('Qual é a potência?', 'What is the power?')
        : tr('Qual é o consumo de energia?', 'What is the energy consumption?'),
    ajuda: [f.onde, if (f.dica != null) f.dica!].join(' '),
    campos: [_campo(_etiqueta, f.rotulo, sufixo: f.unidade, exemplo: f.exemplo)],
    validar: () {
      final v = _opcional(_etiqueta);
      return v == null || _invalido(_etiqueta, maximo: f.maximo)
          ? tr(
              'Digite o número em ${f.unidade}, como está escrito. ${f.exemplo}.',
              'Enter the number in ${f.unidade}, as it is written. ${f.exemplo}.',
            )
          : null;
    },
  );

  _Pergunta _perguntaTamanho(CategoriaEstimavel c) => _Pergunta(
    tr('Qual é o tamanho?', 'What size is it?'),
    ajuda: tr(
      '${legivel(c.medida!)}. Costuma estar escrito no aparelho, na caixa ou no manual.',
      '${legivel(c.medida!)}. It is usually written on the appliance, the box or in the manual.',
    ),
    campos: [
      for (final t in c.tamanhos)
        CartaoOpcao(
          titulo: t.nome,
          selecionada: !_outroTamanho && _tamanho == t.valor,
          onTap: () => _escolherTamanho(t.valor),
        ),
      CartaoOpcao(
        icone: Icons.edit_outlined,
        titulo: tr('Outro tamanho', 'Another size'),
        subtitulo: tr('Digitar o número', 'Type the number'),
        selecionada: _outroTamanho,
        onTap: () => _escolherTamanho(null),
      ),
    ],
  );

  /// horasObrigatorias: com a potencia da plaqueta, so as horas dizem quanto gasta.
  /// semVelocidade: com a potencia, a velocidade do ventilador nao entra na conta.
  List<_Pergunta> _perguntasUso(PerguntaDeUso uso, {bool horasObrigatorias = false, bool semVelocidade = false}) {
    final opcional = uso.opcional && !horasObrigatorias;
    final horas = _Pergunta(
      tr('Quanto tempo por dia ele fica ligado?', 'How long does it stay on per day?'),
      ajuda: uso.perguntarHoras
          ? tr(
              'Some o tempo de todos os usos do dia. Ex.: a noite toda = 8 h e 0 min.',
              'Add up every use in the day. E.g.: all night = 8 h and 0 min.',
            )
          : opcional
          ? tr(
              'Se não souber, toque em "Não sei": usamos o consumo do ensaio do Inmetro.',
              'If you are not sure, tap "I don\'t know": we use the consumption from Inmetro\'s test.',
            )
          : uso.padrao != null
          ? tr(
              'Já deixamos um valor comum preenchido. Troque pelo seu uso, se for diferente.',
              'We filled in a typical value. Change it to your own use if it is different.',
            )
          : tr(
              'Some o tempo de todos os usos do dia. Ex.: 0 h e 15 min.',
              'Add up every use in the day. E.g.: 0 h and 15 min.',
            ),
      campos: [CampoTempo(controle: _tempo)],
      validar: () {
        if (!_tempo.valido) {
          return tr(
            'Confira o tempo: minutos de 0 a 59 e no máximo 24 horas por dia.',
            'Check the time: minutes from 0 to 59 and at most 24 hours per day.',
          );
        }
        if (_tempo.horasDia == null && !opcional) return tr('Digite o tempo de uso por dia.', 'Enter the time of use per day.');
        return null;
      },
      textoPular: opcional ? tr('Não sei, usar o valor do Inmetro', "I don't know, use Inmetro's value") : null,
      aoPular: _tempo.limpar,
    );
    return switch (uso.pergunta) {
      'horas' => [horas],
      'ciclos' => [
        _Pergunta(
          tr('Quantas vezes por mês você lava roupa?', 'How many loads of laundry do you do per month?'),
          ajuda: tr(
            'Já deixamos um valor comum preenchido. Troque pelo seu uso, se for diferente.',
            'We filled in a typical value. Change it to your own use if it is different.',
          ),
          campos: [_campo(_ciclos, tr('Lavagens por mês', 'Loads per month'), sufixo: tr('vezes', 'times'), inteiro: true)],
          validar: () {
            final ciclos = lerNumero(_ciclos.text);
            return ciclos == null || ciclos < 0
                ? tr('Digite quantas lavagens por mês. Ex.: 12.', 'Enter how many loads per month. E.g.: 12.')
                : null;
          },
        ),
      ],
      'velocidade' => [
        if (!semVelocidade)
          _Pergunta(
            tr('Em qual velocidade você costuma usar?', 'Which speed do you usually use?'),
            campos: [
              for (final o in uso.opcoes)
                CartaoOpcao(
                  titulo: nomeDaVelocidade(o),
                  selecionada: _velocidade == o,
                  onTap: () => _escolher(() => _velocidade = o),
                ),
            ],
          ),
        if (uso.perguntarHoras) horas,
      ],
      _ => const [],
    };
  }

  _Pergunta _perguntaNome() => _Pergunta(
    tr('Qual é a marca e o modelo?', 'What is the brand and model?'),
    ajuda: tr(
      'Opcional. Serve só para você reconhecer o aparelho na sua casa.',
      'Optional. It only helps you recognize the appliance in your home.',
    ),
    campos: [_campo(_nome, tr('Marca e modelo', 'Brand and model'), exemplo: tr('Ex.: Consul CRM45', 'E.g.: Consul CRM45'), texto: true)],
    validar: () => null,
    textoPular: tr('Pular', 'Skip'),
    aoPular: _nome.clear,
  );

  List<_Pergunta> _perguntasPortatil() {
    final r = _resistivo;
    return [
      _Pergunta(
        tr('Qual é o aparelho?', 'Which appliance is it?'),
        campos: [
          for (final x in _resistivos!)
            CartaoOpcao(
              icone: iconeDaCategoria(x.categoria),
              titulo: x.nome,
              subtitulo: tr('Típica: ${numero(x.potenciaW, casas: 0)} W', 'Typical: ${numero(x.potenciaW, casas: 0)} W'),
              selecionada: _resistivo?.categoria == x.categoria,
              onTap: () => _escolherResistivo(x),
            ),
        ],
      ),
      if (r != null) ...[
        _Pergunta(
          tr('Qual é a potência?', 'What is the power?'),
          ajuda: tr(
            'Em watts (W). Está na etiqueta embaixo ou atrás do aparelho.',
            'In watts (W). It is on the label under or behind the appliance.',
          ),
          campos: [
            _campo(
              _potencia,
              tr('Potência', 'Power'),
              sufixo: 'W',
              exemplo: tr('Típica: ${numero(r.potenciaW, casas: 0)} W', 'Typical: ${numero(r.potenciaW, casas: 0)} W'),
            ),
          ],
          validar: () => _invalido(_potencia, maximo: 10000)
              ? tr('Digite a potência em watts. Ex.: 1500.', 'Enter the power in watts. E.g.: 1500.')
              : null,
          textoPular: tr(
            'Não sei, usar a típica (${numero(r.potenciaW, casas: 0)} W)',
            "I don't know, use the typical one (${numero(r.potenciaW, casas: 0)} W)",
          ),
          aoPular: _potencia.clear,
        ),
        _Pergunta(
          tr('Quanto tempo por dia você usa?', 'How long do you use it per day?'),
          ajuda: tr(
            'Sugerido: ${duracao(r.horasDia)}. Troque pelo seu uso real.',
            'Suggested: ${duracao(r.horasDia)}. Change it to your real use.',
          ),
          campos: [CampoTempo(controle: _tempoPortatil)],
          validar: () => _tempoPortatil.valido
              ? null
              : tr(
                  'Confira o tempo: minutos de 0 a 59 e no máximo 24 horas por dia.',
                  'Check the time: minutes from 0 to 59 and at most 24 hours per day.',
                ),
        ),
        _Pergunta(
          tr('Em quantos dias do mês você usa?', 'On how many days a month do you use it?'),
          campos: [_campo(_dias, tr('Dias de uso no mês', 'Days of use per month'), sufixo: tr('dias', 'days'), inteiro: true)],
          validar: () => _invalido(_dias, minimo: -1, maximo: 31)
              ? tr('Digite um número de dias entre 0 e 31.', 'Enter a number of days between 0 and 31.')
              : null,
        ),
      ],
    ];
  }

  Widget _campo(
    TextEditingController controle,
    String rotulo, {
    String? exemplo,
    String? sufixo,
    bool inteiro = false,
    bool texto = false,
  }) {
    return TextField(
      controller: controle,
      autofocus: true,
      keyboardType: texto ? TextInputType.text : TextInputType.numberWithOptions(decimal: !inteiro),
      decoration: InputDecoration(labelText: rotulo, hintText: exemplo, suffixText: sufixo),
    );
  }

  // ---------- tela ----------

  @override
  Widget build(BuildContext context) {
    final carregado = _categorias != null && _resistivos != null;
    if (!carregado) {
      return Pagina(
        titulo: tr('Estimar o gasto', 'Estimate the cost'),
        filho: _falhouCarga ? MensagemErro(_erro!, tentarDeNovo: _carregar) : const Carregando(),
      );
    }
    final perguntas = _perguntas();
    final indice = _indice.clamp(0, perguntas.length - 1);
    final p = perguntas[indice];
    return PopScope(
      canPop: indice == 0,
      onPopInvokedWithResult: (saiu, _) {
        if (!saiu) _voltar();
      },
      child: Pagina(
        titulo: tr('Estimar o gasto', 'Estimate the cost'),
        etapa: Etapa(indice + 1, perguntas.length),
        rodape: p.validar == null ? null : _rodape(p),
        filho: ListView(
          key: ValueKey(indice), // cada pergunta comeca do topo
          children: [
            CabecalhoPergunta(p.titulo, ajuda: p.ajuda),
            ...p.campos,
            if (_erro != null) ...[
              const SizedBox(height: Espaco.m),
              MensagemErro(_erro!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rodape(_Pergunta p) {
    final continuar = FilledButton(onPressed: () => _continuar(p), child: Text(tr('Continuar', 'Continue')));
    if (p.textoPular == null) return continuar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        continuar,
        const SizedBox(height: Espaco.p),
        TextButton(onPressed: () => _pular(p), child: Text(p.textoPular!)),
      ],
    );
  }
}
