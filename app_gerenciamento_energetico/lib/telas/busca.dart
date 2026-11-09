import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../tema.dart';
import 'comum.dart';
import 'uso.dart';

/// Passo 1: o usuario busca o aparelho pela marca e/ou modelo.
class TelaBusca extends StatefulWidget {
  const TelaBusca({super.key});

  @override
  State<TelaBusca> createState() => _TelaBuscaState();
}

class _TelaBuscaState extends State<TelaBusca> {
  final _texto = TextEditingController();
  List<String> _categorias = [];
  String? _categoria;
  List<Aparelho>? _resultados;
  bool _carregando = false;
  String? _erro;
  int _pedido = 0; // so a busca mais recente vale (trocar o tipo rapido dispara varias)

  @override
  void initState() {
    super.initState();
    Api.categorias()
        .then((c) {
          if (mounted) setState(() => _categorias = c);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final busca = _texto.text.trim();
    if (busca.length < 2) {
      setState(() => _erro = 'Digite pelo menos 2 letras.');
      return;
    }
    final pedido = ++_pedido;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final lista = await Api.buscarAparelhos(busca, categoria: _categoria);
      if (mounted && pedido == _pedido) setState(() => _resultados = lista);
    } on ApiErro catch (e) {
      if (mounted && pedido == _pedido) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted && pedido == _pedido) setState(() => _carregando = false);
    }
  }

  /// Trocar o tipo de aparelho refaz a busca na hora (se ja tem texto para buscar).
  /// Sem texto ainda, so guarda o tipo: a busca acontece quando a pessoa digitar.
  void _trocarTipo(String? categoria) {
    setState(() => _categoria = categoria);
    if (_texto.text.trim().length >= 2) _buscar();
  }

  void _escolher(Aparelho aparelho) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => TelaUso(consulta: Consulta(aparelho))));
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'iamp',
      tituloWidget: const LogoIamp(),
      passo: 1,
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Quanto cada aparelho pesa na sua conta de luz?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text('Dados oficiais do Inmetro e tarifas da ANEEL.', style: Estilos.secundario),
          const SizedBox(height: 16),
          const _AtalhoCasa(),
          TextField(
            controller: _texto,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _buscar(),
            decoration: InputDecoration(
              labelText: 'Marca e/ou modelo',
              hintText: 'Ex.: brastemp, bosch ewi, samsung',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search, color: Cores.amarelo),
                onPressed: _buscar,
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _categoria,
            dropdownColor: Cores.superficieAlta,
            iconEnabledColor: Cores.amarelo,
            decoration: const InputDecoration(labelText: 'Tipo de aparelho (opcional)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todos')),
              for (final c in _categorias) DropdownMenuItem(value: c, child: Text(legivel(c))),
            ],
            onChanged: _trocarTipo,
          ),
          const SizedBox(height: 16),
          if (_carregando) const Center(child: CircularProgressIndicator()),
          if (_erro != null) MensagemErro(_erro!),
          if (!_carregando && _resultados != null && _resultados!.isEmpty)
            const Text('Nenhum aparelho encontrado. Tente só a marca ou parte do modelo.'),
          if (!_carregando && _resultados != null && _resultados!.isNotEmpty)
            Expanded(
              // a chave muda a cada busca: as secoes voltam a ficar fechadas
              child: ResultadosPorTipo(_resultados!, key: ObjectKey(_resultados), aoEscolher: _escolher),
            ),
        ],
      ),
    );
  }
}

/// Resultados agrupados por tipo de aparelho, em secoes que abrem e fecham.
/// Uma marca pode ter varios tipos (ex.: Philco tem 7): cada tipo vira uma secao com a quantidade.
/// Se so ha um tipo (busca pelo modelo ou com o filtro de tipo), a secao ja vem aberta.
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
    return ListView(
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
    final total = lista.first.totalCategoria > lista.length ? lista.first.totalCategoria : lista.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: aberta,
        leading: Icon(iconeDaCategoria(tipo)),
        title: Text(tituloDaCategoria(tipo), style: Estilos.forte),
        subtitle: Text(total == 1 ? '1 modelo' : '$total modelos', style: Estilos.secundario),
        children: [
          for (final a in lista) ...[
            const Divider(height: 1),
            ListTile(
              title: Text(a.nome),
              subtitle: a.detalhe.isEmpty ? null : Text(a.detalhe, style: Estilos.secundario),
              trailing: const Icon(Icons.chevron_right, color: Cores.amarelo),
              onTap: () => aoEscolher(a),
            ),
          ],
          if (total > lista.length) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(Espaco.m),
              child: Text(
                'Mostrando ${lista.length} de $total. Digite parte do modelo para achar os outros.',
                style: Estilos.secundario,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Resumo da casa na tela inicial (aparece depois do primeiro aparelho adicionado).
class _AtalhoCasa extends StatelessWidget {
  const _AtalhoCasa();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: casa,
      builder: (context, _) {
        if (casa.vazia) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text('Minha casa: ${reais(casa.custoMes)} por mês'),
              subtitle: Text(
                '${casa.totalAparelhos} aparelho(s) - ${numero(casa.kwhMes)} kWh/mês',
                style: Estilos.secundario,
              ),
              trailing: const Icon(Icons.chevron_right, color: Cores.amarelo),
              onTap: () => abrirMinhaCasa(context),
            ),
          ),
        );
      },
    );
  }
}
