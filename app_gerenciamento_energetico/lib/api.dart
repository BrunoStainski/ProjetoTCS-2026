// Comunicacao com a API do Iamp (FastAPI em src/main.py).
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

/// Quantos modelos de cada tipo de aparelho a busca traz (GET /aparelhos?limite=).
const limiteBuscaPorTipo = 30;

/// Quantos modelos de uma marca a lista de marcas mostra (GET /modelos?limite=).
const limiteModelosDaMarca = 50;

/// Marca de um tipo de aparelho, com a quantidade de modelos (GET /marcas).
class Marca {
  final String nome;
  final int modelos;

  const Marca(this.nome, this.modelos);

  Marca.fromJson(Map<String, dynamic> j) : nome = j['marca'], modelos = j['modelos'];
}

class Aparelho {
  final int id;
  final String categoria;
  final String marca;
  final String modelo;
  final String detalhe;

  /// Na busca: quantos modelos desse tipo bateram com o texto (a API manda no maximo `limite` por tipo).
  final int totalCategoria;

  const Aparelho({
    required this.id,
    required this.categoria,
    required this.marca,
    required this.modelo,
    this.detalhe = '',
    this.totalCategoria = 0,
  });

  Aparelho.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      categoria = j['categoria'],
      marca = j['marca'],
      modelo = j['modelo'],
      detalhe = j['detalhe'] ?? '',
      totalCategoria = j['total_categoria'] ?? 0;

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
  final bool perguntarHoras; // ventiladores: depois da velocidade, pergunta as horas por dia

  PerguntaDeUso.fromJson(Map<String, dynamic> j)
    : pergunta = j['pergunta'],
      opcoes = List<String>.from(j['opcoes'] ?? const []),
      padrao = j['padrao'],
      opcional = j['opcional'] ?? false,
      perguntarHoras = j['perguntar_horas'] ?? false;
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
  final bool pelosParecidos; // gasto da mediana dos modelos parecidos (sem o numero do aparelho)

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
      capacidade = _realOuNulo(j['capacidade']),
      pelosParecidos = j['pelos_parecidos'] ?? false;

  String get nome => '$marca $modelo';
  bool get temFaixa => custoMinMes != null && custoMaxMes != null && custoMaxMes! > custoMinMes!;
}

/// Tipo do Inmetro com um nome que a pessoa reconhece olhando o aparelho.
class TipoEstimavel {
  final String valor; // vai para a API como esta
  final String nome;
  final String? descricao;

  TipoEstimavel.fromJson(Map<String, dynamic> j) : valor = j['valor'], nome = j['nome'], descricao = j['descricao'];
}

class TamanhoComum {
  final double valor;
  final String nome;

  TamanhoComum.fromJson(Map<String, dynamic> j) : valor = (j['valor'] as num).toDouble(), nome = j['nome'];
}

/// Numero escrito no proprio aparelho (etiqueta do Inmetro ou potencia da plaqueta).
class FormaDeInformar {
  final String campo; // kwh_mes, kwh_ciclo ou potencia_w
  final String nome;
  final String rotulo;
  final String unidade;
  final String onde;
  final String? dica;
  final String exemplo;
  final double maximo;

  FormaDeInformar.fromJson(Map<String, dynamic> j)
    : campo = j['campo'],
      nome = j['nome'],
      rotulo = j['rotulo'],
      unidade = j['unidade'],
      onde = j['onde'],
      dica = j['dica'],
      exemplo = j['exemplo'],
      maximo = (j['maximo'] as num).toDouble();
}

class CategoriaEstimavel {
  final String categoria;
  final String nome;
  final bool especial;
  final String? medida;
  final String? unidadeMedida;
  final List<TamanhoComum> tamanhos;
  final List<TipoEstimavel> tipos;
  final List<FormaDeInformar> formas;
  final bool valorObrigatorio; // sem catalogo para comparar: precisa de uma das formas
  final PerguntaDeUso uso;

  CategoriaEstimavel.fromJson(Map<String, dynamic> j)
    : categoria = j['categoria'],
      nome = j['nome'],
      especial = j['especial'] ?? false,
      medida = j['medida'],
      unidadeMedida = j['unidade_medida'],
      tamanhos = [for (final t in j['tamanhos'] ?? const []) TamanhoComum.fromJson(t)],
      tipos = [for (final t in j['tipos'] ?? const []) TipoEstimavel.fromJson(t)],
      formas = [for (final f in j['formas'] ?? const []) FormaDeInformar.fromJson(f)],
      valorObrigatorio = j['valor_obrigatorio'] ?? false,
      uso = PerguntaDeUso.fromJson(j['uso']);
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

  static Future<dynamic> _post(
    String caminho,
    Map<String, dynamic> corpo, {
    Duration limite = const Duration(seconds: 15),
  }) async {
    final uri = Uri.parse('$apiUrl$caminho');
    return _tratar(
      () => http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(corpo)),
      limite: limite,
    );
  }

  static Future<dynamic> _tratar(
    Future<http.Response> Function() chamada, {
    Duration limite = const Duration(seconds: 15),
  }) async {
    final http.Response resposta;
    try {
      resposta = await chamada().timeout(limite);
    } catch (_) {
      throw ApiErro('Não consegui me conectar ao Iamp. Confira a internet e tente de novo.');
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
    // limite por tipo de aparelho: uma marca com varios tipos traz todos
    final lista = await _get('/aparelhos', {'busca': busca, 'categoria': ?categoria, 'limite': '$limiteBuscaPorTipo'});
    return [for (final j in lista) Aparelho.fromJson(j)];
  }

  /// Todas as marcas de um tipo de aparelho (lista de marcas da etapa 2).
  static Future<List<Marca>> marcas(String categoria) async {
    final lista = await _get('/marcas', {'categoria': categoria});
    return [for (final j in lista) Marca.fromJson(j)];
  }

  /// Modelos de uma marca dentro de um tipo (abre ao tocar na marca).
  static Future<List<Aparelho>> modelosDaMarca(String categoria, String marca) async {
    final lista = await _get('/modelos', {'categoria': categoria, 'marca': marca, 'limite': '$limiteModelosDaMarca'});
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

  static Future<List<Resistivo>> resistivos() async => [
    for (final j in await _get('/resistivos')) Resistivo.fromJson(j),
  ];

  static Future<Dicas> dicas(Resultado r) async => Dicas.fromJson(
    await _post('/eco-coach/aparelho', {
      'categoria': r.categoria,
      'nome': r.nome,
      'kwh_mes': r.kwhMes,
      'custo_mes': r.custoMes,
      'metodo': r.metodo,
    }, limite: const Duration(seconds: 60)),
  );

  static Future<List<CategoriaEstimavel>> categoriasEstimaveis() async => [
    for (final j in await _get('/estimativa/categorias')) CategoriaEstimavel.fromJson(j),
  ];

  static Map<String, dynamic> _atualEstimado(Resultado atual) => {
    'categoria': atual.categoria,
    'capacidade': atual.capacidade,
    'tipo': atual.tipo,
    'kwh_mes': atual.kwhMes,
    'nome': atual.nome,
    'pelos_parecidos': atual.pelosParecidos,
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
      ..._atualEstimado(atual)
        ..remove('capacidade')
        ..remove('tipo')
        ..remove('pelos_parecidos'),
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

  /// Plano do Eco-Coach (RAG + Gemini). O LLM pode levar alguns segundos: limite maior.
  static Future<EcoCoach> ecoCoach(int moradores, List<Map<String, dynamic>> itens, List<TrocaAvaliada> trocas) async =>
      EcoCoach.fromJson(
        await _post('/eco-coach', {
          'moradores': moradores,
          'itens': itens,
          'trocas': [for (final t in trocas) t.paraApi()],
        }, limite: const Duration(seconds: 90)),
      );
}

/// Troca ja calculada em "Vale a pena trocar?" (vai para o Eco-Coach usar os numeros do Iamp).
class TrocaAvaliada {
  final String aparelho;
  final String alternativa;
  final double economiaMes;
  final double? paybackMeses;

  const TrocaAvaliada({
    required this.aparelho,
    required this.alternativa,
    required this.economiaMes,
    this.paybackMeses,
  });

  Map<String, dynamic> paraApi() => {
    'aparelho': aparelho,
    'alternativa': alternativa,
    'economia_mes': economiaMes,
    'payback_meses': paybackMeses,
  };
}

class FonteCitada {
  final int n;
  final String documento;
  final String orgao;
  final String url;
  final String? secao;
  final int? pagina;

  FonteCitada.fromJson(Map<String, dynamic> j)
    : n = j['n'],
      documento = j['documento'],
      orgao = j['orgao'],
      url = j['url'],
      secao = j['secao'],
      pagina = j['pagina'];
}

class MaiorConsumo {
  final String categoria;
  final String nome;
  final double kwhMes;
  final double? custoMes;
  final double percentual;

  MaiorConsumo.fromJson(Map<String, dynamic> j)
    : categoria = j['categoria'],
      nome = j['nome'],
      kwhMes = _real(j['kwh_mes']),
      custoMes = _realOuNulo(j['custo_mes']),
      percentual = _real(j['percentual']);
}

/// Resposta de POST /eco-coach: numeros calculados pelo Iamp + plano escrito pelo LLM com fontes [n].
class EcoCoach {
  final String perfil;
  final double kwhTotal;
  final double? custoTotal;
  final List<MaiorConsumo> maioresConsumos;
  final String plano; // markdown
  final List<FonteCitada> fontes;
  final String modelo;
  final String aviso;

  EcoCoach.fromJson(Map<String, dynamic> j)
    : perfil = j['perfil'],
      kwhTotal = _real(j['kwh_total']),
      custoTotal = _realOuNulo(j['custo_total']),
      maioresConsumos = [for (final m in j['maiores_consumos']) MaiorConsumo.fromJson(m)],
      plano = j['plano'],
      fontes = [for (final f in j['fontes']) FonteCitada.fromJson(f)],
      modelo = j['modelo'],
      aviso = j['aviso'];
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
