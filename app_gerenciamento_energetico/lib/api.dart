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

class Aparelho {
  final int id;
  final String categoria;
  final String marca;
  final String modelo;
  final String detalhe;

  Aparelho.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        categoria = j['categoria'],
        marca = j['marca'],
        modelo = j['modelo'],
        detalhe = j['detalhe'] ?? '';

  String get nome => '$marca $modelo';
  String get categoriaLegivel => categoria.replaceAll('_', ' ');
}

/// O que o app precisa perguntar antes de calcular.
/// pergunta: null (nada), "horas", "ciclos" ou "velocidade".
class PerguntaDeUso {
  final String? pergunta;
  final List<String> opcoes;
  final dynamic padrao;

  PerguntaDeUso.fromJson(Map<String, dynamic> j)
      : pergunta = j['pergunta'],
        opcoes = List<String>.from(j['opcoes'] ?? const []),
        padrao = j['padrao'];
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
        tarifaKwh = (j['tarifa_kwh'] as num).toDouble();
}

class Resultado {
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

  Resultado.fromJson(Map<String, dynamic> j)
      : marca = j['marca'],
        modelo = j['modelo'],
        detalhe = j['detalhe'] ?? '',
        distribuidora = j['distribuidora'],
        uf = j['uf'],
        kwhMes = (j['kwh_mes'] as num).toDouble(),
        metodo = j['metodo'],
        tarifaKwh = (j['tarifa_kwh'] as num).toDouble(),
        origemTarifa = j['origem_tarifa'],
        custoMes = (j['custo_mes'] as num).toDouble(),
        custoAno = (j['custo_ano'] as num).toDouble(),
        avisos = List<String>.from(j['avisos'] ?? const []);
}

class Api {
  static Future<dynamic> _get(String caminho, [Map<String, String>? params]) async {
    final uri = Uri.parse('$apiUrl$caminho').replace(queryParameters: params);
    return _tratar(() => http.get(uri));
  }

  static Future<dynamic> _post(String caminho, Map<String, dynamic> corpo) async {
    final uri = Uri.parse('$apiUrl$caminho');
    return _tratar(() => http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(corpo),
        ));
  }

  static Future<dynamic> _tratar(Future<http.Response> Function() chamada) async {
    final http.Response resposta;
    try {
      resposta = await chamada().timeout(const Duration(seconds: 15));
    } catch (_) {
      throw ApiErro('Nao consegui falar com a API em $apiUrl. Ela esta rodando? (docker compose up -d)');
    }
    final corpo = jsonDecode(utf8.decode(resposta.bodyBytes));
    if (resposta.statusCode >= 400) {
      final detalhe = corpo is Map ? corpo['detail'] : null;
      throw ApiErro(detalhe is String ? detalhe : 'Erro ${resposta.statusCode} na API');
    }
    return corpo;
  }

  static Future<List<String>> categorias() async =>
      List<String>.from(await _get('/categorias'));

  static Future<List<Aparelho>> buscarAparelhos(String busca, {String? categoria}) async {
    final lista = await _get('/aparelhos', {
      'busca': busca,
      if (categoria != null) 'categoria': categoria,
      'limite': '30',
    });
    return [for (final j in lista) Aparelho.fromJson(j)];
  }

  static Future<PerguntaDeUso> perguntaDeUso(int aparelhoId) async =>
      PerguntaDeUso.fromJson(await _get('/aparelhos/$aparelhoId/uso'));

  static Future<List<String>> ufs() async => List<String>.from(await _get('/ufs'));

  static Future<List<Distribuidora>> distribuidoras({String? uf}) async {
    final lista = await _get('/distribuidoras', {if (uf != null) 'uf': uf});
    return [for (final j in lista) Distribuidora.fromJson(j)];
  }

  static Future<Resultado> calcular({
    required int aparelhoId,
    int? distribuidoraId,
    double? tarifaManual,
    double? horasDia,
    double? ciclosMes,
    String? velocidade,
  }) async {
    final corpo = await _post('/calcular', {
      'aparelho_id': aparelhoId,
      'distribuidora_id': distribuidoraId,
      'tarifa_manual': tarifaManual,
      'horas_dia': horasDia,
      'ciclos_mes': ciclosMes,
      'velocidade': velocidade,
    });
    return Resultado.fromJson(corpo);
  }
}

/// 1234.5 -> "R$ 1.234,50"
String reais(double valor, {int casas = 2}) {
  final partes = valor.toStringAsFixed(casas).split('.');
  final inteiro = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return 'R\$ $inteiro${casas > 0 ? ',${partes[1]}' : ''}';
}

/// 41.25 -> "41,25"
String numero(double valor, {int casas = 2}) => valor.toStringAsFixed(casas).replaceAll('.', ',');

/// Aceita "0,25" ou "0.25"
double? lerNumero(String texto) => double.tryParse(texto.trim().replaceAll(',', '.'));
