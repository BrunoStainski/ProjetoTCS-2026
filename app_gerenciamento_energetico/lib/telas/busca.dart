// Comeco do calculo, uma decisao por tela:
// etapa 1 (TelaBusca): qual tipo de aparelho; etapa 2 (TelaModelo): marca e modelo.

import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
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
          const CabecalhoPergunta(
            'Qual aparelho você quer calcular?',
            ajuda: 'Mostramos quanto ele pesa na sua conta de luz, com dados oficiais do Inmetro e da ANEEL.',
          ),
          const _ResumoCasa(),
          FutureBuilder<List<String>>(
            future: _categorias,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Carregando(texto: 'Carregando os aparelhos...');
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
            titulo: 'Procurar pela marca',
            subtitulo: 'Se você não sabe o tipo ou quer ver todos os aparelhos de uma marca.',
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

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final busca = _texto.text.trim();
    if (busca.length < 2) {
      setState(() => _erro = 'Digite pelo menos 2 letras da marca ou do modelo.');
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
      titulo: c == null ? 'Procurar aparelho' : nomeDaCategoria(c),
      etapa: const Etapa(2, totalEtapas),
      rodape: FilledButton.icon(
        onPressed: _carregando ? null : _buscar,
        icon: const Icon(Icons.search),
        label: const Text('Buscar'),
      ),
      filho: ListView(
        children: [
          CabecalhoPergunta(
            'Qual é a marca e o modelo?',
            ajuda: c == null
                ? 'Pode digitar só a marca. A marca e o modelo estão na etiqueta do aparelho ou no manual.'
                : 'Pode digitar só a marca. A marca e o modelo estão na etiqueta ${c == 'chuveiro' ? 'da embalagem' : 'do aparelho'} ou no manual.',
          ),
          TextField(
            controller: _texto,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _buscar(),
            decoration: InputDecoration(
              labelText: 'Marca e/ou modelo',
              hintText: 'Ex.: Brastemp, Bosch EWI, Samsung',
              suffixIcon: IconButton(tooltip: 'Buscar', icon: const Icon(Icons.search), onPressed: _buscar),
            ),
          ),
          const SizedBox(height: Espaco.m),
          if (_carregando) const Carregando(texto: 'Procurando...'),
          if (_erro != null) MensagemErro(_erro!),
          if (!_carregando && resultados != null && resultados.isEmpty) ...[
            Text('Nenhum aparelho encontrado. Tente só a marca ou parte do modelo.', style: t.corpo),
            const SizedBox(height: Espaco.m),
            const ChamadaEstimar(),
          ],
          if (!_carregando && resultados != null && resultados.isNotEmpty) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                resultados.length == 1 ? '1 aparelho encontrado' : '${resultados.length} aparelhos encontrados',
                style: t.rotulo,
              ),
            ),
            const SizedBox(height: Espaco.p),
            // a chave muda a cada busca: as secoes voltam a ficar fechadas
            ResultadosPorTipo(resultados, key: ObjectKey(resultados), aoEscolher: _escolher),
            const SizedBox(height: Espaco.m),
            const ChamadaEstimar(),
          ],
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
        subtitle: Text(total == 1 ? '1 modelo' : '$total modelos', style: t.secundario),
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
                'Mostrando ${lista.length} de $total. Digite parte do modelo para achar os outros.',
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
        title: const Text('Não achou? Estime o gasto'),
        subtitle: const Text(
          'Para aparelhos mais antigos (geladeira, máquina de lavar, ar...) ou eletroportáteis como air fryer e secador.',
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
              title: Text('Minha casa: ${reais(casa.custoMes)} por mês'),
              subtitle: Text('$n ${n == 1 ? 'aparelho' : 'aparelhos'} · toque para ver'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => irPara(Aba.casa),
            ),
          ),
        );
      },
    );
  }
}
