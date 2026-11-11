// Comeco do calculo, uma decisao por tela:
// etapa 1 (TelaBusca): qual tipo de aparelho; etapa 2 (TelaModelo): marca e modelo.

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
class TelaBusca extends StatefulWidget {
  const TelaBusca({super.key});

  @override
  State<TelaBusca> createState() => _TelaBuscaState();
}

class _TelaBuscaState extends State<TelaBusca> {
  late Future<List<String>> _categorias;

  @override
  void initState() {
    super.initState();
    _categorias = Api.categorias();
  }

  void _abrirModelo(String? categoria) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => TelaModelo(categoria: categoria)));
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Iamp',
      tituloWidget: const LogoIamp(),
      etapa: const Etapa(1, totalEtapas),
      filho: ListView(
        children: [
          CabecalhoPergunta(
            tr('Qual aparelho você quer calcular?', 'Which appliance do you want to calculate?'),
            ajuda: tr(
              'Mostramos quanto ele pesa na sua conta de luz, com dados oficiais do Inmetro e da ANEEL.',
              'We show how much it adds to your electricity bill, using official data from Inmetro and ANEEL '
                  '(Brazilian energy regulators).',
            ),
          ),
          const _ResumoCasa(),
          FutureBuilder<List<String>>(
            future: _categorias,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Carregando(texto: tr('Carregando os aparelhos...', 'Loading appliances...'));
              }
              if (snap.hasError) {
                return MensagemErro(
                  snap.error.toString(),
                  tentarDeNovo: () => setState(() {
                    _categorias = Api.categorias();
                  }),
                );
              }
              return GradeDeTipos(snap.data!, aoEscolher: _abrirModelo);
            },
          ),
          const SizedBox(height: Espaco.p),
          CartaoOpcao(
            icone: Icons.search,
            titulo: tr('Procurar pela marca', 'Search by brand'),
            subtitulo: tr(
              'Se você não sabe o tipo ou quer ver todos os aparelhos de uma marca.',
              "If you don't know the type or want to see every appliance from a brand.",
            ),
            onTap: () => _abrirModelo(null),
          ),
          const SizedBox(height: Espaco.p),
          const ChamadaEstimar(),
        ],
      ),
    );
  }
}

/// Botoes grandes com icone e nome de cada tipo. Duas colunas no celular;
/// uma coluna quando a fonte do sistema esta grande ou a tela e estreita.
class GradeDeTipos extends StatelessWidget {
  final List<String> categorias;
  final void Function(String) aoEscolher;

  const GradeDeTipos(this.categorias, {super.key, required this.aoEscolher});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, limites) {
        final colunas = fonteGrande(context) || limites.maxWidth < 340 ? 1 : 2;
        if (colunas == 1) {
          return Column(
            children: [
              for (final c in categorias)
                CartaoOpcao(icone: iconeDaCategoria(c), titulo: nomeDaCategoria(c), onTap: () => aoEscolher(c)),
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < categorias.length; i += 2)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _BotaoTipo(categorias[i], aoEscolher: aoEscolher)),
                    const SizedBox(width: Espaco.p),
                    Expanded(
                      child: i + 1 < categorias.length
                          ? _BotaoTipo(categorias[i + 1], aoEscolher: aoEscolher)
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

class _BotaoTipo extends StatelessWidget {
  final String categoria;
  final void Function(String) aoEscolher;

  const _BotaoTipo(this.categoria, {required this.aoEscolher});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => aoEscolher(categoria),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espaco.pm, vertical: Espaco.m),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(iconeDaCategoria(categoria), size: t.iconeGrande),
                  const SizedBox(height: Espaco.p),
                  Text(nomeDaCategoria(categoria), style: t.forte, textAlign: TextAlign.center),
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
class TelaModelo extends StatefulWidget {
  final String? categoria;

  const TelaModelo({super.key, this.categoria});

  @override
  State<TelaModelo> createState() => _TelaModeloState();
}

class _TelaModeloState extends State<TelaModelo> {
  final _texto = TextEditingController();
  List<Aparelho>? _resultados;
  bool _carregando = false;
  String? _erro;
  int _pedido = 0; // so a busca mais recente vale
  Future<List<Marca>>? _marcas; // todas as marcas do tipo escolhido (lista abaixo do campo)
  String _filtro = ''; // o que a pessoa digitou: filtra a lista de marcas

  @override
  void initState() {
    super.initState();
    _carregarMarcas();
  }

  void _carregarMarcas() {
    final c = widget.categoria;
    if (c != null) _marcas = Api.marcas(c);
  }

  /// Mudou o texto: a lista de marcas filtra na hora e o resultado da busca anterior sai da tela.
  void _digitou(String texto) {
    setState(() {
      _filtro = texto.trim().toLowerCase();
      _resultados = null;
      _erro = null;
    });
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final busca = _texto.text.trim();
    if (busca.length < 2) {
      setState(() => _erro = tr('Digite pelo menos 2 letras da marca ou do modelo.', 'Type at least 2 letters of the brand or model.'));
      return;
    }
    FocusScope.of(context).unfocus(); // fecha o teclado para mostrar os resultados
    final pedido = ++_pedido;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final lista = await Api.buscarAparelhos(busca, categoria: widget.categoria);
      if (mounted && pedido == _pedido) setState(() => _resultados = lista);
    } on ApiErro catch (e) {
      if (mounted && pedido == _pedido) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted && pedido == _pedido) setState(() => _carregando = false);
    }
  }

  void _escolher(Aparelho aparelho) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => TelaUso(consulta: Consulta(aparelho))));
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final c = widget.categoria;
    final resultados = _resultados;
    return Pagina(
      titulo: c == null ? tr('Procurar aparelho', 'Find an appliance') : nomeDaCategoria(c),
      etapa: const Etapa(2, totalEtapas),
      rodape: FilledButton.icon(
        onPressed: _carregando ? null : _buscar,
        icon: const Icon(Icons.search),
        label: Text(tr('Buscar', 'Search')),
      ),
      filho: ListView(
        children: [
          CabecalhoPergunta(
            tr('Qual é a marca e o modelo?', 'What is the brand and model?'),
            ajuda: c == null
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
            controller: _texto,
            autofocus: c == null, // com a lista de marcas, o teclado nao abre sozinho por cima dela
            textInputAction: TextInputAction.search,
            onChanged: _digitou,
            onSubmitted: (_) => _buscar(),
            decoration: InputDecoration(
              labelText: tr('Marca e/ou modelo', 'Brand and/or model'),
              hintText: tr('Ex.: Brastemp, Bosch EWI, Samsung', 'E.g.: Brastemp, Bosch EWI, Samsung'),
              suffixIcon: IconButton(tooltip: tr('Buscar', 'Search'), icon: const Icon(Icons.search), onPressed: _buscar),
            ),
          ),
          const SizedBox(height: Espaco.m),
          if (_carregando) Carregando(texto: tr('Procurando...', 'Searching...')),
          if (_erro != null) MensagemErro(_erro!),
          if (!_carregando && resultados != null && resultados.isEmpty) ...[
            Text(
              tr(
                'Nenhum aparelho encontrado. Tente só a marca ou parte do modelo.',
                'No appliance found. Try just the brand or part of the model.',
              ),
              style: t.corpo,
            ),
            const SizedBox(height: Espaco.m),
            const ChamadaEstimar(),
          ],
          if (!_carregando && resultados != null && resultados.isNotEmpty) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                resultados.length == 1
                    ? tr('1 aparelho encontrado', '1 appliance found')
                    : tr('${resultados.length} aparelhos encontrados', '${resultados.length} appliances found'),
                style: t.rotulo,
              ),
            ),
            const SizedBox(height: Espaco.p),
            // a chave muda a cada busca: as secoes voltam a ficar fechadas
            ResultadosPorTipo(resultados, key: ObjectKey(resultados), aoEscolher: _escolher),
            const SizedBox(height: Espaco.m),
            const ChamadaEstimar(),
          ],
          // lista de marcas do tipo escolhido (some enquanto o resultado de uma busca esta na tela)
          if (c != null && resultados == null && !_carregando) ...[
            const SizedBox(height: Espaco.p),
            Text(tr('Ou escolha a marca', 'Or pick the brand'), style: t.forte),
            const SizedBox(height: Espaco.p),
            _ListaDeMarcas(
              categoria: c,
              marcas: _marcas,
              filtro: _filtro,
              aoEscolher: _escolher,
              tentarDeNovo: () => setState(_carregarMarcas),
            ),
          ],
        ],
      ),
    );
  }
}

/// Todas as marcas de um tipo, filtradas pelo texto digitado. Cada marca abre os modelos dela.
class _ListaDeMarcas extends StatelessWidget {
  final String categoria;
  final Future<List<Marca>>? marcas;
  final String filtro;
  final void Function(Aparelho) aoEscolher;
  final VoidCallback tentarDeNovo;

  const _ListaDeMarcas({
    required this.categoria,
    required this.marcas,
    required this.filtro,
    required this.aoEscolher,
    required this.tentarDeNovo,
  });

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return FutureBuilder<List<Marca>>(
      future: marcas,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Carregando(texto: tr('Carregando as marcas...', 'Loading brands...'));
        }
        if (snap.hasError) {
          final erro = snap.error;
          return MensagemErro(
            erro is ApiErro ? erro.mensagem : tr('Não deu para carregar as marcas.', 'Could not load the brands.'),
            tentarDeNovo: tentarDeNovo,
          );
        }
        final visiveis = [
          for (final m in snap.data!)
            if (m.nome.toLowerCase().contains(filtro)) m,
        ];
        if (visiveis.isEmpty) {
          return Text(
            tr(
              'Nenhuma marca com "$filtro". Toque em Buscar para procurar pelo modelo.',
              'No brand matches "$filtro". Tap Search to look for the model.',
            ),
            style: t.corpo,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                visiveis.length == 1 ? tr('1 marca', '1 brand') : tr('${visiveis.length} marcas', '${visiveis.length} brands'),
                style: t.rotulo,
              ),
            ),
            const SizedBox(height: Espaco.p),
            // a chave e a marca: ao filtrar, cada secao continua com os modelos que ja carregou
            for (final m in visiveis) _SecaoDaMarca(categoria, m, key: ValueKey(m.nome), aoEscolher: aoEscolher),
          ],
        );
      },
    );
  }
}

/// Uma marca: fechada mostra o nome e quantos modelos tem; ao abrir, busca os modelos na API.
class _SecaoDaMarca extends StatefulWidget {
  final String categoria;
  final Marca marca;
  final void Function(Aparelho) aoEscolher;

  const _SecaoDaMarca(this.categoria, this.marca, {super.key, required this.aoEscolher});

  @override
  State<_SecaoDaMarca> createState() => _SecaoDaMarcaState();
}

class _SecaoDaMarcaState extends State<_SecaoDaMarca> {
  Future<List<Aparelho>>? _modelos; // so carrega quando a pessoa abre a marca

  // corpo em bloco: com "=>" a funcao devolveria o Future e o setState(_carregar) quebra
  void _carregar() {
    _modelos = Api.modelosDaMarca(widget.categoria, widget.marca.nome);
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final m = widget.marca;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(m.nome, style: t.forte),
        subtitle: Text(
          m.modelos == 1 ? tr('1 modelo', '1 model') : tr('${m.modelos} modelos', '${m.modelos} models'),
          style: t.secundario,
        ),
        onExpansionChanged: (aberta) {
          if (aberta && _modelos == null) setState(_carregar);
        },
        children: [
          FutureBuilder<List<Aparelho>>(
            future: _modelos,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Padding(
                  padding: const EdgeInsets.all(Espaco.m),
                  child: Carregando(texto: tr('Carregando os modelos...', 'Loading models...')),
                );
              }
              if (snap.hasError) {
                final erro = snap.error;
                return Padding(
                  padding: const EdgeInsets.all(Espaco.m),
                  child: MensagemErro(
                    erro is ApiErro ? erro.mensagem : tr('Não deu para carregar os modelos.', 'Could not load the models.'),
                    tentarDeNovo: () => setState(_carregar),
                  ),
                );
              }
              final lista = snap.data!;
              final total = lista.isEmpty ? 0 : (lista.first.totalCategoria > lista.length ? lista.first.totalCategoria : lista.length);
              return Column(
                children: [
                  for (final a in lista) ...[
                    const Divider(height: 1),
                    ListTile(
                      title: Text(a.modelo),
                      subtitle: a.detalhe.isEmpty ? null : Text(a.detalhe),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => widget.aoEscolher(a),
                    ),
                  ],
                  if (total > lista.length) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(Espaco.m),
                      child: Text(
                        tr(
                          'Mostrando ${lista.length} de $total. Digite o modelo no campo acima para achar os outros.',
                          'Showing ${lista.length} of $total. Type the model in the field above to find the others.',
                        ),
                        style: t.secundario,
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
class ResultadosPorTipo extends StatelessWidget {
  final List<Aparelho> resultados;
  final void Function(Aparelho) aoEscolher;

  const ResultadosPorTipo(this.resultados, {super.key, required this.aoEscolher});

  @override
  Widget build(BuildContext context) {
    final porTipo = <String, List<Aparelho>>{}; // mantem a ordem da API
    for (final a in resultados) {
      porTipo.putIfAbsent(a.categoria, () => []).add(a);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final MapEntry(key: tipo, value: lista) in porTipo.entries)
          _SecaoDoTipo(tipo, lista, aberta: porTipo.length == 1, aoEscolher: aoEscolher),
      ],
    );
  }
}

class _SecaoDoTipo extends StatelessWidget {
  final String tipo;
  final List<Aparelho> lista;
  final bool aberta;
  final void Function(Aparelho) aoEscolher;

  const _SecaoDoTipo(this.tipo, this.lista, {required this.aberta, required this.aoEscolher});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final total = lista.first.totalCategoria > lista.length ? lista.first.totalCategoria : lista.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: aberta,
        leading: Icon(iconeDaCategoria(tipo)),
        title: Text(tituloDaCategoria(tipo), style: t.forte),
        subtitle: Text(total == 1 ? tr('1 modelo', '1 model') : tr('$total modelos', '$total models'), style: t.secundario),
        children: [
          for (final a in lista) ...[
            const Divider(height: 1),
            ListTile(
              title: Text(a.nome),
              subtitle: a.detalhe.isEmpty ? null : Text(a.detalhe),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => aoEscolher(a),
            ),
          ],
          if (total > lista.length) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(Espaco.m),
              child: Text(
                tr(
                  'Mostrando ${lista.length} de $total. Digite parte do modelo para achar os outros.',
                  'Showing ${lista.length} of $total. Type part of the model to find the others.',
                ),
                style: t.secundario,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ChamadaEstimar extends StatelessWidget {
  const ChamadaEstimar({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Card(
      color: t.fundoDestaque,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(Icons.calculate_outlined, size: t.iconeGrande),
        title: Text(tr('Não achou? Estime o gasto', "Can't find it? Estimate the cost")),
        subtitle: Text(
          tr(
            'Para aparelhos mais antigos (geladeira, máquina de lavar, ar...) ou eletroportáteis como air fryer e secador.',
            'For older appliances (fridge, washing machine, AC...) or small appliances like an air fryer or hair dryer.',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TelaEstimar())),
      ),
    );
  }
}

/// Resumo da casa na tela inicial (aparece depois do primeiro aparelho adicionado).
class _ResumoCasa extends StatelessWidget {
  const _ResumoCasa();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: casa,
      builder: (context, _) {
        if (casa.vazia) return const SizedBox.shrink();
        final n = casa.totalAparelhos;
        return Padding(
          padding: const EdgeInsets.only(bottom: Espaco.m),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text(tr('Minha casa: ${reais(casa.custoMes)} por mês', 'My home: ${reais(casa.custoMes)} per month')),
              subtitle: Text(
                tr(
                  '$n ${n == 1 ? 'aparelho' : 'aparelhos'} · toque para ver',
                  '$n ${n == 1 ? 'appliance' : 'appliances'} · tap to view',
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => irPara(Aba.casa),
            ),
          ),
        );
      },
    );
  }
}
