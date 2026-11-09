// Comunicacao com a API do iamp (FastAPI em src/main.py).
//
// Endereco padrao: http://localhost:8000
// No emulador Android, "localhost" e o proprio celular; o computador e 10.0.2.2.
// Para trocar: flutter run --dart-define=API_URL=http://outro-endereco:8000
// (num celular de verdade, use o IP do computador na rede, ex.: http://192.168.0.10:8000)

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const String _apiUrlInformada = String.fromEnvironment('API_URL');

final String apiUrl = _apiUrlInformada.isNotEmpty
    ? _apiUrlInformada
    : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
    ? 'http://10.0.2.2:8000'
    : 'http://localhost:8000';

class ApiErro implements Exception {
  final String mensagem;
  ApiErro(this.mensagem);

  @override
  String toString() => mensagem;
}

double _real(dynamic v) => (v as num).toDouble();
double? _realOuNulo(dynamic v) => v == null ? null : (v as num).toDouble();

/// "lampada_led" -> "lampada led"
String legivel(String categoria) => categoria.replaceAll('_', ' ');

class Aparelho {
  final int id;
  final String categoria;
  final String marca;
  final String modelo;
  final String detalhe;

  const Aparelho({
    required this.id,
    required this.categoria,
    required this.marca,
    required this.modelo,
    this.detalhe = '',
  });

  Aparelho.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      categoria = j['categoria'],
      marca = j['marca'],
      modelo = j['modelo'],
      detalhe = j['detalhe'] ?? '';

  String get nome => '$marca $modelo';
  String get categoriaLegivel => legivel(categoria);
}

/// O que o app precisa perguntar antes de calcular.
/// pergunta: null (nada), "horas", "ciclos" ou "velocidade".
/// opcional: o usuario pode deixar em branco e fica o consumo do Inmetro (TV e ar-condicionado).
class PerguntaDeUso {
  final String? pergunta;
  final List<String> opcoes;
  final dynamic padrao;
  final bool opcional;

  PerguntaDeUso.fromJson(Map<String, dynamic> j)
    : pergunta = j['pergunta'],
      opcoes = List<String>.from(j['opcoes'] ?? const []),
      padrao = j['padrao'],
      opcional = j['opcional'] ?? false;
}

class Distribuidora {
  final int id;
  final String nome;
  final String? uf;
  final double tarifaKwh;

  Distribuidora.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      nome = j['nome'],
      uf = j['uf'],
      tarifaKwh = _real(j['tarifa_kwh']);
}

class Resultado {
  final String categoria;
  final String marca;
  final String modelo;
  final String detalhe;
  final String distribuidora;
  final String uf;
  final double kwhMes;
  final String metodo;
  final double tarifaKwh;
  final String origemTarifa;
  final double custoMes;
  final double custoAno;
  final List<String> avisos;
  final bool aproximado;
  final double? kwhMin;
  final double? kwhMax;
  final double? custoMinMes;
  final double? custoMaxMes;
  final String? tipo;
  final double? capacidade;

  Resultado.fromJson(Map<String, dynamic> j)
    : categoria = j['categoria'],
      marca = j['marca'],
      modelo = j['modelo'],
      detalhe = j['detalhe'] ?? '',
      distribuidora = j['distribuidora'],
      uf = j['uf'],
      kwhMes = _real(j['kwh_mes']),
      metodo = j['metodo'],
      tarifaKwh = _real(j['tarifa_kwh']),
      origemTarifa = j['origem_tarifa'],
      custoMes = _real(j['custo_mes']),
      custoAno = _real(j['custo_ano']),
      avisos = List<String>.from(j['avisos'] ?? const []),
      aproximado = j['aproximado'] ?? false,
      kwhMin = _realOuNulo(j['kwh_min']),
      kwhMax = _realOuNulo(j['kwh_max']),
      custoMinMes = _realOuNulo(j['custo_min_mes']),
      custoMaxMes = _realOuNulo(j['custo_max_mes']),
      tipo = j['tipo'],
      capacidade = _realOuNulo(j['capacidade']);

  String get nome => '$marca $modelo';
  bool get temFaixa => custoMinMes != null && custoMaxMes != null && custoMaxMes! > custoMinMes!;
}

class CategoriaEstimavel {
  final String categoria;
  final String nome;
  final bool especial;
  final String? medida;
  final List<String> tipos;
  final String? etiquetaRotulo;
  final bool etiquetaObrigatoria;
  final PerguntaDeUso uso;

  CategoriaEstimavel.fromJson(Map<String, dynamic> j)
    : categoria = j['categoria'],
      nome = j['nome'],
      especial = j['especial'] ?? false,
      medida = j['medida'],
      tipos = List<String>.from(j['tipos'] ?? const []),
      etiquetaRotulo = j['etiqueta_rotulo'],
      etiquetaObrigatoria = j['etiqueta_obrigatoria'] ?? false,
      uso = PerguntaDeUso.fromJson(j['uso']);
}

class FonteCitada {
  final int n;
  final String documento;
  final String orgao;
  final String url;

  FonteCitada.fromJson(Map<String, dynamic> j)
    : n = j['n'],
      documento = j['documento'],
      orgao = j['orgao'],
      url = j['url'];
}

class Dicas {
  final String texto;
  final List<FonteCitada> fontes;
  final String aviso;

  Dicas.fromJson(Map<String, dynamic> j)
    : texto = j['dicas'],
      fontes = [for (final f in j['fontes']) FonteCitada.fromJson(f)],
      aviso = j['aviso'];
}

class Resistivo {
  final String categoria;
  final String nome;
  final double potenciaW;
  final double horasDia;
  final double diasMes;

  Resistivo.fromJson(Map<String, dynamic> j)
    : categoria = j['categoria'],
      nome = j['nome'],
      potenciaW = _real(j['potencia_w']),
      horasDia = _real(j['horas_dia']),
      diasMes = _real(j['dias_mes']);
}

/// Um modelo mais economico que faz o mesmo servico (POST /sugestoes).
class AparelhoSugerido {
  final Aparelho aparelho;
  final String tipo;
  final double kwhMes;
  final double custoMes;
  final double economiaKwhMes;
  final double economiaMes;
  final double economiaAno;
  final double economiaPercentual;

  AparelhoSugerido.fromJson(Map<String, dynamic> j)
    : aparelho = Aparelho.fromJson(j),
      tipo = j['tipo'] ?? '',
      kwhMes = _real(j['kwh_mes']),
      custoMes = _real(j['custo_mes']),
      economiaKwhMes = _real(j['economia_kwh_mes']),
      economiaMes = _real(j['economia_mes']),
      economiaAno = _real(j['economia_ano']),
      economiaPercentual = _real(j['economia_percentual']);
}

class Sugestoes {
  final double kwhAtual;
  final double custoAtual;
  final String? criterio;
  final String? mensagem;
  final int suspeitosDescartados;
  final List<AparelhoSugerido> sugestoes;

  Sugestoes.fromJson(Map<String, dynamic> j)
    : kwhAtual = _real(j['atual']['kwh_mes']),
      custoAtual = _real(j['atual']['custo_mes']),
      criterio = j['criterio'],
      mensagem = j['mensagem'],
      suspeitosDescartados = j['suspeitos_descartados'] ?? 0,
      sugestoes = [for (final s in j['sugestoes']) AparelhoSugerido.fromJson(s)];
}

class Payback {
  final double precoNovo;
  final double? meses;
  final double? anos;
  final String texto;

  Payback.fromJson(Map<String, dynamic> j)
    : precoNovo = _real(j['preco_novo']),
      meses = _realOuNulo(j['meses']),
      anos = _realOuNulo(j['anos']),
      texto = j['texto'];
}

class Comparacao {
  final Resultado atual;
  final Resultado novo;
  final double economiaKwhMes;
  final double economiaMes;
  final double economiaAno;
  final Payback? payback;
  final List<String> avisos;

  Comparacao.fromJson(Map<String, dynamic> j)
    : atual = Resultado.fromJson(j['atual']),
      novo = Resultado.fromJson(j['novo']),
      economiaKwhMes = _real(j['economia_kwh_mes']),
      economiaMes = _real(j['economia_mes']),
      economiaAno = _real(j['economia_ano']),
      payback = j['payback'] == null ? null : Payback.fromJson(j['payback']),
      avisos = List<String>.from(j['avisos'] ?? const []);
}

/// Perfil da casa pelo K-Means (POST /classificar).
class Classificacao {
  final String perfil;
  final double kwhTotal;
  final double kwhPorMorador;
  final double medianaKwhPorMorador;
  final double diferencaPercentual;
  final String comparacaoTexto;
  final Map<String, double> fracoes;
  final String aviso;

  Classificacao.fromJson(Map<String, dynamic> j)
    : perfil = j['perfil'],
      kwhTotal = _real(j['kwh_total']),
      kwhPorMorador = _real(j['kwh_por_morador']),
      medianaKwhPorMorador = _real(j['comparacao_media']['mediana_kwh_por_morador']),
      diferencaPercentual = _real(j['comparacao_media']['diferenca_percentual']),
      comparacaoTexto = j['comparacao_media']['texto'],
      fracoes = {for (final e in (j['fracoes'] as Map).entries) e.key as String: _real(e.value)},
      aviso = j['aviso'];
}

class Api {
  static Future<dynamic> _get(String caminho, [Map<String, String>? params]) async {
    final uri = Uri.parse('$apiUrl$caminho').replace(queryParameters: params);
    return _tratar(() => http.get(uri));
  }

  static Future<dynamic> _post(String caminho, Map<String, dynamic> corpo, {Duration? espera}) async {
    final uri = Uri.parse('$apiUrl$caminho');
    return _tratar(
      () => http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(corpo)),
      espera: espera,
    );
  }

  static Future<dynamic> _tratar(Future<http.Response> Function() chamada, {Duration? espera}) async {
    final http.Response resposta;
    try {
      resposta = await chamada().timeout(espera ?? const Duration(seconds: 15));
    } catch (_) {
      throw ApiErro('Nao consegui falar com a API em $apiUrl. Ela esta rodando? (docker compose up -d)');
    }
    final corpo = jsonDecode(utf8.decode(resposta.bodyBytes));
    if (resposta.statusCode >= 400) {
      final detalhe = corpo is Map ? corpo['detail'] : null;
      if (detalhe is String) throw ApiErro(detalhe);
      if (detalhe is List && detalhe.isNotEmpty && detalhe.first is Map) {
        throw ApiErro('${detalhe.first['msg']}');
      }
      throw ApiErro('Erro ${resposta.statusCode} na API');
    }
    return corpo;
  }

  static Future<List<String>> categorias() async => List<String>.from(await _get('/categorias'));

  static Future<List<Aparelho>> buscarAparelhos(String busca, {String? categoria}) async {
    final lista = await _get('/aparelhos', {'busca': busca, 'categoria': ?categoria, 'limite': '30'});
    return [for (final j in lista) Aparelho.fromJson(j)];
  }

  static Future<PerguntaDeUso> perguntaDeUso(int aparelhoId) async =>
      PerguntaDeUso.fromJson(await _get('/aparelhos/$aparelhoId/uso'));

  static Future<List<String>> ufs() async => List<String>.from(await _get('/ufs'));

  static Future<List<Distribuidora>> distribuidoras({String? uf}) async {
    final lista = await _get('/distribuidoras', {'uf': ?uf});
    return [for (final j in lista) Distribuidora.fromJson(j)];
  }

  /// usoETarifa: distribuidora_id ou tarifa_manual, mais horas_dia, ciclos_mes ou velocidade.
  static Future<Resultado> calcular(int aparelhoId, Map<String, dynamic> usoETarifa) async =>
      Resultado.fromJson(await _post('/calcular', {'aparelho_id': aparelhoId, ...usoETarifa}));

  static Future<Resultado> estimar(String rota, Map<String, dynamic> corpo) async =>
      Resultado.fromJson(await _post(rota, corpo));

  static Future<List<Resistivo>> resistivos() async =>
      [for (final j in await _get('/resistivos')) Resistivo.fromJson(j)];

  static Future<Dicas> dicas(Resultado r) async => Dicas.fromJson(
    await _post('/eco-coach/aparelho', {
      'categoria': r.categoria,
      'nome': r.nome,
      'kwh_mes': r.kwhMes,
      'custo_mes': r.custoMes,
      'metodo': r.metodo,
    }, espera: const Duration(seconds: 60)),
  );

  static Future<List<CategoriaEstimavel>> categoriasEstimaveis() async =>
      [for (final j in await _get('/estimativa/categorias')) CategoriaEstimavel.fromJson(j)];

  static Map<String, dynamic> _atualEstimado(Resultado atual) => {
    'categoria': atual.categoria,
    'capacidade': atual.capacidade,
    'tipo': atual.tipo,
    'kwh_mes': atual.kwhMes,
    'nome': atual.nome,
  };

  static Future<Sugestoes> sugestoesEstimado(Resultado atual, Map<String, dynamic> usoETarifa) async =>
      Sugestoes.fromJson(await _post('/sugestoes/estimado', {..._atualEstimado(atual), ...usoETarifa}));

  static Future<Comparacao> compararEstimado(
    Resultado atual,
    int alternativaId,
    Map<String, dynamic> usoETarifa, {
    double? precoNovo,
  }) async => Comparacao.fromJson(
    await _post('/comparar/estimado', {
      ..._atualEstimado(atual)..remove('capacidade')..remove('tipo'),
      'alternativa_id': alternativaId,
      'preco_novo': precoNovo,
      ...usoETarifa,
    }),
  );

  static Future<Sugestoes> sugestoes(int aparelhoId, Map<String, dynamic> usoETarifa) async =>
      Sugestoes.fromJson(await _post('/sugestoes', {'aparelho_id': aparelhoId, ...usoETarifa}));

  static Future<Comparacao> comparar(
    int aparelhoId,
    int alternativaId,
    Map<String, dynamic> usoETarifa, {
    double? precoNovo,
  }) async => Comparacao.fromJson(
    await _post('/comparar', {
      'aparelho_id': aparelhoId,
      'alternativa_id': alternativaId,
      'preco_novo': precoNovo,
      ...usoETarifa,
    }),
  );

  /// itens: [{categoria, kwh_mes}] da casa.
  static Future<Classificacao> classificar(int moradores, List<Map<String, dynamic>> itens) async =>
      Classificacao.fromJson(await _post('/classificar', {'moradores': moradores, 'itens': itens}));
}

/// 1234.5 -> "R$ 1.234,50"
String reais(double valor, {int casas = 2}) {
  final negativo = valor < 0;
  final partes = valor.abs().toStringAsFixed(casas).split('.');
  final inteiro = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${negativo ? '-' : ''}R\$ $inteiro${casas > 0 ? ',${partes[1]}' : ''}';
}

String duracao(double horas) {
  final total = (horas * 60).round();
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// 41.25 -> "41,25"
String numero(double valor, {int casas = 2}) => valor.toStringAsFixed(casas).replaceAll('.', ',');

/// Aceita "0,25", "0.25", "1.299,90" e "R$ 1.299,90"
double? lerNumero(String texto) {
  var t = texto.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(t);
}
