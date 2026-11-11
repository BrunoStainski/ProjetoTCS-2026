import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../idioma.dart';
import '../tema.dart';
import 'comum.dart';

/// Aparelho atual x modelo sugerido (POST /comparar). Com o preco digitado, mostra em quanto
/// tempo a troca se paga (payback, calculado na API; o app so mostra).
class TelaComparar extends StatefulWidget {
  final Consulta consulta;
  final AparelhoSugerido sugerido;
  final ItemCasa? item;
  final Resultado? atual;

  const TelaComparar({super.key, required this.consulta, required this.sugerido, this.item, this.atual});

  @override
  State<TelaComparar> createState() => _TelaCompararState();
}

class _TelaCompararState extends State<TelaComparar> {
  final _preco = TextEditingController();
  late Future<Comparacao> _comparacao;
  bool _calculandoPayback = false;
  String? _erroPreco;
  bool _feito = false; // ja trocou ou adicionou na casa

  @override
  void initState() {
    super.initState();
    _comparacao = _comparar();
  }

  @override
  void dispose() {
    _preco.dispose();
    super.dispose();
  }

  Future<Comparacao> _comparar({double? preco}) => widget.consulta.estimado
      ? Api.compararEstimado(widget.atual!, widget.sugerido.aparelho.id, widget.consulta.paraApi(), precoNovo: preco)
      : Api.comparar(
          widget.consulta.aparelho.id,
          widget.sugerido.aparelho.id,
          widget.consulta.paraApi(),
          precoNovo: preco,
        );

  Future<void> _calcularPayback() async {
    final preco = lerNumero(_preco.text);
    if (preco == null || preco <= 0) {
      setState(() => _erroPreco = tr('Digite o preço em reais. Ex.: 2.499,90.', 'Enter the price in reais. E.g.: 2,499.90.'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _erroPreco = null;
      _calculandoPayback = true;
    });
    try {
      // o setState nao pode receber um Future: espera a resposta e so depois troca o estado
      final comparacao = await _comparar(preco: preco);
      // o Eco-Coach usa essa troca com os numeros calculados aqui (economia e payback)
      casa.registrarTroca(
        TrocaAvaliada(
          aparelho: '${legivel(comparacao.atual.categoria)} ${comparacao.atual.nome}',
          alternativa: comparacao.novo.nome,
          economiaMes: comparacao.economiaMes,
          paybackMeses: comparacao.payback?.meses,
        ),
      );
      if (!mounted) return;
      setState(() {
        _comparacao = Future.value(comparacao);
      });
    } on ApiErro catch (e) {
      if (mounted) setState(() => _erroPreco = e.mensagem);
    } finally {
      if (mounted) setState(() => _calculandoPayback = false);
    }
  }

  void _levarParaCasa(Comparacao c) {
    final nova = widget.consulta.copiar(aparelho: widget.sugerido.aparelho);
    final navegador = Navigator.of(context);
    final avisos = ScaffoldMessenger.of(context);
    if (widget.item != null) {
      casa.trocar(widget.item!, nova, c.novo);
      navegador.popUntil((rota) => rota.isFirst); // volta para Minha casa
      avisos.showSnackBar(
        SnackBar(content: Text(tr('Trocado por ${c.novo.nome}.', 'Replaced with ${c.novo.nome}.')), duration: duracaoAviso),
      );
      return;
    }
    casa.adicionar(nova, c.novo);
    setState(() => _feito = true);
    avisarAdicionado(avisos, tr('${c.novo.nome} foi para a sua casa.', '${c.novo.nome} was added to your home.'));
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Pagina(
      titulo: tr('Vale a pena trocar?', 'Is it worth replacing?'),
      rodape: FilledButton.icon(
        onPressed: _calculandoPayback ? null : _calcularPayback,
        icon: _calculandoPayback
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.timer_outlined),
        label: Text(
          _calculandoPayback ? tr('Calculando...', 'Calculating...') : tr('Ver em quanto tempo se paga', 'See how long it takes to pay off'),
        ),
      ),
      filho: FutureBuilder<Comparacao>(
        future: _comparacao,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done && !snap.hasData) {
            return Carregando(texto: tr('Comparando...', 'Comparing...'));
          }
          if (snap.hasError && !snap.hasData) {
            return MensagemErro(
              snap.error.toString(),
              tentarDeNovo: () => setState(() {
                _comparacao = _comparar();
              }),
            );
          }
          final c = snap.data!;
          final economiza = c.economiaMes > 0;
          return ListView(
            children: [
              LadoALado(
                _Coluna(tr('Seu modelo', 'Your model'), c.atual, destaque: false),
                _Coluna(tr('Modelo novo', 'New model'), c.novo, destaque: true),
                meio: Padding(
                  padding: const EdgeInsets.all(Espaco.pp),
                  child: Icon(Icons.arrow_forward, color: t.destaque, semanticLabel: tr('trocar por', 'replace with')),
                ),
              ),
              const SizedBox(height: Espaco.p),
              CartaoDestaque(
                titulo: economiza
                    ? tr('Você economiza por mês', 'You save per month')
                    : tr('Não há economia por mês', 'No savings per month'),
                valor: c.economiaMes,
                formatar: reais,
                cor: economiza ? t.economia : t.alerta,
                rodape: tr(
                  '${reais(c.economiaAno)} por ano · ${numero(c.economiaKwhMes)} kWh a menos por mês',
                  '${reais(c.economiaAno)} per year · ${numero(c.economiaKwhMes)} kWh less per month',
                ),
              ),
              Titulo(tr('Em quanto tempo a troca se paga?', 'How long until it pays off?')),
              Text(
                tr(
                  'Digite o preço do modelo novo que você encontrou na loja. '
                      'Calculamos em quantos meses a economia na conta paga a compra.',
                  'Enter the price of the new model you found in the store. '
                      'We calculate how many months of bill savings it takes to pay for it.',
                ),
                style: t.secundario,
              ),
              const SizedBox(height: Espaco.pm),
              TextField(
                controller: _preco,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onSubmitted: (_) => _calcularPayback(),
                decoration: InputDecoration(
                  labelText: tr('Preço do modelo novo', 'Price of the new model'),
                  hintText: tr('Ex.: 2.499,90', 'E.g.: 2,499.90'),
                  prefixText: 'R\$ ',
                  errorText: _erroPreco,
                ),
              ),
              // o resultado aparece com animacao e os meses "contam" ate o valor
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (filho, animacao) => SizeTransition(
                  sizeFactor: animacao,
                  child: FadeTransition(opacity: animacao, child: filho),
                ),
                child: c.payback == null
                    ? const SizedBox.shrink()
                    : Padding(
                        key: ValueKey(c.payback!.precoNovo),
                        padding: const EdgeInsets.only(top: Espaco.m),
                        child: CartaoPayback(c.payback!),
                      ),
              ),
              const SizedBox(height: Espaco.g),
              if (!_feito)
                OutlinedButton.icon(
                  onPressed: () => _levarParaCasa(c),
                  icon: Icon(widget.item != null ? Icons.swap_horiz : Icons.add_home_outlined),
                  label: Text(
                    widget.item != null
                        ? tr('Trocar na minha casa', 'Replace it in my home')
                        : tr('Adicionar este modelo à minha casa', 'Add this model to my home'),
                  ),
                ),
              const SizedBox(height: Espaco.m),
              ListaAvisos(c.avisos),
            ],
          );
        },
      ),
    );
  }
}

class _Coluna extends StatelessWidget {
  final String titulo;
  final Resultado r;
  final bool destaque;

  const _Coluna(this.titulo, this.r, {required this.destaque});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return MergeSemantics(
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.raio),
          side: BorderSide(color: destaque ? t.economia : t.borda, width: destaque ? 2 : 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Espaco.pm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: t.rotulo.copyWith(color: destaque ? t.economia : t.textoSecundario)),
              const SizedBox(height: Espaco.pp),
              Text(r.nome, style: t.forte, maxLines: 3, overflow: TextOverflow.ellipsis),
              if (r.detalhe.isNotEmpty) Text(r.detalhe, style: t.secundario),
              const SizedBox(height: Espaco.p),
              Text(reais(r.custoMes), style: t.valorMedio),
              Text(tr('por mês · ${numero(r.kwhMes)} kWh', 'per month · ${numero(r.kwhMes)} kWh'), style: t.secundario),
            ],
          ),
        ),
      ),
    );
  }
}

/// Em quanto tempo a troca se paga. A cor (verde ate 5 anos, amarelo acima, vermelho se nao se paga)
/// sempre vem com uma frase que diz a mesma coisa. 5 anos e um corte do grupo, nao uma regra oficial.
class CartaoPayback extends StatelessWidget {
  final Payback p;

  const CartaoPayback(this.p, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final meses = p.meses;
    final (cor, veredito, icone) = meses == null
        ? (t.alerta, tr('Não se paga', 'Does not pay off'), Icons.money_off)
        : meses <= 60
        ? (t.economia, tr('Se paga rápido', 'Pays off quickly'), Icons.savings_outlined)
        : (t.destaque, tr('Demora para se pagar', 'Takes a long time to pay off'), Icons.hourglass_bottom);
    return MergeSemantics(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Espaco.g),
        decoration: t.cartaoDestaque(cor),
        child: Column(
          children: [
            Icon(icone, color: cor, size: t.iconeGrande),
            const SizedBox(height: Espaco.p),
            Text(veredito, style: t.titulo.copyWith(color: cor), textAlign: TextAlign.center),
            const SizedBox(height: Espaco.pp),
            if (meses != null) ...[
              if (meses < 1)
                Text(
                  tr('em menos de 1 mês', 'in less than 1 month'),
                  style: t.valor.copyWith(color: cor),
                  textAlign: TextAlign.center,
                )
              else
                ValorAnimado(
                  meses,
                  formatar: (v) => tr('em ${numero(v, casas: 0)} meses', 'in ${numero(v, casas: 0)} months'),
                  estilo: t.valor.copyWith(color: cor),
                ),
              if (p.anos != null && meses >= 12)
                Text(tr('cerca de ${numero(p.anos!, casas: 1)} anos', 'about ${numero(p.anos!, casas: 1)} years'), style: t.forte),
              const SizedBox(height: Espaco.p),
            ],
            Text(p.texto, textAlign: TextAlign.center, style: t.corpo),
            const SizedBox(height: Espaco.pp),
            Text(
              tr('Preço considerado: ${reais(p.precoNovo)}', 'Price used: ${reais(p.precoNovo)}'),
              style: t.secundario,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
