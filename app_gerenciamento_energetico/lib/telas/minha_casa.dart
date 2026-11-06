import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../tema.dart';
import 'comum.dart';
import 'sugestoes.dart';

/// "Minha casa": soma os aparelhos calculados, mostra o que mais pesa na conta
/// e classifica o perfil da casa com o K-Means (POST /classificar).
class TelaMinhaCasa extends StatefulWidget {
  const TelaMinhaCasa({super.key});

  /// Quantas telas "Minha casa" estao abertas (para nao empilhar duas).
  static int abertas = 0;

  @override
  State<TelaMinhaCasa> createState() => _TelaMinhaCasaState();
}

class _TelaMinhaCasaState extends State<TelaMinhaCasa> {
  bool _classificando = false;
  String? _erroPerfil;

  @override
  void initState() {
    super.initState();
    TelaMinhaCasa.abertas++;
  }

  @override
  void dispose() {
    TelaMinhaCasa.abertas--;
    super.dispose();
  }

  Future<void> _classificar() async {
    setState(() {
      _classificando = true;
      _erroPerfil = null;
    });
    try {
      casa.guardarPerfil(await Api.classificar(casa.moradores, casa.itensParaPerfil()));
    } on ApiErro catch (e) {
      if (mounted) setState(() => _erroPerfil = e.mensagem);
    } finally {
      if (mounted) setState(() => _classificando = false);
    }
  }

  void _voltarParaBusca() => Navigator.popUntil(context, (rota) => rota.isFirst);

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Minha casa',
      mostrarCasa: false,
      filho: ListenableBuilder(
        listenable: casa,
        builder: (context, _) => casa.vazia ? _vazia() : _lista(),
      ),
    );
  }

  Widget _vazia() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.home_outlined, size: 64, color: Cores.amarelo),
          const SizedBox(height: 12),
          Text('Sua casa ainda está vazia', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Calcule um aparelho e toque em "Adicionar à minha casa". '
            'Com alguns aparelhos, o iamp mostra o total da conta e o perfil de consumo da casa.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Cores.cinza),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _voltarParaBusca,
            icon: const Icon(Icons.search),
            label: const Text('Buscar um aparelho'),
          ),
        ],
      ),
    );
  }

  Widget _lista() {
    final total = casa.kwhMes;
    return ListView(
      children: [
        CartaoDestaque(
          titulo: 'Sua casa por mês',
          valor: reais(casa.custoMes),
          rodape: '${reais(casa.custoAno)} por ano - ${numero(total)} kWh/mês',
        ),
        if (casa.tarifasMisturadas)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: ListaAvisos(['Alguns aparelhos foram calculados com tarifas diferentes; o total soma os dois.']),
          ),
        const Titulo('O que mais pesa na conta'),
        for (final item in casa.porCusto) _CartaoItem(item, fracao: total > 0 ? item.kwhMes / total : 0),
        TextButton.icon(
          onPressed: _voltarParaBusca,
          icon: const Icon(Icons.add),
          label: const Text('Adicionar outro aparelho'),
        ),
        const Titulo('Perfil de consumo da casa'),
        const Text(
          'Compara o consumo por morador com milhares de casas simuladas, usando um modelo de '
          'agrupamento (K-Means).',
          style: TextStyle(color: Cores.cinza),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.people_outline, color: Cores.amarelo),
            const SizedBox(width: 8),
            const Expanded(child: Text('Moradores')),
            IconButton(
              tooltip: 'Menos um morador',
              onPressed: casa.moradores > 1 ? () => casa.mudarMoradores(casa.moradores - 1) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('${casa.moradores}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(
              tooltip: 'Mais um morador',
              onPressed: casa.moradores < 20 ? () => casa.mudarMoradores(casa.moradores + 1) : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (casa.perfil == null)
          FilledButton.icon(
            onPressed: _classificando ? null : _classificar,
            icon: _classificando
                ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Cores.preto))
                : const Icon(Icons.insights),
            label: const Text('Ver perfil da casa'),
          ),
        if (_erroPerfil != null) MensagemErro(_erroPerfil!, tentarDeNovo: _classificar),
        if (casa.perfil != null) _CartaoPerfil(casa.perfil!, maior: casa.porCusto.first, total: total),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _CartaoItem extends StatelessWidget {
  final ItemCasa item;
  final double fracao;

  const _CartaoItem(this.item, {required this.fracao});

  @override
  Widget build(BuildContext context) {
    final r = item.resultado;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(iconeDaCategoria(r.categoria), color: Cores.amarelo),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text([legivel(r.categoria), if (r.detalhe.isNotEmpty) r.detalhe].join(' - '),
                          style: const TextStyle(color: Cores.cinza, fontSize: 12)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(reais(item.custoMes), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('${numero(item.kwhMes)} kWh', style: const TextStyle(color: Cores.cinza, fontSize: 12)),
                  ],
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opções',
                  color: Cores.superficieAlta,
                  icon: const Icon(Icons.more_vert, color: Cores.cinza),
                  onSelected: (opcao) {
                    if (opcao == 'remover') casa.remover(item);
                    if (opcao == 'economicos') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TelaSugestoes(consulta: item.consulta, item: item)),
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'economicos', child: Text('Ver modelos mais econômicos')),
                    PopupMenuItem(value: 'remover', child: Text('Remover da casa')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: fracao, minHeight: 6),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text('${numero(fracao * 100, casas: 0)}%', style: const TextStyle(color: Cores.cinza)),
                ),
                const Text('Qtd.', style: TextStyle(color: Cores.cinza)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Menos um',
                  onPressed: item.quantidade > 1 ? () => casa.mudarQuantidade(item, item.quantidade - 1) : null,
                  icon: const Icon(Icons.remove, size: 18),
                ),
                Text('${item.quantidade}'),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Mais um',
                  onPressed: () => casa.mudarQuantidade(item, item.quantidade + 1),
                  icon: const Icon(Icons.add, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoPerfil extends StatelessWidget {
  final Classificacao c;
  final ItemCasa maior;
  final double total;

  const _CartaoPerfil(this.c, {required this.maior, required this.total});

  static const _icones = {
    'Consciente': Icons.eco_outlined,
    'Moderado': Icons.balance,
    'Ineficiente': Icons.warning_amber_rounded,
  };

  static const _nomesFracoes = {
    'frac_chuveiro': 'Chuveiro',
    'frac_ar': 'Ar-condicionado',
    'frac_refrigerador': 'Geladeira e freezer',
  };

  @override
  Widget build(BuildContext context) {
    final acima = c.diferencaPercentual > 0;
    return Card(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: Cores.amarelo),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icones[c.perfil] ?? Icons.insights, color: Cores.amarelo, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Perfil da casa', style: TextStyle(color: Cores.cinza)),
                      Text(c.perfil,
                          style: const TextStyle(color: Cores.amarelo, fontSize: 26, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: CartaoInfo('Por morador', '${numero(c.kwhPorMorador, casas: 1)} kWh/mês')),
                Expanded(child: CartaoInfo('Mediana', '${numero(c.medianaKwhPorMorador, casas: 1)} kWh/mês')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(acima ? Icons.arrow_upward : Icons.arrow_downward, color: Cores.amarelo, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(_primeiraMaiuscula(c.comparacaoTexto))),
              ],
            ),
            const Titulo('Parte do consumo'),
            for (final e in _nomesFracoes.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(width: 150, child: Text(e.value)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: c.fracoes[e.key] ?? 0, minHeight: 6),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text('${numero((c.fracoes[e.key] ?? 0) * 100, casas: 0)}%',
                          textAlign: TextAlign.end, style: const TextStyle(color: Cores.cinza)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'O que mais pesa: ${maior.resultado.nome} '
              '(${numero(total > 0 ? maior.kwhMes / total * 100 : 0, casas: 0)}% do consumo). '
              'Veja no menu do item se existe um modelo mais econômico.',
            ),
            const SizedBox(height: 12),
            ListaAvisos([c.aviso, 'O perfil considera só os aparelhos que você adicionou.']),
          ],
        ),
      ),
    );
  }

  static String _primeiraMaiuscula(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
