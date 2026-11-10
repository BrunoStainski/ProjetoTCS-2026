// Estimativa de aparelho fora do catalogo do Inmetro, uma pergunta por tela.
// As perguntas dependem das respostas (geladeira pergunta o ano; eletroportatil, a potencia...).
// Voltar (seta ou botao do celular) volta uma pergunta, sem perder o que ja foi respondido.

import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../tema.dart';
import 'comum.dart';
import 'distribuidora.dart';

enum Grupo { pesado, portatil }

const tiposDeGeladeira = {
  'duplex': 'Geladeira duplex (2 portas)',
  '1_porta': 'Geladeira 1 porta',
  'frigobar': 'Frigobar',
  'freezer_vertical': 'Freezer vertical',
  'freezer_horizontal': 'Freezer horizontal',
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

  String? _tipo;
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
  bool get _temEtiqueta => _etiqueta.text.trim().isNotEmpty;

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
          _erro = 'Não consegui carregar a lista de aparelhos. Confira a internet e tente de novo.';
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
      _tipo = null;
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
      Aparelho(id: 0, categoria: 'refrigerador', marca: marca ?? 'Geladeira', modelo: modelo ?? ''),
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
    final etiqueta = _opcional(_etiqueta);
    return Consulta(
      Aparelho(id: 0, categoria: c.categoria, marca: marca ?? c.nome, modelo: modelo ?? ''),
      estimativa: Estimativa(rotaEstimado, {
        'categoria': c.categoria,
        'tipo': etiqueta == null ? _tipo : null,
        'medida': etiqueta == null ? _opcional(_medida) : null,
        'valor_etiqueta': etiqueta,
        'marca': marca,
        'modelo': modelo,
      }),
      horasDia: c.uso.pergunta == 'horas' ? _tempo.horasDia : null,
      ciclosMes: c.uso.pergunta == 'ciclos' ? lerNumero(_ciclos.text) : null,
      velocidade: c.uso.pergunta == 'velocidade' ? _velocidade : null,
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
    'Que tipo de aparelho é?',
    ajuda: 'Para aparelhos que não estão no catálogo do Inmetro. Calculamos um gasto aproximado '
        'com o que você souber.',
    campos: [
      CartaoOpcao(
        icone: Icons.kitchen,
        titulo: 'Eletrodoméstico grande',
        subtitulo: 'Geladeira, máquina de lavar, ar-condicionado, chuveiro, TV...',
        selecionada: _grupo == Grupo.pesado,
        onTap: () => _escolherGrupo(Grupo.pesado),
      ),
      CartaoOpcao(
        icone: Icons.blender_outlined,
        titulo: 'Eletroportátil',
        subtitulo: 'Air fryer, secador de cabelo, ferro de passar, cafeteira...',
        selecionada: _grupo == Grupo.portatil,
        onTap: () => _escolherGrupo(Grupo.portatil),
      ),
    ],
  );

  _Pergunta _perguntaAparelhoPesado() => _Pergunta(
    'Qual é o aparelho?',
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
      'Qual é o tipo?',
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
      'Ela forma gelo nas paredes?',
      ajuda: 'Quem não forma gelo é "frost-free" e não precisa degelar.',
      campos: [
        CartaoOpcao(
          titulo: 'Não forma gelo (frost-free)',
          subtitulo: 'Não precisa degelar.',
          selecionada: _frostFree == true,
          onTap: () => _escolher(() => _frostFree = true),
        ),
        CartaoOpcao(
          titulo: 'Forma gelo',
          subtitulo: 'Precisa degelar de vez em quando.',
          selecionada: _frostFree == false,
          onTap: () => _escolher(() => _frostFree = false),
        ),
      ],
    ),
    _Pergunta(
      'Qual é a capacidade total?',
      ajuda: 'Em litros. Está na etiqueta dentro da porta ou no manual.',
      campos: [_campo(_medida, 'Capacidade total', sufixo: 'litros', exemplo: 'Ex.: 407')],
      validar: () {
        final volume = lerNumero(_medida.text);
        return volume == null || volume <= 0 || volume > 1000
            ? 'Digite a capacidade total em litros (está na etiqueta ou no manual).'
            : null;
      },
    ),
    if (!_soFreezer)
      _Pergunta(
        'Quantos litros tem o freezer?',
        ajuda: 'Melhora a estimativa. Se não souber, toque em "Não sei".',
        campos: [_campo(_congelador, 'Litros do freezer', sufixo: 'litros', exemplo: 'Ex.: 90')],
        validar: () {
          final volume = lerNumero(_medida.text) ?? 0;
          final congelador = _opcional(_congelador);
          return _invalido(_congelador, minimo: -1) || (congelador ?? 0) > volume
              ? 'Os litros do freezer precisam ser menores que a capacidade total.'
              : null;
        },
        textoPular: 'Não sei',
        aoPular: _congelador.clear,
      ),
    _Pergunta(
      'Em que ano você comprou?',
      ajuda: 'Geladeiras mais antigas costumam gastar mais.',
      campos: [_campo(_ano, 'Ano de compra', exemplo: 'Ex.: 2014', inteiro: true)],
      validar: () {
        final ano = int.tryParse(_ano.text.trim());
        final anoAtual = DateTime.now().year;
        return ano == null || ano < 1980 || ano > anoAtual
            ? 'Digite o ano de compra entre 1980 e $anoAtual. Ex.: 2014.'
            : null;
      },
    ),
    _Pergunta(
      'Tem a etiqueta amarela do Inmetro?',
      ajuda: 'É o número em kWh por mês da etiqueta colada no aparelho. Com ele o resultado fica bem mais preciso.',
      campos: [_campo(_etiqueta, 'Consumo da etiqueta', sufixo: 'kWh/mês', exemplo: 'Ex.: 52,5')],
      validar: () => _invalido(_etiqueta, maximo: 300) ? 'Digite o número em kWh por mês. Ex.: 52,5.' : null,
      textoPular: 'Não tenho a etiqueta',
      aoPular: _etiqueta.clear,
    ),
  ];

  List<_Pergunta> _perguntasCategoria(CategoriaEstimavel c) {
    final rotuloEtiqueta = c.etiquetaRotulo == null ? null : legivel(c.etiquetaRotulo!);
    return [
      if (rotuloEtiqueta != null)
        _Pergunta(
          c.etiquetaObrigatoria ? 'Qual é o valor da etiqueta?' : 'Tem a etiqueta do Inmetro?',
          ajuda: c.etiquetaObrigatoria
              ? 'Está escrito no próprio aparelho ou na embalagem.'
              : 'Com o valor da etiqueta o cálculo fica exato. Sem ele, usamos modelos parecidos.',
          campos: [_campo(_etiqueta, rotuloEtiqueta)],
          validar: () {
            if (c.etiquetaObrigatoria && !_temEtiqueta) {
              return 'Digite o valor de "$rotuloEtiqueta". Ele está no aparelho ou na embalagem.';
            }
            return _invalido(_etiqueta) ? 'Confira o número digitado.' : null;
          },
          textoPular: c.etiquetaObrigatoria ? null : 'Não tenho a etiqueta',
          aoPular: _etiqueta.clear,
        ),
      if (!_temEtiqueta && c.tipos.isNotEmpty)
        _Pergunta(
          'Qual é o tipo?',
          campos: [
            for (final tipo in c.tipos)
              CartaoOpcao(titulo: tipo, selecionada: _tipo == tipo, onTap: () => _escolher(() => _tipo = tipo)),
          ],
        ),
      if (!_temEtiqueta && c.medida != null)
        _Pergunta(
          'Qual é o tamanho?',
          ajuda: 'Está na etiqueta do aparelho ou no manual.',
          campos: [_campo(_medida, legivel(c.medida!))],
          validar: () => _opcional(_medida) == null || _invalido(_medida)
              ? 'Digite ${legivel(c.medida!).toLowerCase()} ou volte e informe o valor da etiqueta.'
              : null,
        ),
      ..._perguntasUso(c.uso),
    ];
  }

  List<_Pergunta> _perguntasUso(PerguntaDeUso uso) => switch (uso.pergunta) {
    'horas' => [
      _Pergunta(
        'Quanto tempo por dia ele fica ligado?',
        ajuda: uso.opcional
            ? 'Se não souber, toque em "Não sei": usamos o consumo do ensaio do Inmetro.'
            : uso.padrao != null
            ? 'Já deixamos um valor comum preenchido. Troque pelo seu uso, se for diferente.'
            : 'Some o tempo de todos os usos do dia. Ex.: 0 h e 15 min.',
        campos: [CampoTempo(controle: _tempo)],
        validar: () {
          if (!_tempo.valido) return 'Confira o tempo: minutos de 0 a 59 e no máximo 24 horas por dia.';
          if (_tempo.horasDia == null && !uso.opcional) return 'Digite o tempo de uso por dia.';
          return null;
        },
        textoPular: uso.opcional ? 'Não sei, usar o valor do Inmetro' : null,
        aoPular: _tempo.limpar,
      ),
    ],
    'ciclos' => [
      _Pergunta(
        'Quantas vezes por mês você lava roupa?',
        ajuda: 'Já deixamos um valor comum preenchido. Troque pelo seu uso, se for diferente.',
        campos: [_campo(_ciclos, 'Lavagens por mês', sufixo: 'vezes', inteiro: true)],
        validar: () {
          final ciclos = lerNumero(_ciclos.text);
          return ciclos == null || ciclos < 0 ? 'Digite quantas lavagens por mês. Ex.: 12.' : null;
        },
      ),
    ],
    'velocidade' => [
      _Pergunta(
        'Em qual velocidade você costuma usar?',
        campos: [
          for (final o in uso.opcoes)
            CartaoOpcao(titulo: o, selecionada: _velocidade == o, onTap: () => _escolher(() => _velocidade = o)),
        ],
      ),
    ],
    _ => const [],
  };

  _Pergunta _perguntaNome() => _Pergunta(
    'Qual é a marca e o modelo?',
    ajuda: 'Opcional. Serve só para você reconhecer o aparelho na sua casa.',
    campos: [_campo(_nome, 'Marca e modelo', exemplo: 'Ex.: Consul CRM45', texto: true)],
    validar: () => null,
    textoPular: 'Pular',
    aoPular: _nome.clear,
  );

  List<_Pergunta> _perguntasPortatil() {
    final r = _resistivo;
    return [
      _Pergunta(
        'Qual é o aparelho?',
        campos: [
          for (final x in _resistivos!)
            CartaoOpcao(
              icone: iconeDaCategoria(x.categoria),
              titulo: x.nome,
              subtitulo: 'Típica: ${numero(x.potenciaW, casas: 0)} W',
              selecionada: _resistivo?.categoria == x.categoria,
              onTap: () => _escolherResistivo(x),
            ),
        ],
      ),
      if (r != null) ...[
        _Pergunta(
          'Qual é a potência?',
          ajuda: 'Em watts (W). Está na etiqueta embaixo ou atrás do aparelho.',
          campos: [_campo(_potencia, 'Potência', sufixo: 'W', exemplo: 'Típica: ${numero(r.potenciaW, casas: 0)} W')],
          validar: () => _invalido(_potencia, maximo: 10000) ? 'Digite a potência em watts. Ex.: 1500.' : null,
          textoPular: 'Não sei, usar a típica (${numero(r.potenciaW, casas: 0)} W)',
          aoPular: _potencia.clear,
        ),
        _Pergunta(
          'Quanto tempo por dia você usa?',
          ajuda: 'Sugerido: ${duracao(r.horasDia)}. Troque pelo seu uso real.',
          campos: [CampoTempo(controle: _tempoPortatil)],
          validar: () =>
              _tempoPortatil.valido ? null : 'Confira o tempo: minutos de 0 a 59 e no máximo 24 horas por dia.',
        ),
        _Pergunta(
          'Em quantos dias do mês você usa?',
          campos: [_campo(_dias, 'Dias de uso no mês', sufixo: 'dias', inteiro: true)],
          validar: () => _invalido(_dias, minimo: -1, maximo: 31) ? 'Digite um número de dias entre 0 e 31.' : null,
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
        titulo: 'Estimar o gasto',
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
        titulo: 'Estimar o gasto',
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
    final continuar = FilledButton(onPressed: () => _continuar(p), child: const Text('Continuar'));
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
