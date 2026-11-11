// Estado do app: o que o usuario esta calculando agora (Consulta) e a lista "Minha casa".
// Fica so na memoria: ao fechar o app, a lista recomeca vazia.

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'idioma.dart';

/// Tarifa escolhida: distribuidora da ANEEL ou o valor da conta de luz.
class TariffChoice {
  final int? distributorId;
  final double? manualTariff;
  final String? _distributor;
  final double tariffKwh;

  TariffChoice.fromDistributor(Distributor d)
    : distributorId = d.id,
      manualTariff = null,
      _distributor = d.uf == null ? d.name : '${d.name} - ${d.uf}',
      tariffKwh = d.tariffKwh;

  TariffChoice.manual(double tariff)
    : distributorId = null,
      manualTariff = tariff,
      _distributor = null,
      tariffKwh = tariff;

  /// Calculada na hora: segue o idioma, mesmo se a tarifa foi escolhida antes da troca.
  String get description => _distributor ?? tr('Tarifa da conta de luz', 'Rate from your electricity bill');

  Map<String, dynamic> toApi() => {'distribuidora_id': distributorId, 'tarifa_manual': manualTariff};
}

const fridgeRoute = '/calcular/refrigerador-antigo';
const estimatedRoute = '/calcular/estimado';
const resistiveRoute = '/calcular/resistivo';

class Estimate {
  final String route;
  final Map<String, dynamic> data;

  const Estimate(this.route, this.data);
}

/// O que o usuario ja escolheu ao longo das telas.
class Query {
  final Appliance appliance;
  final Estimate? estimation;
  double? dailyHours;
  double? monthlyCycles;
  String? speed;
  TariffChoice? tariff;

  Query(this.appliance, {this.estimation, this.dailyHours, this.monthlyCycles, this.speed, this.tariff});

  bool get estimated => estimation != null;
  bool get smallAppliance => estimation?.route == resistiveRoute;

  /// Mesmo uso e mesma tarifa, opcionalmente com outro aparelho (troca por um mais economico).
  Query copy({Appliance? appliance}) => Query(
    appliance ?? this.appliance,
    estimation: appliance == null ? estimation : null,
    dailyHours: dailyHours,
    monthlyCycles: monthlyCycles,
    speed: speed,
    tariff: tariff,
  );

  Map<String, dynamic> estimateBody() => {...toApi(), ...estimation!.data};

  /// Corpo comum de /calcular, /sugestoes e /comparar.
  Map<String, dynamic> toApi() => {
    ...?tariff?.toApi(),
    'horas_dia': dailyHours,
    'ciclos_mes': monthlyCycles,
    'velocidade': speed,
  };
}

class ItemHome {
  final int id;
  final Query query;
  final Result result;
  int quantity;

  ItemHome(this.id, this.query, this.result, {this.quantity = 1});

  double get monthlyKwh => result.monthlyKwh * quantity;
  double get monthlyCost => result.monthlyCost * quantity;
  double get yearlyCost => result.yearlyCost * quantity;
}

class Home extends ChangeNotifier {
  final List<ItemHome> _items = [];
  int _nextId = 1;
  int residents = 2;

  /// Ultima tarifa usada: a tela da distribuidora oferece usar de novo.
  TariffChoice? lastTariff;

  /// Perfil do K-Means. Volta a null quando a casa muda (precisa classificar de novo).
  Classification? profile;

  /// Ultimo plano do Eco-Coach (aba Economizar). Fica guardado ate a casa mudar (poupa o limite gratuito do Gemini).
  EcoCoach? plan;

  /// Trocas com payback calculado em "Vale a pena trocar?" (no maximo 5, as mais recentes).
  final List<EvaluatedSwap> _swaps = [];
  List<EvaluatedSwap> get swaps => List.unmodifiable(_swaps);

  List<ItemHome> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  int get totalAppliances => _items.fold(0, (summed, i) => summed + i.quantity);
  double get monthlyKwh => _items.fold(0.0, (summed, i) => summed + i.monthlyKwh);
  double get monthlyCost => _items.fold(0.0, (summed, i) => summed + i.monthlyCost);
  double get yearlyCost => _items.fold(0.0, (summed, i) => summed + i.yearlyCost);

  /// Do que mais pesa na conta para o que menos pesa.
  List<ItemHome> get byCost => [..._items]..sort((a, b) => b.monthlyCost.compareTo(a.monthlyCost));

  /// A casa usa mais de uma tarifa? (o total soma valores com tarifas diferentes)
  bool get mixedTariffs => _items.map((i) => i.result.tariffKwh).toSet().length > 1;

  void _changed() {
    profile = null;
    plan = null;
    notifyListeners();
  }

  ItemHome add(Query query, Result result) {
    final item = ItemHome(_nextId++, query.copy(), result);
    _items.add(item);
    _changed();
    return item;
  }

  /// Tira o item da casa e devolve a posicao dele (para o "Desfazer").
  int remove(ItemHome item) {
    final position = _items.indexOf(item);
    _items.remove(item);
    _changed();
    return position;
  }

  /// Desfaz uma remocao: o item volta para a mesma posicao.
  void reinsert(ItemHome item, int position) {
    if (_items.contains(item)) return;
    _items.insert(position.clamp(0, _items.length), item);
    _changed();
  }

  void changeQuantity(ItemHome item, int quantity) {
    item.quantity = quantity.clamp(1, 99);
    _changed();
  }

  /// Troca o aparelho de um item por um modelo mais economico, mantendo a quantidade.
  void replace(ItemHome old, Query newQuery, Result result) {
    final i = _items.indexOf(old);
    if (i < 0) return;
    _items[i] = ItemHome(_nextId++, newQuery.copy(), result, quantity: old.quantity);
    _changed();
  }

  void changeResidents(int n) {
    residents = n.clamp(1, 20);
    _changed();
  }

  void rememberTariff(TariffChoice tariff) {
    lastTariff = tariff;
    notifyListeners();
  }

  void storeProfile(Classification c) {
    profile = c;
    notifyListeners();
  }

  void storePlan(EcoCoach p) {
    plan = p;
    notifyListeners();
  }

  /// Trocou o idioma: o perfil e o plano vieram da API no idioma anterior e precisam ser pedidos de novo.
  void forgetApiTexts() {
    profile = null;
    plan = null;
    notifyListeners();
  }

  /// Guarda a troca avaliada (a mesma dupla de aparelhos so aparece uma vez, com o valor mais novo).
  void registerSwap(EvaluatedSwap t) {
    _swaps.removeWhere((x) => x.appliance == t.appliance && x.alternative == t.alternative);
    _swaps.add(t);
    if (_swaps.length > 5) _swaps.removeAt(0);
    plan = null; // o plano precisa considerar a troca nova; o perfil nao muda
    notifyListeners();
  }

  /// Formato de POST /classificar.
  List<Map<String, dynamic>> itemsForProfile() => [
    for (final i in _items) {'categoria': i.result.category, 'kwh_mes': i.monthlyKwh},
  ];

  /// Formato de POST /eco-coach: igual ao do perfil, com o custo de cada item.
  List<Map<String, dynamic>> itemsForEcoCoach() => [
    for (final i in _items) {'categoria': i.result.category, 'kwh_mes': i.monthlyKwh, 'custo_mes': i.monthlyCost},
  ];

  @visibleForTesting
  void clear() {
    _items.clear();
    _swaps.clear();
    residents = 2;
    lastTariff = null;
    profile = null;
    plan = null;
    notifyListeners();
  }
}

/// Unica casa do app (sem login, sem banco no celular).
final home = Home();
