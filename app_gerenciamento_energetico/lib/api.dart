// Comunicacao com a API do Iamp (FastAPI em src/main.py).
//
// Endereco padrao: http://localhost:8000
// No emulador Android, "localhost" e o proprio celular; o computador e 10.0.2.2.
// Para trocar: flutter run --dart-define=API_URL=http://outro-endereco:8000
// (num celular de verdade, use o IP do computador na rede, ex.: http://192.168.0.10:8000)

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'idioma.dart';

const String _givenApiUrl = String.fromEnvironment('API_URL');

final String apiUrl = _givenApiUrl.isNotEmpty
    ? _givenApiUrl
    : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
    ? 'http://10.0.2.2:8000'
    : 'http://localhost:8000';

class ApiError implements Exception {
  final String message;
  ApiError(this.message);

  @override
  String toString() => message;
}

/// 401: o token da conta venceu ou a conta foi apagada em outro aparelho.
class SessionExpired extends ApiError {
  SessionExpired(super.message);
}

double _real(dynamic v) => (v as num).toDouble();
double? _realOrNull(dynamic v) => v == null ? null : (v as num).toDouble();

/// "lampada_led" -> "lampada led"
String readable(String category) => category.replaceAll('_', ' ');

/// Quantos modelos de cada tipo de aparelho a busca traz (GET /aparelhos?limite=).
const searchLimitPerType = 30;

/// Quantos modelos de uma marca a lista de marcas mostra (GET /modelos?limite=).
const brandModelLimit = 50;

/// Marca de um tipo de aparelho, com a quantidade de modelos (GET /marcas).
class Brand {
  final String name;
  final int models;

  const Brand(this.name, this.models);

  Brand.fromJson(Map<String, dynamic> j) : name = j['marca'], models = j['modelos'];
}

class Appliance {
  final int id;
  final String category;
  final String brand;
  final String model;
  final String detail;

  /// Na busca: quantos modelos desse tipo bateram com o texto (a API manda no maximo `limite` por tipo).
  final int totalCategory;

  const Appliance({
    required this.id,
    required this.category,
    required this.brand,
    required this.model,
    this.detail = '',
    this.totalCategory = 0,
  });

  Appliance.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      category = j['categoria'],
      brand = j['marca'],
      model = j['modelo'],
      detail = j['detalhe'] ?? '',
      totalCategory = j['total_categoria'] ?? 0;

  String get name => '$brand $model';
  String get readableCategory => readable(category);

  /// Para guardar a casa na nuvem (o mesmo formato de fromJson).
  Map<String, dynamic> toJson() => {'id': id, 'categoria': category, 'marca': brand, 'modelo': model, 'detalhe': detail};
}

/// O que o app precisa perguntar antes de calcular.
/// pergunta: null (nada), "horas", "ciclos" ou "velocidade".
/// opcional: o usuario pode deixar em branco e fica o consumo do Inmetro (TV e ar-condicionado).
class UsageQuestion {
  final String? question;
  final List<String> options;
  final dynamic defaults;
  final bool optional;
  final bool askHours; // ventiladores: depois da velocidade, pergunta as horas por dia

  UsageQuestion.fromJson(Map<String, dynamic> j)
    : question = j['pergunta'],
      options = List<String>.from(j['opcoes'] ?? const []),
      defaults = j['padrao'],
      optional = j['opcional'] ?? false,
      askHours = j['perguntar_horas'] ?? false;
}

class Distributor {
  final int id;
  final String name;
  final String? uf;
  final double tariffKwh;

  Distributor.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      name = j['nome'],
      uf = j['uf'],
      tariffKwh = _real(j['tarifa_kwh']);
}

class Result {
  final String category;
  final String brand;
  final String model;
  final String detail;
  final String distributor;
  final String uf;
  final double monthlyKwh;
  final String method;
  final double tariffKwh;
  final String tariffOrigin;
  final double monthlyCost;
  final double yearlyCost;
  final List<String> notices;
  final bool approximate;
  final double? kwhMin;
  final double? kwhMax;
  final double? monthlyMinCost;
  final double? monthlyMaxCost;
  final String? kind;
  final double? capacity;
  final bool bySimilar; // gasto da mediana dos modelos parecidos (sem o numero do aparelho)

  /// O JSON como veio da API: a casa na nuvem guarda o resultado assim e le de volta com fromJson.
  final Map<String, dynamic> json;

  Result.fromJson(Map<String, dynamic> j)
    : json = j,
      category = j['categoria'],
      brand = j['marca'],
      model = j['modelo'],
      detail = j['detalhe'] ?? '',
      distributor = j['distribuidora'],
      uf = j['uf'],
      monthlyKwh = _real(j['kwh_mes']),
      method = j['metodo'],
      tariffKwh = _real(j['tarifa_kwh']),
      tariffOrigin = j['origem_tarifa'],
      monthlyCost = _real(j['custo_mes']),
      yearlyCost = _real(j['custo_ano']),
      notices = List<String>.from(j['avisos'] ?? const []),
      approximate = j['aproximado'] ?? false,
      kwhMin = _realOrNull(j['kwh_min']),
      kwhMax = _realOrNull(j['kwh_max']),
      monthlyMinCost = _realOrNull(j['custo_min_mes']),
      monthlyMaxCost = _realOrNull(j['custo_max_mes']),
      kind = j['tipo'],
      capacity = _realOrNull(j['capacidade']),
      bySimilar = j['pelos_parecidos'] ?? false;

  String get name => '$brand $model';
  bool get hasRange => monthlyMinCost != null && monthlyMaxCost != null && monthlyMaxCost! > monthlyMinCost!;
}

/// Tipo do Inmetro com um nome que a pessoa reconhece olhando o aparelho.
class EstimableType {
  final String value; // vai para a API como esta
  final String name;
  final String? description;

  EstimableType.fromJson(Map<String, dynamic> j) : value = j['valor'], name = j['nome'], description = j['descricao'];
}

class CommonSize {
  final double value;
  final String name;

  CommonSize.fromJson(Map<String, dynamic> j) : value = (j['valor'] as num).toDouble(), name = j['nome'];
}

/// Numero escrito no proprio aparelho (etiqueta do Inmetro ou potencia da plaqueta).
class EntryMode {
  final String field; // kwh_mes, kwh_ciclo ou potencia_w
  final String name;
  final String label;
  final String unit;
  final String where;
  final String? tip;
  final String example;
  final double maximum;

  EntryMode.fromJson(Map<String, dynamic> j)
    : field = j['campo'],
      name = j['nome'],
      label = j['rotulo'],
      unit = j['unidade'],
      where = j['onde'],
      tip = j['dica'],
      example = j['exemplo'],
      maximum = (j['maximo'] as num).toDouble();
}

class EstimableCategory {
  final String category;
  final String name;
  final bool special;
  final String? measure;
  final String? measureUnit;
  final List<CommonSize> sizes;
  final List<EstimableType> types;
  final List<EntryMode> shapes;
  final bool requiredValue; // sem catalogo para comparar: precisa de uma das formas
  final UsageQuestion usage;

  EstimableCategory.fromJson(Map<String, dynamic> j)
    : category = j['categoria'],
      name = j['nome'],
      special = j['especial'] ?? false,
      measure = j['medida'],
      measureUnit = j['unidade_medida'],
      sizes = [for (final t in j['tamanhos'] ?? const []) CommonSize.fromJson(t)],
      types = [for (final t in j['tipos'] ?? const []) EstimableType.fromJson(t)],
      shapes = [for (final f in j['formas'] ?? const []) EntryMode.fromJson(f)],
      requiredValue = j['valor_obrigatorio'] ?? false,
      usage = UsageQuestion.fromJson(j['uso']);
}

class Tips {
  final String text;
  final List<CitedSource> sources;
  final String notice;

  Tips.fromJson(Map<String, dynamic> j)
    : text = j['dicas'],
      sources = [for (final f in j['fontes']) CitedSource.fromJson(f)],
      notice = j['aviso'];
}

class Resistive {
  final String category;
  final String name;
  final double powerW;
  final double dailyHours;
  final double daysPerMonth;

  Resistive.fromJson(Map<String, dynamic> j)
    : category = j['categoria'],
      name = j['nome'],
      powerW = _real(j['potencia_w']),
      dailyHours = _real(j['horas_dia']),
      daysPerMonth = _real(j['dias_mes']);
}

/// Um modelo mais economico que faz o mesmo servico (POST /sugestoes).
class SuggestedAppliance {
  final Appliance appliance;
  final String kind;
  final double monthlyKwh;
  final double monthlyCost;
  final double monthlySavingsKwh;
  final double monthlySavings;
  final double yearlySavings;
  final double percentageSavings;

  SuggestedAppliance.fromJson(Map<String, dynamic> j)
    : appliance = Appliance.fromJson(j),
      kind = j['tipo'] ?? '',
      monthlyKwh = _real(j['kwh_mes']),
      monthlyCost = _real(j['custo_mes']),
      monthlySavingsKwh = _real(j['economia_kwh_mes']),
      monthlySavings = _real(j['economia_mes']),
      yearlySavings = _real(j['economia_ano']),
      percentageSavings = _real(j['economia_percentual']);
}

class Suggestions {
  final double currentKwh;
  final double currentCost;
  final String? criterion;
  final String? message;
  final int discardedSuspects;
  final List<SuggestedAppliance> suggestions;

  Suggestions.fromJson(Map<String, dynamic> j)
    : currentKwh = _real(j['atual']['kwh_mes']),
      currentCost = _real(j['atual']['custo_mes']),
      criterion = j['criterio'],
      message = j['mensagem'],
      discardedSuspects = j['suspeitos_descartados'] ?? 0,
      suggestions = [for (final s in j['sugestoes']) SuggestedAppliance.fromJson(s)];
}

class Payback {
  final double newPrice;
  final double? months;
  final double? years;
  final String text;

  Payback.fromJson(Map<String, dynamic> j)
    : newPrice = _real(j['preco_novo']),
      months = _realOrNull(j['meses']),
      years = _realOrNull(j['anos']),
      text = j['texto'];
}

class Comparison {
  final Result current;
  final Result rewritten;
  final double monthlySavingsKwh;
  final double monthlySavings;
  final double yearlySavings;
  final Payback? payback;
  final List<String> notices;

  Comparison.fromJson(Map<String, dynamic> j)
    : current = Result.fromJson(j['atual']),
      rewritten = Result.fromJson(j['novo']),
      monthlySavingsKwh = _real(j['economia_kwh_mes']),
      monthlySavings = _real(j['economia_mes']),
      yearlySavings = _real(j['economia_ano']),
      payback = j['payback'] == null ? null : Payback.fromJson(j['payback']),
      notices = List<String>.from(j['avisos'] ?? const []);
}

/// Perfil da casa pelo K-Means (POST /classificar).
class Classification {
  final String profile;
  final double kwhTotal;
  final double kwhPerResident;
  final double medianKwhPerResident;
  final double percentageDifference;
  final String textComparison;
  final Map<String, double> fractions;
  final String notice;

  Classification.fromJson(Map<String, dynamic> j)
    : profile = j['perfil'],
      kwhTotal = _real(j['kwh_total']),
      kwhPerResident = _real(j['kwh_por_morador']),
      medianKwhPerResident = _real(j['comparacao_media']['mediana_kwh_por_morador']),
      percentageDifference = _real(j['comparacao_media']['diferenca_percentual']),
      textComparison = j['comparacao_media']['texto'],
      fractions = {for (final e in (j['fracoes'] as Map).entries) e.key as String: _real(e.value)},
      notice = j['aviso'];
}

/// Tempo maximo de uma chamada comum. No Render gratis o servidor dorme depois de 15 min parado e leva
/// ate ~1 min para acordar: com 15 s (como era) a primeira chamada depois de um tempo dava erro.
const requestLimit = Duration(seconds: 75);

class Api {
  /// A API responde no idioma do app (avisos, "Como calculamos", plano do Eco-Coach...).
  static Map<String, String> get _language => {
    'Accept-Language': language.value.header,
    if (token != null) 'Authorization': 'Bearer $token',
  };

  /// Token da conta (POST /contas ou /login). So na memoria: fechar o app sai da conta.
  static String? token;

  /// Acorda o servidor assim que o app abre (enquanto a pessoa ainda esta nas boas-vindas).
  /// Nao mostra nada e ignora erro: se falhar, a proxima chamada tenta de novo.
  static Future<void> wakeUp() async {
    try {
      await http.get(Uri.parse('$apiUrl/saude')).timeout(requestLimit);
    } catch (_) {}
  }

  static Future<dynamic> _get(String path, [Map<String, String>? params]) async {
    final uri = Uri.parse('$apiUrl$path').replace(queryParameters: params);
    return _clean(() => http.get(uri, headers: _language));
  }

  static Future<dynamic> _post(
    String path,
    Map<String, dynamic> body, {
    Duration limit = requestLimit,
  }) async {
    final uri = Uri.parse('$apiUrl$path');
    return _clean(
      () => http.post(uri, headers: {'Content-Type': 'application/json', ..._language}, body: jsonEncode(body)),
      limit: limit,
    );
  }

  static Future<dynamic> _put(String path, Map<String, dynamic> body) => _clean(
    () => http.put(
      Uri.parse('$apiUrl$path'),
      headers: {'Content-Type': 'application/json', ..._language},
      body: jsonEncode(body),
    ),
  );

  static Future<dynamic> _patch(String path, Map<String, dynamic> body) => _clean(
    () => http.patch(
      Uri.parse('$apiUrl$path'),
      headers: {'Content-Type': 'application/json', ..._language},
      body: jsonEncode(body),
    ),
  );

  static Future<dynamic> _delete(String path) => _clean(() => http.delete(Uri.parse('$apiUrl$path'), headers: _language));

  static Future<dynamic> _clean(
    Future<http.Response> Function() call, {
    Duration limit = requestLimit,
  }) async {
    final http.Response response;
    try {
      response = await call().timeout(limit);
    } catch (_) {
      throw ApiError(
        tr(
          'Não consegui me conectar ao Iamp. Confira a internet e tente de novo.',
          'Could not connect to Iamp. Check your internet connection and try again.',
        ),
      );
    }
    // erro 500 da API vem em texto puro e o Render responde com uma pagina HTML enquanto acorda:
    // sem isso, a pessoa via "FormatException" (ou nada, nas telas que so tratam ApiError)
    if (response.statusCode == 204) return null; // apagar, sair: resposta sem corpo
    final dynamic body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiError(
        tr(
          'O Iamp está com um problema agora. Tente de novo em instantes.',
          'Iamp is having a problem right now. Try again in a moment.',
        ),
      );
    }
    if (response.statusCode >= 400) {
      final detail = body is Map ? body['detail'] : null;
      if (response.statusCode == 401) {
        throw SessionExpired(detail is String ? detail : tr('Entre na sua conta de novo.', 'Please log in again.'));
      }
      if (detail is String) throw ApiError(detail);
      if (detail is List && detail.isNotEmpty && detail.first is Map) {
        throw ApiError('${detail.first['msg']}');
      }
      throw ApiError(tr('Erro ${response.statusCode} na API', 'API error ${response.statusCode}'));
    }
    return body;
  }

  static Future<List<String>> categories() async => List<String>.from(await _get('/categorias'));

  // Conta e casas na nuvem (conta.dart chama; as telas nao chamam direto) ---------------------

  static Future<Map<String, dynamic>> signUp(String name, String email, String password) async =>
      await _post('/contas', {'nome': name, 'email': email, 'senha': password, 'aceite_privacidade': true});

  static Future<Map<String, dynamic>> logIn(String email, String password) async =>
      await _post('/login', {'email': email, 'senha': password});

  static Future<void> logOut() async => _post('/logout', const {});

  static Future<Map<String, dynamic>> updateAccount({String? name, String? email}) async =>
      await _patch('/conta', {'nome': ?name, 'email': ?email});

  static Future<void> deleteAccount() async => _delete('/conta');

  static Future<List<Map<String, dynamic>>> savedHomes() async =>
      List<Map<String, dynamic>>.from(await _get('/casas'));

  static Future<Map<String, dynamic>> createHome(String name, int residents) async =>
      await _post('/casas', {'nome': name, 'moradores': residents});

  static Future<Map<String, dynamic>> saveHome(int id, Map<String, dynamic> body) async =>
      await _put('/casas/$id', body);

  static Future<void> deleteHome(int id) async => _delete('/casas/$id');

  static Future<List<Appliance>> searchAppliances(String searchText, {String? category}) async {
    // limite por tipo de aparelho: uma marca com varios tipos traz todos
    final itemList = await _get('/aparelhos', {'busca': searchText, 'categoria': ?category, 'limite': '$searchLimitPerType'});
    return [for (final j in itemList) Appliance.fromJson(j)];
  }

  /// Todas as marcas de um tipo de aparelho (lista de marcas da etapa 2).
  static Future<List<Brand>> brands(String category) async {
    final itemList = await _get('/marcas', {'categoria': category});
    return [for (final j in itemList) Brand.fromJson(j)];
  }

  /// Modelos de uma marca dentro de um tipo (abre ao tocar na marca).
  static Future<List<Appliance>> brandModels(String category, String brand) async {
    final itemList = await _get('/modelos', {'categoria': category, 'marca': brand, 'limite': '$brandModelLimit'});
    return [for (final j in itemList) Appliance.fromJson(j)];
  }

  static Future<UsageQuestion> usageQuestion(int applianceId) async =>
      UsageQuestion.fromJson(await _get('/aparelhos/$applianceId/uso'));

  static Future<List<String>> ufs() async => List<String>.from(await _get('/ufs'));

  static Future<List<Distributor>> distributors({String? uf}) async {
    final itemList = await _get('/distribuidoras', {'uf': ?uf});
    return [for (final j in itemList) Distributor.fromJson(j)];
  }

  /// usageAndTariff: distribuidora_id ou tarifa_manual, mais horas_dia, ciclos_mes ou velocidade.
  static Future<Result> calculate(int applianceId, Map<String, dynamic> usageAndTariff) async =>
      Result.fromJson(await _post('/calcular', {'aparelho_id': applianceId, ...usageAndTariff}));

  static Future<Result> estimate(String route, Map<String, dynamic> body) async =>
      Result.fromJson(await _post(route, body));

  static Future<List<Resistive>> resistive() async => [
    for (final j in await _get('/resistivos')) Resistive.fromJson(j),
  ];

  static Future<Tips> tips(Result r) async => Tips.fromJson(
    await _post('/eco-coach/aparelho', {
      'categoria': r.category,
      'nome': r.name,
      'kwh_mes': r.monthlyKwh,
      'custo_mes': r.monthlyCost,
      'metodo': r.method,
    }, limit: requestLimit),
  );

  static Future<List<EstimableCategory>> estimableCategories() async => [
    for (final j in await _get('/estimativa/categorias')) EstimableCategory.fromJson(j),
  ];

  static Map<String, dynamic> _currentEstimated(Result current) => {
    'categoria': current.category,
    'capacidade': current.capacity,
    'tipo': current.kind,
    'kwh_mes': current.monthlyKwh,
    'nome': current.name,
    'pelos_parecidos': current.bySimilar,
  };

  static Future<Suggestions> estimatedSuggestions(Result current, Map<String, dynamic> usageAndTariff) async =>
      Suggestions.fromJson(await _post('/sugestoes/estimado', {..._currentEstimated(current), ...usageAndTariff}));

  static Future<Comparison> compareEstimated(
    Result current,
    int alternativeId,
    Map<String, dynamic> usageAndTariff, {
    double? newPrice,
  }) async => Comparison.fromJson(
    await _post('/comparar/estimado', {
      ..._currentEstimated(current)
        ..remove('capacidade')
        ..remove('tipo')
        ..remove('pelos_parecidos'),
      'alternativa_id': alternativeId,
      'preco_novo': newPrice,
      ...usageAndTariff,
    }),
  );

  static Future<Suggestions> suggestions(int applianceId, Map<String, dynamic> usageAndTariff) async =>
      Suggestions.fromJson(await _post('/sugestoes', {'aparelho_id': applianceId, ...usageAndTariff}));

  static Future<Comparison> compare(
    int applianceId,
    int alternativeId,
    Map<String, dynamic> usageAndTariff, {
    double? newPrice,
  }) async => Comparison.fromJson(
    await _post('/comparar', {
      'aparelho_id': applianceId,
      'alternativa_id': alternativeId,
      'preco_novo': newPrice,
      ...usageAndTariff,
    }),
  );

  /// itens: [{categoria, kwh_mes}] da casa.
  static Future<Classification> classify(int residents, List<Map<String, dynamic>> items) async =>
      Classification.fromJson(await _post('/classificar', {'moradores': residents, 'itens': items}));

  /// Plano do Eco-Coach (RAG + Gemini). O LLM pode levar alguns segundos: limite maior.
  static Future<EcoCoach> ecoCoach(int residents, List<Map<String, dynamic>> items, List<EvaluatedSwap> swaps) async =>
      EcoCoach.fromJson(
        await _post('/eco-coach', {
          'moradores': residents,
          'itens': items,
          'trocas': [for (final t in swaps) t.toApi()],
        }, limit: const Duration(seconds: 120)), // servidor acordando + Gemini escrevendo
      );
}

/// Troca ja calculada em "Vale a pena trocar?" (vai para o Eco-Coach usar os numeros do Iamp).
class EvaluatedSwap {
  final String appliance;
  final String alternative;
  final double monthlySavings;
  final double? paybackMonths;

  /// Resultado do aparelho atual (o mesmo objeto que vai para "Minha casa"). A troca so vale para o
  /// Eco-Coach enquanto esse aparelho estiver na casa. null = vale sempre. Nao vai para a API.
  final Result? current;

  const EvaluatedSwap({
    required this.appliance,
    required this.alternative,
    required this.monthlySavings,
    this.paybackMonths,
    this.current,
  });

  Map<String, dynamic> toApi() => {
    'aparelho': appliance,
    'alternativa': alternative,
    'economia_mes': monthlySavings,
    'payback_meses': paybackMonths,
  };
}

class CitedSource {
  final int n;
  final String document;
  final String agency;
  final String url;
  final String? section;
  final int? page;

  CitedSource.fromJson(Map<String, dynamic> j)
    : n = j['n'],
      document = j['documento'],
      agency = j['orgao'],
      url = j['url'],
      section = j['secao'],
      page = j['pagina'];
}

class LargestConsumption {
  final String category;
  final String name;
  final double monthlyKwh;
  final double? monthlyCost;
  final double percentage;

  LargestConsumption.fromJson(Map<String, dynamic> j)
    : category = j['categoria'],
      name = j['nome'],
      monthlyKwh = _real(j['kwh_mes']),
      monthlyCost = _realOrNull(j['custo_mes']),
      percentage = _real(j['percentual']);
}

/// Resposta de POST /eco-coach: numeros calculados pelo Iamp + plano escrito pelo LLM com fontes [n].
class EcoCoach {
  final String profile;
  final double kwhTotal;
  final double? totalCost;
  final List<LargestConsumption> largestConsumptions;
  final String plan; // markdown
  final List<CitedSource> sources;
  final String model;
  final String notice;

  EcoCoach.fromJson(Map<String, dynamic> j)
    : profile = j['perfil'],
      kwhTotal = _real(j['kwh_total']),
      totalCost = _realOrNull(j['custo_total']),
      largestConsumptions = [for (final m in j['maiores_consumos']) LargestConsumption.fromJson(m)],
      plan = j['plano'],
      sources = [for (final f in j['fontes']) CitedSource.fromJson(f)],
      model = j['modelo'],
      notice = j['aviso'];
}

/// 1234.5 -> "R$ 1.234,50" (em ingles, "R$ 1,234.50": o valor continua em reais)
String reais(double value, {int homes = 2}) {
  final (thousands, decimal) = inEnglish ? (',', '.') : ('.', ',');
  final negative = value < 0;
  final parts = value.abs().toStringAsFixed(homes).split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => thousands);
  return '${negative ? '-' : ''}R\$ $whole${homes > 0 ? '$decimal${parts[1]}' : ''}';
}

String duration(double hours) {
  final total = (hours * 60).round();
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// 41.25 -> "41,25" (em ingles, "41.25")
String number(double value, {int homes = 2}) {
  final text = value.toStringAsFixed(homes);
  return inEnglish ? text : text.replaceAll('.', ',');
}

/// Aceita "0,25", "0.25", "1.299,90" e "R$ 1.299,90".
/// Em ingles a virgula separa os milhares ("1,299.90"); quem digita do jeito brasileiro ("0,85" ou
/// "2.499,90") continua certo: o separador que vem por ultimo e o decimal.
double? readNumber(String text) {
  var t = text.trim().replaceAll('R\$', '').replaceAll(' ', '');
  final decimalComma = inEnglish
      ? t.lastIndexOf(',') > t.lastIndexOf('.') && !RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(t)
      : t.contains(',');
  t = decimalComma ? t.replaceAll('.', '').replaceAll(',', '.') : t.replaceAll(',', '');
  return double.tryParse(t);
}
