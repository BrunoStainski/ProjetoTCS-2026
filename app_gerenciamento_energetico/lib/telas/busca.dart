import 'package:flutter/material.dart';

import '../api.dart';
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
    Api.categorias().then((c) => setState(() => _categorias = c)).catchError((_) {});
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
      titulo: 'iamp - Qual é o aparelho?',
      passo: 1,
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Descubra quanto um aparelho pesa na sua conta de luz.',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _texto,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _buscar(),
            decoration: InputDecoration(
              labelText: 'Marca e/ou modelo',
              hintText: 'Ex.: brastemp, bosch ewi, samsung',
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _buscar),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _categoria,
            decoration: const InputDecoration(labelText: 'Tipo de aparelho (opcional)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todos')),
              for (final c in _categorias) DropdownMenuItem(value: c, child: Text(c.replaceAll('_', ' '))),
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
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final a = _resultados![i];
                  return ListTile(
                    title: Text(a.nome),
                    subtitle: Text([a.categoriaLegivel, if (a.detalhe.isNotEmpty) a.detalhe].join(' - ')),
                    trailing: const Icon(Icons.chevron_right),
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
