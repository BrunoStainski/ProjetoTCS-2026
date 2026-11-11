// Comeco do calculo, uma decisao por tela:
// etapa 1 (SearchScreen): qual tipo de aparelho; etapa 2 (ModelScreen): marca e modelo.

import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../idioma.dart';
import '../navegacao.dart';
import '../tema.dart';
import 'comum.dart';
import 'estimar.dart';
import 'uso.dart';

/// Etapa 1: a pessoa escolhe o tipo de aparelho em botoes grandes.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late Future<List<String>> _categories;

  @override
  void initState() {
    super.initState();
    _categories = Api.categories();
  }

  void _openModel(String? category) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ModelScreen(category: category)));
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Iamp',
      widgetTitle: const LogoIamp(),
      step: const FlowStep(1, totalSteps),
      child: ListView(
        children: [
          QuestionHeader(
            tr('Qual aparelho você quer calcular?', 'Which appliance do you want to calculate?'),
            help: tr(
              'Mostramos quanto ele pesa na sua conta de luz, com dados oficiais do Inmetro e da ANEEL.',
              'We show how much it adds to your electricity bill, using official data from Inmetro and ANEEL '
                  '(Brazilian energy regulators).',
            ),
          ),
          const _HomeSummary(),
          FutureBuilder<List<String>>(
            future: _categories,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Loading(text: tr('Carregando os aparelhos...', 'Loading appliances...'));
              }
              if (snap.hasError) {
                return ErrorMessage(
                  snap.error.toString(),
                  tryAgain: () => setState(() {
                    _categories = Api.categories();
                  }),
                );
              }
              return TypeGrid(snap.data!, onChoose: _openModel);
            },
          ),
          const SizedBox(height: Spacing.p),
          OptionCard(
            icon: Icons.search,
            title: tr('Procurar pela marca', 'Search by brand'),
            subtitle: tr(
              'Se você não sabe o tipo ou quer ver todos os aparelhos de uma marca.',
              "If you don't know the type or want to see every appliance from a brand.",
            ),
            onTap: () => _openModel(null),
          ),
          const SizedBox(height: Spacing.p),
          const EstimateCallToAction(),
        ],
      ),
    );
  }
}

/// Botoes grandes com icone e nome de cada tipo. Duas colunas no celular;
/// uma coluna quando a fonte do sistema esta grande ou a tela e estreita.
class TypeGrid extends StatelessWidget {
  final List<String> categories;
  final void Function(String) onChoose;

  const TypeGrid(this.categories, {super.key, required this.onChoose});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, limits) {
        final columns = largeFont(context) || limits.maxWidth < 340 ? 1 : 2;
        if (columns == 1) {
          return Column(
            children: [
              for (final c in categories)
                OptionCard(icon: categoryIcon(c), title: categoryName(c), onTap: () => onChoose(c)),
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < categories.length; i += 2)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _TypeButton(categories[i], onChoose: onChoose)),
                    const SizedBox(width: Spacing.p),
                    Expanded(
                      child: i + 1 < categories.length
                          ? _TypeButton(categories[i + 1], onChoose: onChoose)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TypeButton extends StatelessWidget {
  final String category;
  final void Function(String) onChoose;

  const _TypeButton(this.category, {required this.onChoose});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onChoose(category),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.pm, vertical: Spacing.m),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(categoryIcon(category), size: t.largeIcon),
                  const SizedBox(height: Spacing.p),
                  Text(categoryName(category), style: t.strong, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Etapa 2: marca e/ou modelo, dentro do tipo escolhido (ou de todos).
class ModelScreen extends StatefulWidget {
  final String? category;

  const ModelScreen({super.key, this.category});

  @override
  State<ModelScreen> createState() => _ModelScreenState();
}

class _ModelScreenState extends State<ModelScreen> {
  final _text = TextEditingController();
  List<Appliance>? _results;
  bool _loading = false;
  String? _error;
  int _request = 0; // so a busca mais recente vale
  Future<List<Brand>>? _brands; // todas as marcas do tipo escolhido (lista abaixo do campo)
  String _filter = ''; // o que a pessoa digitou: filtra a lista de marcas

  @override
  void initState() {
    super.initState();
    _loadBrands();
  }

  void _loadBrands() {
    final c = widget.category;
    if (c != null) _brands = Api.brands(c);
  }

  /// Mudou o texto: a lista de marcas filtra na hora e o resultado da busca anterior sai da tela.
  void _typed(String text) {
    setState(() {
      _filter = text.trim().toLowerCase();
      _results = null;
      _error = null;
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final searchText = _text.text.trim();
    if (searchText.length < 2) {
      setState(() => _error = tr('Digite pelo menos 2 letras da marca ou do modelo.', 'Type at least 2 letters of the brand or model.'));
      return;
    }
    FocusScope.of(context).unfocus(); // fecha o teclado para mostrar os resultados
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final itemList = await Api.searchAppliances(searchText, category: widget.category);
      if (mounted && request == _request) setState(() => _results = itemList);
    } on ApiError catch (e) {
      if (mounted && request == _request) setState(() => _error = e.message);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _choose(Appliance appliance) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => UsageScreen(query: Query(appliance))));
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final c = widget.category;
    final results = _results;
    return AppPage(
      title: c == null ? tr('Procurar aparelho', 'Find an appliance') : categoryName(c),
      step: const FlowStep(2, totalSteps),
      footer: FilledButton.icon(
        onPressed: _loading ? null : _search,
        icon: const Icon(Icons.search),
        label: Text(tr('Buscar', 'Search')),
      ),
      child: ListView(
        children: [
          QuestionHeader(
            tr('Qual é a marca e o modelo?', 'What is the brand and model?'),
            help: c == null
                ? tr(
                    'Pode digitar só a marca. A marca e o modelo estão na etiqueta do aparelho ou no manual.',
                    "You can type just the brand. The brand and model are on the appliance's label or in the manual.",
                  )
                : tr(
                    'Escolha a marca na lista ou digite a marca e o modelo. Eles estão na etiqueta ${c == 'chuveiro' ? 'da embalagem' : 'do aparelho'} ou no manual.',
                    'Pick the brand from the list or type the brand and model. They are on the label ${c == 'chuveiro' ? 'of the box' : 'of the appliance'} or in the manual.',
                  ),
          ),
          TextField(
            controller: _text,
            autofocus: c == null, // com a lista de marcas, o teclado nao abre sozinho por cima dela
            textInputAction: TextInputAction.search,
            onChanged: _typed,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: tr('Marca e/ou modelo', 'Brand and/or model'),
              hintText: tr('Ex.: Brastemp, Bosch EWI, Samsung', 'E.g.: Brastemp, Bosch EWI, Samsung'),
              suffixIcon: IconButton(tooltip: tr('Buscar', 'Search'), icon: const Icon(Icons.search), onPressed: _search),
            ),
          ),
          const SizedBox(height: Spacing.m),
          if (_loading) Loading(text: tr('Procurando...', 'Searching...')),
          if (_error != null) ErrorMessage(_error!),
          if (!_loading && results != null && results.isEmpty) ...[
            Text(
              tr(
                'Nenhum aparelho encontrado. Tente só a marca ou parte do modelo.',
                'No appliance found. Try just the brand or part of the model.',
              ),
              style: t.body,
            ),
            const SizedBox(height: Spacing.m),
            const EstimateCallToAction(),
          ],
          if (!_loading && results != null && results.isNotEmpty) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                results.length == 1
                    ? tr('1 aparelho encontrado', '1 appliance found')
                    : tr('${results.length} aparelhos encontrados', '${results.length} appliances found'),
                style: t.label,
              ),
            ),
            const SizedBox(height: Spacing.p),
            // a chave muda a cada busca: as secoes voltam a ficar fechadas
            ResultsPerType(results, key: ObjectKey(results), onChoose: _choose),
            const SizedBox(height: Spacing.m),
            const EstimateCallToAction(),
          ],
          // lista de marcas do tipo escolhido (some enquanto o resultado de uma busca esta na tela)
          if (c != null && results == null && !_loading) ...[
            const SizedBox(height: Spacing.p),
            Text(tr('Ou escolha a marca', 'Or pick the brand'), style: t.strong),
            const SizedBox(height: Spacing.p),
            _BrandList(
              category: c,
              brands: _brands,
              filterText: _filter,
              onChoose: _choose,
              tryAgain: () => setState(_loadBrands),
            ),
          ],
        ],
      ),
    );
  }
}

/// Todas as marcas de um tipo, filtradas pelo texto digitado. Cada marca abre os modelos dela.
class _BrandList extends StatelessWidget {
  final String category;
  final Future<List<Brand>>? brands;
  final String filterText;
  final void Function(Appliance) onChoose;
  final VoidCallback tryAgain;

  const _BrandList({
    required this.category,
    required this.brands,
    required this.filterText,
    required this.onChoose,
    required this.tryAgain,
  });

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return FutureBuilder<List<Brand>>(
      future: brands,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Loading(text: tr('Carregando as marcas...', 'Loading brands...'));
        }
        if (snap.hasError) {
          final error = snap.error;
          return ErrorMessage(
            error is ApiError ? error.message : tr('Não deu para carregar as marcas.', 'Could not load the brands.'),
            tryAgain: tryAgain,
          );
        }
        final visible = [
          for (final m in snap.data!)
            if (m.name.toLowerCase().contains(filterText)) m,
        ];
        if (visible.isEmpty) {
          return Text(
            tr(
              'Nenhuma marca com "$filterText". Toque em Buscar para procurar pelo modelo.',
              'No brand matches "$filterText". Tap Search to look for the model.',
            ),
            style: t.body,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                visible.length == 1 ? tr('1 marca', '1 brand') : tr('${visible.length} marcas', '${visible.length} brands'),
                style: t.label,
              ),
            ),
            const SizedBox(height: Spacing.p),
            // a chave e a marca: ao filtrar, cada secao continua com os modelos que ja carregou
            for (final m in visible) _BrandSection(category, m, key: ValueKey(m.name), onChoose: onChoose),
          ],
        );
      },
    );
  }
}

/// Uma marca: fechada mostra o nome e quantos modelos tem; ao abrir, busca os modelos na API.
class _BrandSection extends StatefulWidget {
  final String category;
  final Brand brand;
  final void Function(Appliance) onChoose;

  const _BrandSection(this.category, this.brand, {super.key, required this.onChoose});

  @override
  State<_BrandSection> createState() => _BrandSectionState();
}

class _BrandSectionState extends State<_BrandSection> {
  Future<List<Appliance>>? _models; // so carrega quando a pessoa abre a marca

  // corpo em bloco: com "=>" a funcao devolveria o Future e o setState(_carregar) quebra
  void _load() {
    _models = Api.brandModels(widget.category, widget.brand.name);
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final m = widget.brand;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(m.name, style: t.strong),
        subtitle: Text(
          m.models == 1 ? tr('1 modelo', '1 model') : tr('${m.models} modelos', '${m.models} models'),
          style: t.secondary,
        ),
        onExpansionChanged: (isOpen) {
          if (isOpen && _models == null) setState(_load);
        },
        children: [
          FutureBuilder<List<Appliance>>(
            future: _models,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Padding(
                  padding: const EdgeInsets.all(Spacing.m),
                  child: Loading(text: tr('Carregando os modelos...', 'Loading models...')),
                );
              }
              if (snap.hasError) {
                final error = snap.error;
                return Padding(
                  padding: const EdgeInsets.all(Spacing.m),
                  child: ErrorMessage(
                    error is ApiError ? error.message : tr('Não deu para carregar os modelos.', 'Could not load the models.'),
                    tryAgain: () => setState(_load),
                  ),
                );
              }
              final itemList = snap.data!;
              final total = itemList.isEmpty ? 0 : (itemList.first.totalCategory > itemList.length ? itemList.first.totalCategory : itemList.length);
              return Column(
                children: [
                  for (final a in itemList) ...[
                    const Divider(height: 1),
                    ListTile(
                      title: Text(a.model),
                      subtitle: a.detail.isEmpty ? null : Text(a.detail),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => widget.onChoose(a),
                    ),
                  ],
                  if (total > itemList.length) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(Spacing.m),
                      child: Text(
                        tr(
                          'Mostrando ${itemList.length} de $total. Digite o modelo no campo acima para achar os outros.',
                          'Showing ${itemList.length} of $total. Type the model in the field above to find the others.',
                        ),
                        style: t.secondary,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Resultados agrupados por tipo de aparelho, em secoes que abrem e fecham.
/// Uma marca pode ter varios tipos (ex.: Philco tem 7): cada tipo vira uma secao com a quantidade.
/// Se so ha um tipo (busca pelo modelo ou dentro de um tipo), a secao ja vem aberta.
class ResultsPerType extends StatelessWidget {
  final List<Appliance> results;
  final void Function(Appliance) onChoose;

  const ResultsPerType(this.results, {super.key, required this.onChoose});

  @override
  Widget build(BuildContext context) {
    final byType = <String, List<Appliance>>{}; // mantem a ordem da API
    for (final a in results) {
      byType.putIfAbsent(a.category, () => []).add(a);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final MapEntry(key: kind, value: itemList) in byType.entries)
          _TypeSection(kind, itemList, isOpen: byType.length == 1, onChoose: onChoose),
      ],
    );
  }
}

class _TypeSection extends StatelessWidget {
  final String kind;
  final List<Appliance> itemList;
  final bool isOpen;
  final void Function(Appliance) onChoose;

  const _TypeSection(this.kind, this.itemList, {required this.isOpen, required this.onChoose});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final total = itemList.first.totalCategory > itemList.length ? itemList.first.totalCategory : itemList.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: isOpen,
        leading: Icon(categoryIcon(kind)),
        title: Text(categoryTitle(kind), style: t.strong),
        subtitle: Text(total == 1 ? tr('1 modelo', '1 model') : tr('$total modelos', '$total models'), style: t.secondary),
        children: [
          for (final a in itemList) ...[
            const Divider(height: 1),
            ListTile(
              title: Text(a.name),
              subtitle: a.detail.isEmpty ? null : Text(a.detail),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onChoose(a),
            ),
          ],
          if (total > itemList.length) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(Spacing.m),
              child: Text(
                tr(
                  'Mostrando ${itemList.length} de $total. Digite parte do modelo para achar os outros.',
                  'Showing ${itemList.length} of $total. Type part of the model to find the others.',
                ),
                style: t.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class EstimateCallToAction extends StatelessWidget {
  const EstimateCallToAction({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Card(
      color: t.highlightBackground,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(Icons.calculate_outlined, size: t.largeIcon),
        title: Text(tr('Não achou? Estime o gasto', "Can't find it? Estimate the cost")),
        subtitle: Text(
          tr(
            'Para aparelhos mais antigos (geladeira, máquina de lavar, ar...) ou eletroportáteis como air fryer e secador.',
            'For older appliances (fridge, washing machine, AC...) or small appliances like an air fryer or hair dryer.',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EstimateScreen())),
      ),
    );
  }
}

/// Resumo da casa na tela inicial (aparece depois do primeiro aparelho adicionado).
class _HomeSummary extends StatelessWidget {
  const _HomeSummary();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: home,
      builder: (context, _) {
        if (home.isEmpty) return const SizedBox.shrink();
        final n = home.totalAppliances;
        return Padding(
          padding: const EdgeInsets.only(bottom: Spacing.m),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text(tr('Minha casa: ${reais(home.monthlyCost)} por mês', 'My home: ${reais(home.monthlyCost)} per month')),
              subtitle: Text(
                tr(
                  '$n ${n == 1 ? 'aparelho' : 'aparelhos'} · toque para ver',
                  '$n ${n == 1 ? 'appliance' : 'appliances'} · tap to view',
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => goTo(AppTab.home),
            ),
          ),
        );
      },
    );
  }
}
