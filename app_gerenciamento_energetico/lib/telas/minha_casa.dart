import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../idioma.dart';
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
          content: Text(tr('${item.resultado.nome} saiu da sua casa.', '${item.resultado.nome} was removed from your home.')),
          duration: duracaoAviso,
          persist: false,
          action: SnackBarAction(label: tr('Desfazer', 'Undo'), onPressed: () => casa.reinserir(item, posicao)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: casa,
      builder: (context, _) =>
          Pagina(titulo: tr('Minha casa', 'My home'), rodape: _rodape(), filho: casa.vazia ? const _CasaVazia() : _lista()),
    );
  }

  /// Acao principal embaixo: calcular (casa vazia), ver o perfil e, depois do perfil, economizar.
  Widget _rodape() {
    if (casa.vazia) {
      return FilledButton.icon(
        onPressed: () => irPara(Aba.calcular, recomecar: true),
        icon: const Icon(Icons.calculate_outlined),
        label: Text(tr('Calcular um aparelho', 'Calculate an appliance')),
      );
    }
    if (casa.perfil != null) {
      return FilledButton.icon(
        onPressed: () => irPara(Aba.economizar),
        icon: const Icon(Icons.savings_outlined),
        label: Text(tr('Ver como economizar', 'See how to save')),
      );
    }
    return FilledButton.icon(
      onPressed: _classificando ? null : _classificar,
      icon: _classificando
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.insights),
      label: Text(_classificando ? tr('Comparando...', 'Comparing...') : tr('Comparar com outras casas', 'Compare with other homes')),
    );
  }

  Widget _lista() {
    final t = Iamp.de(context);
    final total = casa.kwhMes;
    final n = casa.totalAparelhos;
    return ListView(
      children: [
        CartaoDestaque(
          titulo: tr('Sua conta de luz com estes aparelhos', 'Your electricity bill with these appliances'),
          valor: casa.custoMes,
          formatar: (v) => tr('${reais(v)} por mês', '${reais(v)} per month'),
          rodape: tr(
            '${reais(casa.custoAno)} por ano · $n ${n == 1 ? 'aparelho' : 'aparelhos'}',
            '${reais(casa.custoAno)} per year · $n ${n == 1 ? 'appliance' : 'appliances'}',
          ),
        ),
        Text(
          tr('Consumo de ${numero(total)} kWh por mês.', 'Uses ${numero(total)} kWh per month.'),
          style: t.secundario,
          textAlign: TextAlign.center,
        ),
        if (casa.tarifasMisturadas)
          Padding(
            padding: const EdgeInsets.only(top: Espaco.p),
            child: ListaAvisos([
              tr(
                'Alguns aparelhos foram calculados com tarifas diferentes; o total soma os dois.',
                'Some appliances were calculated with different rates; the total adds them together.',
              ),
            ]),
          ),
        Titulo(tr('O que mais pesa na conta', 'What weighs most on the bill')),
        for (final item in casa.porCusto)
          _CartaoItem(item, fracao: total > 0 ? item.kwhMes / total : 0, aoRemover: () => _remover(item)),
        const SizedBox(height: Espaco.p),
        OutlinedButton.icon(
          onPressed: () => irPara(Aba.calcular, recomecar: true),
          icon: const Icon(Icons.add),
          label: Text(tr('Adicionar outro aparelho', 'Add another appliance')),
        ),
        Titulo(tr('Quantas pessoas moram na casa?', 'How many people live in the home?')),
        Text(
          tr('Usamos para comparar a sua casa com casas parecidas.', 'We use it to compare your home with similar homes.'),
          style: t.secundario,
        ),
        const SizedBox(height: Espaco.p),
        _Contador(
          valor: casa.moradores,
          rotulo: casa.moradores == 1 ? tr('morador', 'resident') : tr('moradores', 'residents'),
          descricao: tr('moradores', 'residents'),
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
            Semantics(
              header: true,
              child: Text(tr('Sua casa ainda está vazia', 'Your home is still empty'), style: t.titulo, textAlign: TextAlign.center),
            ),
            const SizedBox(height: Espaco.p),
            Text(
              tr(
                'Calcule um aparelho e toque em "Adicionar à minha casa". '
                    'Com alguns aparelhos, o Iamp mostra o total da conta e onde dá para economizar.',
                'Calculate an appliance and tap "Add to my home". '
                    'With a few appliances, Iamp shows the bill total and where you can save.',
              ),
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
          tooltip: tr('Diminuir $descricao', 'Decrease $descricao'),
          onPressed: valor > minimo ? () => aoMudar(valor - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        Semantics(
          liveRegion: true,
          child: Text('$valor $rotulo', style: t.numero),
        ),
        IconButton.outlined(
          tooltip: tr('Aumentar $descricao', 'Increase $descricao'),
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
                  Text(tr('${reais(item.custoMes)} por mês', '${reais(item.custoMes)} per month'), style: t.valorMedio),
                  Text(
                    tr('$parte da conta · ${numero(item.kwhMes)} kWh', '$parte of the bill · ${numero(item.kwhMes)} kWh'),
                    style: t.secundario,
                  ),
                  const SizedBox(height: Espaco.p),
                  ExcludeSemantics(child: BarraParte(fracao, descricao: tr('$parte da conta', '$parte of the bill'))),
                ],
              ),
            ),
            const SizedBox(height: Espaco.pm),
            Text(tr('Quantidade', 'Quantity'), style: t.rotulo),
            _Contador(
              valor: item.quantidade,
              rotulo: item.quantidade == 1 ? tr('unidade', 'unit') : tr('unidades', 'units'),
              descricao: tr('a quantidade de ${r.nome}', 'the quantity of ${r.nome}'),
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
                    label: Text(tr('Ver modelos que gastam menos', 'See models that use less')),
                  ),
                if (item.consulta.portatil)
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => TelaDicas(resultado: item.resultado))),
                    icon: const Icon(Icons.tips_and_updates_outlined),
                    label: Text(tr('Como gastar menos', 'How to spend less')),
                  ),
                Semantics(
                  label: tr('Remover ${r.nome} da casa', 'Remove ${r.nome} from the home'),
                  excludeSemantics: true,
                  button: true,
                  onTap: aoRemover,
                  child: TextButton.icon(
                    onPressed: aoRemover,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(tr('Remover', 'Remove')),
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

  static String? _explicacao(String perfil) => switch (perfil) {
    'Consciente' => tr('A sua casa gasta pouco por pessoa.', 'Your home uses little per person.'),
    'Moderado' => tr('A sua casa gasta perto da média por pessoa.', 'Your home uses close to the average per person.'),
    'Ineficiente' => tr('A sua casa gasta mais que a média por pessoa.', 'Your home uses more than the average per person.'),
    _ => null,
  };

  static Map<String, String> get _nomesFracoes => {
    'frac_chuveiro': tr('Chuveiro', 'Electric shower'),
    'frac_ar': tr('Ar-condicionado', 'Air conditioner'),
    'frac_refrigerador': tr('Geladeira', 'Fridge'),
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
                      Text(tr('Perfil da casa', 'Home profile'), style: t.rotulo),
                      Text(nomeDoPerfil(c.perfil), style: t.valor.copyWith(color: cor)),
                      if (_explicacao(c.perfil) case final explicacao?) Text(explicacao, style: t.corpo),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Espaco.m),
          LadoALado(
            CartaoInfo(
              tr('Sua casa, por pessoa', 'Your home, per person'),
              tr('${reais(c.kwhPorMorador * tarifaMedia)} por mês', '${reais(c.kwhPorMorador * tarifaMedia)} per month'),
              detalhe: '${numero(c.kwhPorMorador, casas: 1)} kWh',
            ),
            CartaoInfo(
              tr('Casas parecidas, por pessoa', 'Similar homes, per person'),
              tr('cerca de ${reais(c.medianaKwhPorMorador * tarifaMedia)}', 'about ${reais(c.medianaKwhPorMorador * tarifaMedia)}'),
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
          Titulo(tr('Quanto cada um pesa no consumo', 'How much each one weighs in consumption')),
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
            tr(
              'O que mais pesa: ${maior.resultado.nome} '
                  '(${numero(total > 0 ? maior.kwhMes / total * 100 : 0, casas: 0)}% do consumo). '
                  'Veja no cartão dele se existe um modelo que gasta menos.',
              'What weighs most: ${maior.resultado.nome} '
                  '(${numero(total > 0 ? maior.kwhMes / total * 100 : 0, casas: 0)}% of consumption). '
                  'Check its card to see if there is a model that uses less.',
            ),
            style: t.corpo,
          ),
          const SizedBox(height: Espaco.m),
          ListaAvisos([
            c.aviso,
            tr('O perfil considera só os aparelhos que você adicionou.', 'The profile only counts the appliances you added.'),
          ]),
        ],
      ),
    );
  }

  static String _primeiraMaiuscula(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
