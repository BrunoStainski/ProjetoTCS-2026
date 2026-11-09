import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../tema.dart';
import 'comum.dart';
import 'eco_coach.dart';
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
      // leva a tela ate o cartao do perfil, que aparece no fim da lista
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final alvo = _chavePerfil.currentContext;
        if (alvo != null && alvo.mounted) {
          Scrollable.ensureVisible(alvo, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
        }
      });
    } on ApiErro catch (e) {
      if (mounted) setState(() => _erroPerfil = e.mensagem);
    } finally {
      if (mounted) setState(() => _classificando = false);
    }
  }

  final _chavePerfil = GlobalKey();

  void _voltarParaBusca() => Navigator.popUntil(context, (rota) => rota.isFirst);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: casa,
      builder: (context, _) =>
          Pagina(titulo: 'Minha casa', mostrarCasa: false, rodape: _rodape(), filho: casa.vazia ? _vazia() : _lista()),
    );
  }

  /// Acao principal embaixo: buscar (casa vazia), ver o perfil e, depois do perfil, o Eco-Coach.
  Widget? _rodape() {
    if (casa.vazia) {
      return FilledButton.icon(
        onPressed: _voltarParaBusca,
        icon: const Icon(Icons.search),
        label: const Text('Buscar um aparelho'),
      );
    }
    if (casa.perfil != null) {
      return FilledButton.icon(
        onPressed: _abrirEcoCoach,
        icon: const Icon(Icons.auto_awesome),
        label: Text(casa.plano != null ? 'Ver plano do Eco-Coach' : 'Gerar plano do Eco-Coach'),
      );
    }
    return FilledButton.icon(
      onPressed: _classificando ? null : _classificar,
      icon: _classificando
          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Cores.preto))
          : const Icon(Icons.insights),
      label: const Text('Ver perfil da casa'),
    );
  }

  Widget _vazia() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.home_outlined, size: 64, color: Cores.amarelo),
          SizedBox(height: Espaco.m),
          Text('Sua casa ainda está vazia', style: Estilos.titulo),
          SizedBox(height: Espaco.p),
          Text(
            'Calcule um aparelho e toque em "Adicionar à minha casa". '
            'Com alguns aparelhos, o iamp mostra o total da conta e o perfil de consumo da casa.',
            textAlign: TextAlign.center,
            style: Estilos.corpo,
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
          valor: casa.custoMes,
          formatar: reais,
          rodape: '${reais(casa.custoAno)} por ano · ${numero(total)} kWh/mês',
        ),
        if (casa.tarifasMisturadas)
          const Padding(
            padding: EdgeInsets.only(top: Espaco.p),
            child: ListaAvisos(['Alguns aparelhos foram calculados com tarifas diferentes; o total soma os dois.']),
          ),
        const Titulo('O que mais pesa na conta'),
        for (final item in casa.porCusto) _CartaoItem(item, fracao: total > 0 ? item.kwhMes / total : 0),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _voltarParaBusca,
            icon: const Icon(Icons.add),
            label: const Text('Adicionar outro aparelho'),
          ),
        ),
        const Titulo('Perfil de consumo da casa'),
        const Text(
          'Compara o consumo por morador com milhares de casas simuladas, usando um modelo de '
          'agrupamento (K-Means).',
          style: Estilos.secundario,
        ),
        const SizedBox(height: Espaco.p),
        Card(
          child: Padding(
            padding: const EdgeInsets.only(left: Espaco.m, right: 4),
            child: Row(
              children: [
                const Icon(Icons.people_outline, color: Cores.amarelo),
                const SizedBox(width: 12),
                const Expanded(child: Text('Moradores', style: Estilos.forte)),
                IconButton(
                  tooltip: 'Menos um morador',
                  onPressed: casa.moradores > 1 ? () => casa.mudarMoradores(casa.moradores - 1) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 32,
                  child: Text('${casa.moradores}', style: Estilos.valorMedio, textAlign: TextAlign.center),
                ),
                IconButton(
                  tooltip: 'Mais um morador',
                  onPressed: casa.moradores < 20 ? () => casa.mudarMoradores(casa.moradores + 1) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ),
        ),
        if (_erroPerfil != null) MensagemErro(_erroPerfil!, tentarDeNovo: _classificar),
        if (casa.perfil != null)
          Padding(
            key: _chavePerfil,
            padding: const EdgeInsets.only(top: Espaco.p),
            child: _CartaoPerfil(casa.perfil!, maior: casa.porCusto.first, total: total),
          ),
        const Titulo('Eco-Coach'),
        Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _abrirEcoCoach,
            child: Padding(
              padding: const EdgeInsets.all(Espaco.m),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 32),
                  const SizedBox(width: Espaco.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          casa.plano != null ? 'Seu plano está pronto' : 'Plano de economia com IA',
                          style: Estilos.forte,
                        ),
                        Text(
                          'Dicas oficiais do Inmetro e da Cemig para os aparelhos que mais pesam'
                          '${casa.trocas.isEmpty ? '' : ', incluindo ${casa.trocas.length} troca(s) que você avaliou'}.',
                          style: Estilos.secundario,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Espaco.g),
      ],
    );
  }

  void _abrirEcoCoach() => Navigator.push(context, MaterialPageRoute(builder: (_) => const TelaEcoCoach()));
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
        padding: const EdgeInsets.fromLTRB(Espaco.m, 12, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(iconeDaCategoria(r.categoria), color: Cores.amarelo),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.nome, style: Estilos.forte, maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text(
                        [legivel(r.categoria), if (r.detalhe.isNotEmpty) r.detalhe].join(' - '),
                        style: Estilos.secundario,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Espaco.p),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(reais(item.custoMes), style: Estilos.numero.copyWith(color: Cores.branco)),
                    Text('${numero(item.kwhMes)} kWh', style: Estilos.secundario),
                  ],
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opções',
                  icon: const Icon(Icons.more_vert, color: Cores.amarelo),
                  onSelected: (opcao) {
                    if (opcao == 'remover') casa.remover(item);
                    if (opcao == 'economicos') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TelaSugestoes(consulta: item.consulta, item: item),
                        ),
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
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: fracao),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: v, minHeight: 8),
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${numero(fracao * 100, casas: 0)}%',
                    style: Estilos.secundario,
                    textAlign: TextAlign.end,
                  ),
                ),
                const SizedBox(width: Espaco.p),
                // botoes de quantidade com 48dp de area de toque (padrao do Android)
                IconButton(
                  tooltip: 'Menos um',
                  onPressed: item.quantidade > 1 ? () => casa.mudarQuantidade(item, item.quantidade - 1) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 28,
                  child: Text('${item.quantidade}', style: Estilos.numero, textAlign: TextAlign.center),
                ),
                IconButton(
                  tooltip: 'Mais um',
                  onPressed: () => casa.mudarQuantidade(item, item.quantidade + 1),
                  icon: const Icon(Icons.add_circle_outline),
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

  // verde = bom, amarelo = neutro, vermelho = alerta
  static const _cores = {'Consciente': Cores.verde, 'Moderado': Cores.amarelo, 'Ineficiente': Cores.vermelho};

  static const _nomesFracoes = {
    'frac_chuveiro': 'Chuveiro',
    'frac_ar': 'Ar-condicionado',
    'frac_refrigerador': 'Geladeira',
  };

  @override
  Widget build(BuildContext context) {
    final acima = c.diferencaPercentual > 0;
    final cor = _cores[c.perfil] ?? Cores.amarelo;
    return Container(
      padding: const EdgeInsets.all(Espaco.g),
      decoration: BoxDecoration(
        color: Cores.superficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.7), width: 1.5),
        boxShadow: [BoxShadow(color: cor.withValues(alpha: 0.18), blurRadius: 32, spreadRadius: -4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icones[c.perfil] ?? Icons.insights, color: cor, size: 40),
              const SizedBox(width: Espaco.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Perfil da casa', style: Estilos.rotulo),
                    Text(c.perfil, style: Estilos.valor.copyWith(color: cor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Espaco.m),
          Row(
            children: [
              Expanded(child: CartaoInfo('Por morador', '${numero(c.kwhPorMorador, casas: 1)} kWh/mês')),
              const SizedBox(width: Espaco.p),
              Expanded(child: CartaoInfo('Mediana', '${numero(c.medianaKwhPorMorador, casas: 1)} kWh/mês')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // abaixo da mediana e bom (verde); acima, alerta (vermelho)
              Icon(
                acima ? Icons.arrow_upward : Icons.arrow_downward,
                color: acima ? Cores.vermelho : Cores.verde,
                size: 20,
              ),
              const SizedBox(width: Espaco.p),
              Expanded(child: Text(_primeiraMaiuscula(c.comparacaoTexto))),
            ],
          ),
          const Titulo('Parte do consumo'),
          for (final e in _nomesFracoes.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: Espaco.p),
              child: Row(
                children: [
                  SizedBox(width: 136, child: Text(e.value)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: c.fracoes[e.key] ?? 0, minHeight: 6),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${numero((c.fracoes[e.key] ?? 0) * 100, casas: 0)}%',
                      textAlign: TextAlign.end,
                      style: Estilos.secundario,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Espaco.p),
          Text(
            'O que mais pesa: ${maior.resultado.nome} '
            '(${numero(total > 0 ? maior.kwhMes / total * 100 : 0, casas: 0)}% do consumo). '
            'Veja no menu do item se existe um modelo mais econômico.',
          ),
          const SizedBox(height: Espaco.m),
          ListaAvisos([c.aviso, 'O perfil considera só os aparelhos que você adicionou.']),
        ],
      ),
    );
  }

  static String _primeiraMaiuscula(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
