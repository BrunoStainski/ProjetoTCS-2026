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
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final lista = await Api.buscarAparelhos(busca, categoria: _categoria);
      setState(() => _resultados = lista);
    } on ApiErro catch (e) {
      setState(() => _erro = e.mensagem);
    } finally {
      setState(() => _carregando = false);
    }
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
            onChanged: (c) => setState(() => _categoria = c),
          ),
          const SizedBox(height: 16),
          if (_carregando) const Center(child: CircularProgressIndicator()),
          if (_erro != null) MensagemErro(_erro!),
          if (!_carregando && _resultados != null && _resultados!.isEmpty)
            const Text('Nenhum aparelho encontrado. Tente só a marca ou parte do modelo.'),
          if (!_carregando && _resultados != null && _resultados!.isNotEmpty)
            Expanded(
              child: ListView.separated(
                itemCount: _resultados!.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final a = _resultados![i];
                  return ListTile(
                    leading: Icon(iconeDaCategoria(a.categoria)),
                    title: Text(a.nome),
                    subtitle: Text(
                      [a.categoriaLegivel, if (a.detalhe.isNotEmpty) a.detalhe].join(' - '),
                      style: Estilos.secundario,
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Cores.amarelo),
                    onTap: () => _escolher(a),
                  );
                },
              ),
            ),
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
