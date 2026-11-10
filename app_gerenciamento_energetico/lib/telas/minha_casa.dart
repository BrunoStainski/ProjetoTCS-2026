import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../navegacao.dart';
import '../tema.dart';
import 'comum.dart';
import 'dicas.dart';
import 'sugestoes.dart';

/// Aba "Minha casa": soma os aparelhos calculados, mostra o que mais pesa na conta
/// e compara a casa com casas parecidas (perfil de consumo, POST /classificar).
class TelaMinhaCasa extends StatefulWidget {
  const TelaMinhaCasa({super.key});

  @override
  State<TelaMinhaCasa> createState() => _TelaMinhaCasaState();
}

class _TelaMinhaCasaState extends State<TelaMinhaCasa> {
  bool _classificando = false;
  String? _erroPerfil;
  final _chavePerfil = GlobalKey();

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

  void _remover(ItemCasa item) {
    final avisos = ScaffoldMessenger.of(context);
    final posicao = casa.remover(item);
    avisos
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${item.resultado.nome} saiu da sua casa.'),
          duration: duracaoAviso,
          persist: false,
          action: SnackBarAction(label: 'Desfazer', onPressed: () => casa.reinserir(item, posicao)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: casa,
      builder: (context, _) =>
          Pagina(titulo: 'Minha casa', rodape: _rodape(), filho: casa.vazia ? const _CasaVazia() : _lista()),
    );
  }

  /// Acao principal embaixo: calcular (casa vazia), ver o perfil e, depois do perfil, economizar.
  Widget _rodape() {
    if (casa.vazia) {
      return FilledButton.icon(
        onPressed: () => irPara(Aba.calcular, recomecar: true),
        icon: const Icon(Icons.calculate_outlined),
        label: const Text('Calcular um aparelho'),
      );
    }
    if (casa.perfil != null) {
      return FilledButton.icon(
        onPressed: () => irPara(Aba.economizar),
        icon: const Icon(Icons.savings_outlined),
        label: const Text('Ver como economizar'),
      );
    }
    return FilledButton.icon(
      onPressed: _classificando ? null : _classificar,
      icon: _classificando
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.insights),
      label: Text(_classificando ? 'Comparando...' : 'Comparar com outras casas'),
    );
  }

  Widget _lista() {
    final t = Iamp.de(context);
    final total = casa.kwhMes;
    final n = casa.totalAparelhos;
    return ListView(
      children: [
        CartaoDestaque(
          titulo: 'Sua conta de luz com estes aparelhos',
          valor: casa.custoMes,
          formatar: (v) => '${reais(v)} por mês',
          rodape: '${reais(casa.custoAno)} por ano · $n ${n == 1 ? 'aparelho' : 'aparelhos'}',
        ),
        Text(
          'Consumo de ${numero(total)} kWh por mês.',
          style: t.secundario,
          textAlign: TextAlign.center,
        ),
        if (casa.tarifasMisturadas)
          const Padding(
            padding: EdgeInsets.only(top: Espaco.p),
            child: ListaAvisos(['Alguns aparelhos foram calculados com tarifas diferentes; o total soma os dois.']),
          ),
        const Titulo('O que mais pesa na conta'),
        for (final item in casa.porCusto)
          _CartaoItem(item, fracao: total > 0 ? item.kwhMes / total : 0, aoRemover: () => _remover(item)),
        const SizedBox(height: Espaco.p),
        OutlinedButton.icon(
          onPressed: () => irPara(Aba.calcular, recomecar: true),
          icon: const Icon(Icons.add),
          label: const Text('Adicionar outro aparelho'),
        ),
        const Titulo('Quantas pessoas moram na casa?'),
        Text('Usamos para comparar a sua casa com casas parecidas.', style: t.secundario),
        const SizedBox(height: Espaco.p),
        _Contador(
          valor: casa.moradores,
          rotulo: casa.moradores == 1 ? 'morador' : 'moradores',
          descricao: 'moradores',
          minimo: 1,
          maximo: 20,
          aoMudar: casa.mudarMoradores,
        ),
        if (_erroPerfil != null) MensagemErro(_erroPerfil!, tentarDeNovo: _classificar),
        if (casa.perfil != null)
          Padding(
            key: _chavePerfil,
            padding: const EdgeInsets.only(top: Espaco.m),
            child: _CartaoPerfil(casa.perfil!, maior: casa.porCusto.first, total: total),
          ),
        const SizedBox(height: Espaco.g),
      ],
    );
  }
}

class _CasaVazia extends StatelessWidget {
  const _CasaVazia();

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_outlined, size: t.iconeEnorme),
            const SizedBox(height: Espaco.m),
            Semantics(header: true, child: Text('Sua casa ainda está vazia', style: t.titulo, textAlign: TextAlign.center)),
            const SizedBox(height: Espaco.p),
            Text(
              'Calcule um aparelho e toque em "Adicionar à minha casa". '
              'Com alguns aparelhos, o Iamp mostra o total da conta e onde dá para economizar.',
              textAlign: TextAlign.center,
              style: t.corpo,
            ),
          ],
        ),
      ),
    );
  }
}

/// Botoes - e + com o numero no meio. Cada botao diz ao leitor de tela o que muda.
class _Contador extends StatelessWidget {
  final int valor;
  final String rotulo;
  final String descricao;
  final int minimo;
  final int maximo;
  final void Function(int) aoMudar;

  const _Contador({
    required this.valor,
    required this.rotulo,
    required this.descricao,
    required this.minimo,
    required this.maximo,
    required this.aoMudar,
  });

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Espaco.p,
      children: [
        IconButton.outlined(
          tooltip: 'Diminuir $descricao',
          onPressed: valor > minimo ? () => aoMudar(valor - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        Semantics(
          liveRegion: true,
          child: Text('$valor $rotulo', style: t.numero),
        ),
        IconButton.outlined(
          tooltip: 'Aumentar $descricao',
          onPressed: valor < maximo ? () => aoMudar(valor + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

class _CartaoItem extends StatelessWidget {
  final ItemCasa item;
  final double fracao;
  final VoidCallback aoRemover;

  const _CartaoItem(this.item, {required this.fracao, required this.aoRemover});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final r = item.resultado;
    final parte = '${numero(fracao * 100, casas: 0)}%';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Espaco.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // o leitor de tela le o resumo inteiro de uma vez: nome, valor e parte da conta
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(iconeDaCategoria(r.categoria), size: t.iconeGrande),
                      const SizedBox(width: Espaco.pm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.nome, style: t.forte, maxLines: 3, overflow: TextOverflow.ellipsis),
                            Text(
                              [nomeDaCategoria(r.categoria), if (r.detalhe.isNotEmpty) r.detalhe].join(' · '),
                              style: t.secundario,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Espaco.pm),
                  Text('${reais(item.custoMes)} por mês', style: t.valorMedio),
                  Text('$parte da conta · ${numero(item.kwhMes)} kWh', style: t.secundario),
                  const SizedBox(height: Espaco.p),
                  ExcludeSemantics(child: BarraParte(fracao, descricao: '$parte da conta')),
                ],
              ),
            ),
            const SizedBox(height: Espaco.pm),
            Text('Quantidade', style: t.rotulo),
            _Contador(
              valor: item.quantidade,
              rotulo: item.quantidade == 1 ? 'unidade' : 'unidades',
              descricao: 'a quantidade de ${r.nome}',
              minimo: 1,
              maximo: 99,
              aoMudar: (q) => casa.mudarQuantidade(item, q),
            ),
            const Divider(height: Espaco.g),
            Wrap(
              spacing: Espaco.p,
              runSpacing: Espaco.p,
              children: [
                if (!item.consulta.portatil)
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TelaSugestoes(consulta: item.consulta, item: item, atual: item.resultado),
                      ),
                    ),
                    icon: const Icon(Icons.trending_down),
                    label: const Text('Ver modelos que gastam menos'),
                  ),
                if (item.consulta.portatil)
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => TelaDicas(resultado: item.resultado))),
                    icon: const Icon(Icons.tips_and_updates_outlined),
                    label: const Text('Como gastar menos'),
                  ),
                Semantics(
                  label: 'Remover ${r.nome} da casa',
                  excludeSemantics: true,
                  button: true,
                  onTap: aoRemover,
                  child: TextButton.icon(
                    onPressed: aoRemover,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remover'),
                  ),
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

  static const _explicacao = {
    'Consciente': 'A sua casa gasta pouco por pessoa.',
    'Moderado': 'A sua casa gasta perto da média por pessoa.',
    'Ineficiente': 'A sua casa gasta mais que a média por pessoa.',
  };

  static const _nomesFracoes = {
    'frac_chuveiro': 'Chuveiro',
    'frac_ar': 'Ar-condicionado',
    'frac_refrigerador': 'Geladeira',
  };

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    // verde = bom, amarelo = neutro, vermelho = alerta (sempre com o nome e um icone diferente)
    final cor = switch (c.perfil) {
      'Consciente' => t.economia,
      'Ineficiente' => t.alerta,
      _ => t.destaque,
    };
    final acima = c.diferencaPercentual > 0;
    // a tarifa media da casa transforma o kWh por morador em reais
    final tarifaMedia = total > 0 ? casa.custoMes / total : 0.0;
    return Container(
      padding: const EdgeInsets.all(Espaco.g),
      decoration: t.cartaoDestaque(cor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                Icon(_icones[c.perfil] ?? Icons.insights, color: cor, size: t.iconeGrande + 8),
                const SizedBox(width: Espaco.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Perfil da casa', style: t.rotulo),
                      Text(c.perfil, style: t.valor.copyWith(color: cor)),
                      if (_explicacao[c.perfil] != null) Text(_explicacao[c.perfil]!, style: t.corpo),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Espaco.m),
          LadoALado(
            CartaoInfo(
              'Sua casa, por pessoa',
              '${reais(c.kwhPorMorador * tarifaMedia)} por mês',
              detalhe: '${numero(c.kwhPorMorador, casas: 1)} kWh',
            ),
            CartaoInfo(
              'Casas parecidas, por pessoa',
              'cerca de ${reais(c.medianaKwhPorMorador * tarifaMedia)}',
              detalhe: '${numero(c.medianaKwhPorMorador, casas: 1)} kWh',
            ),
          ),
          const SizedBox(height: Espaco.pm),
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // a seta muda junto com a cor: acima da media = para cima
                Icon(acima ? Icons.arrow_upward : Icons.arrow_downward, color: acima ? t.alerta : t.economia),
                const SizedBox(width: Espaco.p),
                Expanded(child: Text(_primeiraMaiuscula(c.comparacaoTexto), style: t.corpo)),
              ],
            ),
          ),
          const Titulo('Quanto cada um pesa no consumo'),
          for (final e in _nomesFracoes.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: Espaco.pm),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${e.value}: ${numero((c.fracoes[e.key] ?? 0) * 100, casas: 0)}%', style: t.corpo),
                    const SizedBox(height: Espaco.pp),
                    ExcludeSemantics(child: BarraParte(c.fracoes[e.key] ?? 0, descricao: e.value)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Espaco.p),
          Text(
            'O que mais pesa: ${maior.resultado.nome} '
            '(${numero(total > 0 ? maior.kwhMes / total * 100 : 0, casas: 0)}% do consumo). '
            'Veja no cartão dele se existe um modelo que gasta menos.',
            style: t.corpo,
          ),
          const SizedBox(height: Espaco.m),
          ListaAvisos([c.aviso, 'O perfil considera só os aparelhos que você adicionou.']),
        ],
      ),
    );
  }

  static String _primeiraMaiuscula(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
