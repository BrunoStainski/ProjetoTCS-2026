// Estado do app: o que o usuario esta calculando agora (Consulta) e a lista "Minha casa".
// Fica so na memoria: ao fechar o app, a lista recomeca vazia.

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'idioma.dart';

/// Tarifa escolhida: distribuidora da ANEEL ou o valor da conta de luz.
class EscolhaTarifa {
  final int? distribuidoraId;
  final double? tarifaManual;
  final String? _distribuidora;
  final double tarifaKwh;

  EscolhaTarifa.daDistribuidora(Distribuidora d)
    : distribuidoraId = d.id,
      tarifaManual = null,
      _distribuidora = d.uf == null ? d.nome : '${d.nome} - ${d.uf}',
      tarifaKwh = d.tarifaKwh;

  EscolhaTarifa.manual(double tarifa)
    : distribuidoraId = null,
      tarifaManual = tarifa,
      _distribuidora = null,
      tarifaKwh = tarifa;

  /// Calculada na hora: segue o idioma, mesmo se a tarifa foi escolhida antes da troca.
  String get descricao => _distribuidora ?? tr('Tarifa da conta de luz', 'Rate from your electricity bill');

  Map<String, dynamic> paraApi() => {'distribuidora_id': distribuidoraId, 'tarifa_manual': tarifaManual};
}

const rotaGeladeira = '/calcular/refrigerador-antigo';
const rotaEstimado = '/calcular/estimado';
const rotaResistivo = '/calcular/resistivo';

class Estimativa {
  final String rota;
  final Map<String, dynamic> dados;

  const Estimativa(this.rota, this.dados);
}

/// O que o usuario ja escolheu ao longo das telas.
class Consulta {
  final Aparelho aparelho;
  final Estimativa? estimativa;
  double? horasDia;
  double? ciclosMes;
  String? velocidade;
  EscolhaTarifa? tarifa;

  Consulta(this.aparelho, {this.estimativa, this.horasDia, this.ciclosMes, this.velocidade, this.tarifa});

  bool get estimado => estimativa != null;
  bool get portatil => estimativa?.rota == rotaResistivo;

  /// Mesmo uso e mesma tarifa, opcionalmente com outro aparelho (troca por um mais economico).
  Consulta copiar({Aparelho? aparelho}) => Consulta(
    aparelho ?? this.aparelho,
    estimativa: aparelho == null ? estimativa : null,
    horasDia: horasDia,
    ciclosMes: ciclosMes,
    velocidade: velocidade,
    tarifa: tarifa,
  );

  Map<String, dynamic> corpoDaEstimativa() => {...paraApi(), ...estimativa!.dados};

  /// Corpo comum de /calcular, /sugestoes e /comparar.
  Map<String, dynamic> paraApi() => {
    ...?tarifa?.paraApi(),
    'horas_dia': horasDia,
    'ciclos_mes': ciclosMes,
    'velocidade': velocidade,
  };
}

class ItemCasa {
  final int id;
  final Consulta consulta;
  final Resultado resultado;
  int quantidade;

  ItemCasa(this.id, this.consulta, this.resultado, {this.quantidade = 1});

  double get kwhMes => resultado.kwhMes * quantidade;
  double get custoMes => resultado.custoMes * quantidade;
  double get custoAno => resultado.custoAno * quantidade;
}

class Casa extends ChangeNotifier {
  final List<ItemCasa> _itens = [];
  int _proximoId = 1;
  int moradores = 2;

  /// Ultima tarifa usada: a tela da distribuidora oferece usar de novo.
  EscolhaTarifa? ultimaTarifa;

  /// Perfil do K-Means. Volta a null quando a casa muda (precisa classificar de novo).
  Classificacao? perfil;

  /// Ultimo plano do Eco-Coach (aba Economizar). Fica guardado ate a casa mudar (poupa o limite gratuito do Gemini).
  EcoCoach? plano;

  /// Trocas com payback calculado em "Vale a pena trocar?" (no maximo 5, as mais recentes).
  final List<TrocaAvaliada> _trocas = [];
  List<TrocaAvaliada> get trocas => List.unmodifiable(_trocas);

  List<ItemCasa> get itens => List.unmodifiable(_itens);
  bool get vazia => _itens.isEmpty;
  int get totalAparelhos => _itens.fold(0, (soma, i) => soma + i.quantidade);
  double get kwhMes => _itens.fold(0.0, (soma, i) => soma + i.kwhMes);
  double get custoMes => _itens.fold(0.0, (soma, i) => soma + i.custoMes);
  double get custoAno => _itens.fold(0.0, (soma, i) => soma + i.custoAno);

  /// Do que mais pesa na conta para o que menos pesa.
  List<ItemCasa> get porCusto => [..._itens]..sort((a, b) => b.custoMes.compareTo(a.custoMes));

  /// A casa usa mais de uma tarifa? (o total soma valores com tarifas diferentes)
  bool get tarifasMisturadas => _itens.map((i) => i.resultado.tarifaKwh).toSet().length > 1;

  void _mudou() {
    perfil = null;
    plano = null;
    notifyListeners();
  }

  ItemCasa adicionar(Consulta consulta, Resultado resultado) {
    final item = ItemCasa(_proximoId++, consulta.copiar(), resultado);
    _itens.add(item);
    _mudou();
    return item;
  }

  /// Tira o item da casa e devolve a posicao dele (para o "Desfazer").
  int remover(ItemCasa item) {
    final posicao = _itens.indexOf(item);
    _itens.remove(item);
    _mudou();
    return posicao;
  }

  /// Desfaz uma remocao: o item volta para a mesma posicao.
  void reinserir(ItemCasa item, int posicao) {
    if (_itens.contains(item)) return;
    _itens.insert(posicao.clamp(0, _itens.length), item);
    _mudou();
  }

  void mudarQuantidade(ItemCasa item, int quantidade) {
    item.quantidade = quantidade.clamp(1, 99);
    _mudou();
  }

  /// Troca o aparelho de um item por um modelo mais economico, mantendo a quantidade.
  void trocar(ItemCasa antigo, Consulta nova, Resultado resultado) {
    final i = _itens.indexOf(antigo);
    if (i < 0) return;
    _itens[i] = ItemCasa(_proximoId++, nova.copiar(), resultado, quantidade: antigo.quantidade);
    _mudou();
  }

  void mudarMoradores(int n) {
    moradores = n.clamp(1, 20);
    _mudou();
  }

  void lembrarTarifa(EscolhaTarifa tarifa) {
    ultimaTarifa = tarifa;
    notifyListeners();
  }

  void guardarPerfil(Classificacao c) {
    perfil = c;
    notifyListeners();
  }

  void guardarPlano(EcoCoach p) {
    plano = p;
    notifyListeners();
  }

  /// Trocou o idioma: o perfil e o plano vieram da API no idioma anterior e precisam ser pedidos de novo.
  void esquecerTextosDaApi() {
    perfil = null;
    plano = null;
    notifyListeners();
  }

  /// Guarda a troca avaliada (a mesma dupla de aparelhos so aparece uma vez, com o valor mais novo).
  void registrarTroca(TrocaAvaliada t) {
    _trocas.removeWhere((x) => x.aparelho == t.aparelho && x.alternativa == t.alternativa);
    _trocas.add(t);
    if (_trocas.length > 5) _trocas.removeAt(0);
    plano = null; // o plano precisa considerar a troca nova; o perfil nao muda
    notifyListeners();
  }

  /// Formato de POST /classificar.
  List<Map<String, dynamic>> itensParaPerfil() => [
    for (final i in _itens) {'categoria': i.resultado.categoria, 'kwh_mes': i.kwhMes},
  ];

  /// Formato de POST /eco-coach: igual ao do perfil, com o custo de cada item.
  List<Map<String, dynamic>> itensParaEcoCoach() => [
    for (final i in _itens) {'categoria': i.resultado.categoria, 'kwh_mes': i.kwhMes, 'custo_mes': i.custoMes},
  ];

  @visibleForTesting
  void limpar() {
    _itens.clear();
    _trocas.clear();
    moradores = 2;
    ultimaTarifa = null;
    perfil = null;
    plano = null;
    notifyListeners();
  }
}

/// Unica casa do app (sem login, sem banco no celular).
final casa = Casa();
