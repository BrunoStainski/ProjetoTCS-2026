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
  Grupo _grupo = Grupo.pesado;
  List<CategoriaEstimavel>? _categorias;
  CategoriaEstimavel? _categoria;
  String? _erro;

  String _tipoGeladeira = 'duplex';
  bool _frostFree = true;
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
  bool get _soFreezer => _tipoGeladeira.startsWith('freezer');

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
    setState(() => _erro = null);
    try {
      final categorias = await widget.carregarCategorias();
      final resistivos = await widget.carregarResistivos();
      if (!mounted) return;
      setState(() {
        _categorias = categorias;
        _resistivos = resistivos;
        if (categorias.isNotEmpty) _escolherCategoria(categorias.first);
        if (resistivos.isNotEmpty) _escolherResistivo(resistivos.first);
      });
    } catch (_) {
      if (mounted) setState(() => _erro = 'Não consegui carregar os aparelhos. A API está rodando?');
    }
  }

  void _escolherCategoria(CategoriaEstimavel c) {
    _categoria = c;
    _tipo = null;
    _medida.clear();
    _etiqueta.clear();
    _erro = null;
    final uso = c.uso;
    _tempo.definir(uso.pergunta == 'horas' ? (uso.padrao as num?)?.toDouble() : null);
    _ciclos.text = uso.pergunta == 'ciclos' && uso.padrao != null ? numero((uso.padrao as num).toDouble(), casas: 0) : '';
    _velocidade = uso.pergunta == 'velocidade' ? uso.padrao as String? : null;
  }

  void _escolherResistivo(Resistivo r) {
    _resistivo = r;
    _tempoPortatil.definir(r.horasDia);
    _dias.text = numero(r.diasMes, casas: 0);
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

  void _mostrarErro(String mensagem) => setState(() => _erro = mensagem);

  void _continuar() {
    if (_grupo == Grupo.portatil) return _continuarPortatil();
    if (_categoria == null) return;
    _geladeira ? _continuarGeladeira() : _continuarPesado(_categoria!);
  }

  void _continuarGeladeira() {
    final volume = lerNumero(_medida.text);
    final ano = int.tryParse(_ano.text.trim());
    final anoAtual = DateTime.now().year;
    if (volume == null || volume <= 0 || volume > 1000) {
      return _mostrarErro('Informe a capacidade total em litros (está na etiqueta ou no manual).');
    }
    if (ano == null || ano < 1980 || ano > anoAtual) {
      return _mostrarErro('Informe o ano de compra entre 1980 e $anoAtual (ex.: 2014).');
    }
    final congelador = _soFreezer ? null : _opcional(_congelador);
    if (!_soFreezer && (_invalido(_congelador, minimo: -1) || (congelador ?? 0) > volume)) {
      return _mostrarErro('Os litros do freezer precisam ser um número menor que a capacidade total.');
    }
    if (_invalido(_etiqueta, maximo: 300)) {
      return _mostrarErro('O consumo da etiqueta precisa ser um número em kWh/mês (ex.: 52,5).');
    }
    final (marca, modelo) = _marcaEModelo();
    _seguir(
      Consulta(
        Aparelho(id: 0, categoria: 'refrigerador', marca: marca ?? 'Geladeira', modelo: modelo ?? ''),
        estimativa: Estimativa(rotaGeladeira, {
          'tipo': _tipoGeladeira,
          'frost_free': _frostFree,
          'volume_total_l': volume,
          'volume_congelador_l': congelador,
          'ano_compra': ano,
          'kwh_etiqueta': _opcional(_etiqueta),
          'marca': marca,
          'modelo': modelo,
        }),
      ),
    );
  }

  void _continuarPesado(CategoriaEstimavel c) {
    if (_invalido(_medida) || _invalido(_etiqueta)) return _mostrarErro('Confira os números digitados.');
    final medida = _opcional(_medida);
    final etiqueta = _opcional(_etiqueta);
    if (c.etiquetaObrigatoria && etiqueta == null) return _mostrarErro('Preencha o campo "${c.etiquetaRotulo}".');
    if (!c.etiquetaObrigatoria && medida == null && etiqueta == null) {
      return _mostrarErro('Informe ${c.medida!.toLowerCase()} ou o valor da etiqueta.');
    }
    if (c.tipos.isNotEmpty && _tipo == null && etiqueta == null) return _mostrarErro('Escolha o tipo.');

    double? horas;
    double? ciclos;
    switch (c.uso.pergunta) {
      case 'horas':
        if (!_tempo.valido) return _mostrarErro('Confira o tempo de uso (minutos de 0 a 59, até 24 h por dia).');
        horas = _tempo.horasDia;
        if (horas == null && !c.uso.opcional) return _mostrarErro('Informe o tempo de uso por dia.');
      case 'ciclos':
        ciclos = lerNumero(_ciclos.text);
        if (ciclos == null || ciclos < 0) return _mostrarErro('Informe quantas lavagens por mês.');
    }
    final (marca, modelo) = _marcaEModelo();
    _seguir(
      Consulta(
        Aparelho(id: 0, categoria: c.categoria, marca: marca ?? c.nome, modelo: modelo ?? ''),
        estimativa: Estimativa(rotaEstimado, {
          'categoria': c.categoria,
          'tipo': _tipo,
          'medida': medida,
          'valor_etiqueta': etiqueta,
          'marca': marca,
          'modelo': modelo,
        }),
        horasDia: horas,
        ciclosMes: ciclos,
        velocidade: c.uso.pergunta == 'velocidade' ? _velocidade : null,
      ),
    );
  }

  void _continuarPortatil() {
    final r = _resistivo;
    if (r == null) return _mostrarErro('Escolha o aparelho.');
    if (_invalido(_potencia, maximo: 10000) || _invalido(_dias, minimo: -1, maximo: 31)) {
      return _mostrarErro('Confira os números: potência em W e dias entre 0 e 31.');
    }
    if (!_tempoPortatil.valido) return _mostrarErro('Confira o tempo de uso (minutos de 0 a 59, até 24 h por dia).');
    _seguir(
      Consulta(
        Aparelho(id: 0, categoria: r.categoria, marca: r.nome, modelo: ''),
        estimativa: Estimativa(rotaResistivo, {
          'categoria': r.categoria,
          'potencia_w': _opcional(_potencia),
          'dias_mes': _opcional(_dias),
        }),
        horasDia: _tempoPortatil.horasDia,
      ),
    );
  }

  void _seguir(Consulta consulta) {
    setState(() => _erro = null);
    Navigator.push(context, MaterialPageRoute(builder: (_) => TelaDistribuidora(consulta: consulta)));
  }

  @override
  Widget build(BuildContext context) {
    final carregado = _categorias != null && _resistivos != null;
    return Pagina(
      titulo: 'Estimar o gasto',
      rodape: carregado ? FilledButton(onPressed: _continuar, child: const Text('Continuar')) : null,
      filho: ListView(
        children: [
          const Text(
            'Não está no catálogo do Inmetro? Calculamos um gasto aproximado com o que você souber do aparelho.',
            style: Estilos.secundario,
          ),
          const SizedBox(height: Espaco.m),
          SegmentedButton<Grupo>(
            segments: const [
              ButtonSegment(value: Grupo.pesado, label: Text('Eletro pesado'), icon: Icon(Icons.kitchen)),
              ButtonSegment(value: Grupo.portatil, label: Text('Eletroportáteis'), icon: Icon(Icons.blender_outlined)),
            ],
            selected: {_grupo},
            onSelectionChanged: (s) => setState(() {
              _grupo = s.first;
              _erro = null;
            }),
          ),
          const SizedBox(height: Espaco.m),
          if (_erro != null) ...[
            MensagemErro(_erro!, tentarDeNovo: carregado ? null : _carregar),
            const SizedBox(height: Espaco.p),
          ],
          if (!carregado && _erro == null) const Center(child: CircularProgressIndicator()),
          if (carregado) ...(_grupo == Grupo.pesado ? _camposPesado() : _camposPortatil()),
        ],
      ),
    );
  }

  List<Widget> _camposPesado() {
    final c = _categoria;
    return [
      _lista<CategoriaEstimavel>(
        rotulo: 'Aparelho',
        valor: c,
        opcoes: _categorias!,
        texto: (x) => legivel(x.nome),
        aoMudar: (x) => setState(() => _escolherCategoria(x)),
      ),
      if (c != null) ...(c.especial ? _camposGeladeira() : _camposCategoria(c)),
      _campo(_nome, 'Marca e modelo (opcional)', exemplo: 'Ex.: Consul CRM45', texto: true),
    ];
  }

  List<Widget> _camposGeladeira() => [
    _lista<String>(
      rotulo: 'Tipo',
      valor: _tipoGeladeira,
      opcoes: tiposDeGeladeira.keys.toList(),
      texto: (t) => tiposDeGeladeira[t]!,
      aoMudar: (t) => setState(() => _tipoGeladeira = t),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _frostFree,
      onChanged: (v) => setState(() => _frostFree = v),
      title: const Text('Frost-free'),
      subtitle: const Text('Não forma gelo nas paredes (não precisa degelar).', style: Estilos.secundario),
    ),
    _campo(_medida, 'Capacidade total (litros)', exemplo: 'Ex.: 407'),
    if (!_soFreezer)
      _campo(
        _congelador,
        'Litros do freezer (opcional)',
        exemplo: 'Ex.: 90',
        ajuda: 'Melhora a estimativa. Está na etiqueta ou no manual.',
      ),
    _campo(_ano, 'Ano de compra', exemplo: 'Ex.: 2014', inteiro: true),
    const Titulo('Tem a etiqueta do Inmetro?'),
    _campo(
      _etiqueta,
      'Consumo da etiqueta em kWh/mês (opcional)',
      exemplo: 'Ex.: 52,5',
      ajuda: 'É o número em kWh/mês da etiqueta colada no aparelho. Com ele o resultado fica bem mais preciso.',
    ),
  ];

  List<Widget> _camposCategoria(CategoriaEstimavel c) => [
    if (c.tipos.isNotEmpty)
      _lista<String>(
        rotulo: 'Tipo',
        valor: _tipo,
        opcoes: c.tipos,
        texto: (t) => t,
        aoMudar: (t) => setState(() => _tipo = t),
      ),
    if (c.medida != null) _campo(_medida, legivel(c.medida!)),
    if (c.etiquetaRotulo != null) ...[
      if (!c.etiquetaObrigatoria) const Titulo('Tem a etiqueta do Inmetro?'),
      _campo(
        _etiqueta,
        c.etiquetaObrigatoria ? legivel(c.etiquetaRotulo!) : '${legivel(c.etiquetaRotulo!)} (opcional)',
        ajuda: c.etiquetaObrigatoria
            ? 'Está escrita no próprio aparelho ou na embalagem.'
            : 'Com o valor da etiqueta o cálculo fica exato. Sem ele, usamos modelos parecidos do catálogo.',
      ),
    ],
    ..._camposUso(c.uso),
  ];

  List<Widget> _camposUso(PerguntaDeUso uso) => switch (uso.pergunta) {
    'horas' => [
      CampoTempo(
        controle: _tempo,
        rotulo: uso.opcional ? 'Tempo de uso por dia (opcional)' : 'Tempo de uso por dia',
        ajuda: uso.opcional
            ? 'Em branco, usamos o consumo do ensaio do Inmetro.'
            : uso.padrao != null
            ? 'Valor sugerido é uma estimativa. Troque pelo seu uso real.'
            : 'Obrigatório. Ex.: 0 h 15 min.',
      ),
      const SizedBox(height: Espaco.m),
    ],
    'ciclos' => [_campo(_ciclos, 'Lavagens por mês', inteiro: true)],
    'velocidade' => [
      const Text('Em qual velocidade você costuma usar?', style: Estilos.forte),
      const SizedBox(height: Espaco.p),
      SegmentedButton<String>(
        segments: [for (final o in uso.opcoes) ButtonSegment(value: o, label: Text(o))],
        selected: {?_velocidade},
        onSelectionChanged: (s) => setState(() => _velocidade = s.first),
      ),
      const SizedBox(height: Espaco.m),
    ],
    _ => const [],
  };

  List<Widget> _camposPortatil() {
    final r = _resistivo;
    return [
      _lista<Resistivo>(
        rotulo: 'Aparelho',
        valor: r,
        opcoes: _resistivos!,
        texto: (x) => legivel(x.nome),
        aoMudar: (x) => setState(() => _escolherResistivo(x)),
      ),
      _campo(
        _potencia,
        'Potência em W (opcional)',
        exemplo: r == null ? null : 'Típica: ${numero(r.potenciaW, casas: 0)} W',
        ajuda: 'Está na etiqueta embaixo ou atrás do aparelho. Em branco, usamos a típica.',
      ),
      CampoTempo(
        controle: _tempoPortatil,
        rotulo: 'Tempo de uso por dia',
        ajuda: r == null ? null : 'Sugerido: ${duracao(r.horasDia)}. Troque pelo seu uso real.',
      ),
      const SizedBox(height: Espaco.m),
      _campo(_dias, 'Dias de uso no mês', inteiro: true),
    ];
  }

  Widget _lista<T>({
    required String rotulo,
    required T? valor,
    required List<T> opcoes,
    required String Function(T) texto,
    required void Function(T) aoMudar,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Espaco.m),
      child: DropdownButtonFormField<T>(
        key: ValueKey('$rotulo-${_categoria?.categoria}'),
        initialValue: valor,
        isExpanded: true,
        dropdownColor: Cores.superficieAlta,
        iconEnabledColor: Cores.amarelo,
        decoration: InputDecoration(labelText: rotulo),
        items: [for (final o in opcoes) DropdownMenuItem(value: o, child: Text(texto(o)))],
        onChanged: (v) {
          if (v != null) aoMudar(v);
        },
      ),
    );
  }

  Widget _campo(
    TextEditingController controle,
    String rotulo, {
    String? exemplo,
    String? ajuda,
    bool inteiro = false,
    bool texto = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Espaco.m),
      child: TextField(
        controller: controle,
        keyboardType: texto ? TextInputType.text : TextInputType.numberWithOptions(decimal: !inteiro),
        onSubmitted: (_) => _continuar(),
        decoration: InputDecoration(labelText: rotulo, hintText: exemplo, helperText: ajuda, helperMaxLines: 3),
      ),
    );
  }
}
