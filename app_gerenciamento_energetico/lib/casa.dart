// Estado do app: o que o usuario esta calculando agora (Consulta) e as casas da pessoa (Minha casa).
// Sem conta, as casas ficam so na memoria (somem ao fechar o app). Com conta, conta.dart grava cada
// mudanca na nuvem (PUT /casas/{id}); por isso a casa e os itens sabem virar JSON e voltar.

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

  TariffChoice.fromJson(Map<String, dynamic> j)
    : distributorId = j['distribuidora_id'],
      manualTariff = (j['tarifa_manual'] as num?)?.toDouble(),
      _distributor = j['distribuidora'],
      tariffKwh = (j['tarifa_kwh'] as num).toDouble();

  Map<String, dynamic> toJson() => {
    'distribuidora_id': distributorId,
    'tarifa_manual': manualTariff,
    'distribuidora': _distributor,
    'tarifa_kwh': tariffKwh,
  };

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

  Estimate.fromJson(Map<String, dynamic> j) : route = j['rota'], data = Map<String, dynamic>.from(j['dados']);

  Map<String, dynamic> toJson() => {'rota': route, 'dados': data};
}

/// O que o usuario ja escolheu ao longo das telas.
class Query {
  final Appliance appliance;
  final Estimate? estimation;
  double? dailyHours;
  double? monthlyCycles;
  String? speed;
  double? daysPerMonth; // dias de uso no mes (ar-condicionado); null = todos os dias (30)
  TariffChoice? tariff;

  Query(
    this.appliance, {
    this.estimation,
    this.dailyHours,
    this.monthlyCycles,
    this.speed,
    this.daysPerMonth,
    this.tariff,
  });

  Query.fromJson(Map<String, dynamic> j)
    : appliance = Appliance.fromJson(j['aparelho']),
      estimation = j['estimativa'] == null ? null : Estimate.fromJson(j['estimativa']),
      dailyHours = (j['horas_dia'] as num?)?.toDouble(),
      monthlyCycles = (j['ciclos_mes'] as num?)?.toDouble(),
      speed = j['velocidade'],
      daysPerMonth = (j['dias_mes'] as num?)?.toDouble(),
      tariff = j['tarifa'] == null ? null : TariffChoice.fromJson(j['tarifa']);

  Map<String, dynamic> toJson() => {
    'aparelho': appliance.toJson(),
    'estimativa': estimation?.toJson(),
    'horas_dia': dailyHours,
    'ciclos_mes': monthlyCycles,
    'velocidade': speed,
    'dias_mes': daysPerMonth,
    'tarifa': tariff?.toJson(),
  };

  bool get estimated => estimation != null;
  bool get smallAppliance => estimation?.route == resistiveRoute;

  /// Mesmo uso e mesma tarifa, opcionalmente com outro aparelho (troca por um mais economico).
  Query copy({Appliance? appliance}) => Query(
    appliance ?? this.appliance,
    estimation: appliance == null ? estimation : null,
    dailyHours: dailyHours,
    monthlyCycles: monthlyCycles,
    speed: speed,
    daysPerMonth: daysPerMonth,
    tariff: tariff,
  );

  Map<String, dynamic> estimateBody() => {...toApi(), ...estimation!.data};

  /// Corpo comum de /calcular, /sugestoes e /comparar.
  Map<String, dynamic> toApi() => {
    ...?tariff?.toApi(),
    'horas_dia': dailyHours,
    'ciclos_mes': monthlyCycles,
    'velocidade': speed,
    'dias_mes': daysPerMonth,
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

/// Limites do servidor (contas.MAX_HOMES e MAX_ITEMS): o app nao deixa passar, senao a casa nunca seria salva.
const maxHomes = 10;
const maxItemsPerHome = 100;

class Home extends ChangeNotifier {
  final List<ItemHome> _items = [];
  int _nextId = 1;
  int residents = 2;

  /// Nome que a pessoa deu ("Casa", "Apartamento da praia").
  String name;

  /// Id da casa na nuvem (null = ainda nao foi gravada, ou a pessoa nao entrou na conta).
  int? cloudId;

  /// Sobe a cada mudanca que precisa ir para a nuvem (perfil e plano nao contam: a API nao guarda).
  int version = 0;

  Home({String? name}) : name = name ?? tr('Minha casa', 'My home');

  /// Casa que veio de GET /casas. Item que nao da para ler (formato antigo) fica de fora.
  Home.fromCloud(Map<String, dynamic> j) : name = j['nome'], cloudId = j['id'], residents = j['moradores'] {
    final tariff = j['ultima_tarifa'];
    if (tariff is Map<String, dynamic>) lastTariff = TariffChoice.fromJson(tariff);
    for (final i in j['itens'] as List) {
      try {
        final data = i['dados'] as Map<String, dynamic>;
        _items.add(
          ItemHome(
            _nextId++,
            Query.fromJson(data['consulta']),
            Result.fromJson(data['resultado']),
            quantity: i['quantidade'],
          ),
        );
      } catch (_) {}
    }
  }

  /// Corpo de PUT /casas/{id}: a casa inteira (kWh e R$ de 1 unidade, como o app guarda).
  Map<String, dynamic> toCloud() => {
    'nome': name,
    'moradores': residents,
    'ultima_tarifa': lastTariff?.toJson(),
    'itens': [
      for (final i in _items)
        {
          'quantidade': i.quantity,
          'categoria': i.result.category,
          'kwh_mes': i.result.monthlyKwh,
          'custo_mes': i.result.monthlyCost,
          'dados': {'consulta': i.query.toJson(), 'resultado': i.result.json},
        },
    ],
  };

  void rename(String newName) {
    name = newName.trim();
    version++;
    notifyListeners();
  }

  /// Ultima tarifa usada: a tela da distribuidora oferece usar de novo.
  TariffChoice? lastTariff;

  /// Perfil do K-Means. Volta a null quando a casa muda (precisa classificar de novo).
  Classification? profile;

  /// Ultimo plano do Eco-Coach (aba Economizar). Fica guardado ate a casa mudar (poupa o limite gratuito do Gemini).
  EcoCoach? plan;

  /// Trocas com payback calculado em "Vale a pena trocar?" (no maximo 5, as mais recentes).
  final List<EvaluatedSwap> _swaps = [];

  /// So as trocas de aparelhos que ainda estao na casa: removido ou ja trocado, o Eco-Coach nao recomenda
  /// de novo. "Desfazer" a remocao traz o mesmo item (o mesmo resultado), entao a troca volta junto.
  List<EvaluatedSwap> get swaps =>
      List.unmodifiable(_swaps.where((s) => s.current == null || _items.any((i) => identical(i.result, s.current))));

  List<ItemHome> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  /// Chegou ao limite de aparelhos (maxItemsPerHome): as telas avisam em vez de adicionar.
  bool get full => _items.length >= maxItemsPerHome;
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
    version++;
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
    version++;
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

/// As casas da pessoa (uma ou mais) e qual esta aberta. Sempre tem pelo menos uma.
/// Repassa os avisos de mudanca de todas as casas: as telas escutam `homes` e redesenham tanto quando
/// a casa aberta muda quanto quando a pessoa troca de casa.
class Homes extends ChangeNotifier {
  final List<Home> _list = [];
  late Home _active;

  Homes() {
    _active = _attach(Home());
    _list.add(_active);
  }

  List<Home> get list => List.unmodifiable(_list);
  Home get active => _active;

  Home _attach(Home h) {
    h.addListener(notifyListeners);
    return h;
  }

  /// Cria uma casa vazia e ja abre ela.
  Home add(String name) {
    final h = _attach(Home(name: name.trim()));
    _list.add(h);
    _active = h;
    notifyListeners();
    return h;
  }

  void select(Home h) {
    if (!_list.contains(h) || identical(h, _active)) return;
    _active = h;
    notifyListeners();
  }

  /// Tira a casa da lista (a ultima nao sai). Se era a aberta, abre a primeira.
  void remove(Home h) {
    if (_list.length == 1 || !_list.contains(h)) return;
    _list.remove(h);
    h.removeListener(notifyListeners);
    if (identical(h, _active)) _active = _list.first;
    notifyListeners();
  }

  /// Troca todas as casas (ao entrar na conta). `open` = a que fica aberta.
  void replaceAll(List<Home> newHomes, {Home? open}) {
    if (newHomes.isEmpty) return reset();
    for (final h in _list) {
      h.removeListener(notifyListeners);
    }
    _list
      ..clear()
      ..addAll(newHomes.map(_attach));
    _active = open != null && newHomes.contains(open) ? open : newHomes.first;
    notifyListeners();
  }

  /// Volta para uma casa vazia so no aparelho (ao sair da conta; os testes tambem usam).
  void reset() => replaceAll([Home()]);
}

final homes = Homes();

/// Casa aberta agora: as telas usam `home` como antes (calcular, Minha casa, Economizar).
Home get home => homes.active;
