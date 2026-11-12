import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../idioma.dart';
import '../tema.dart';
import 'comum.dart';

/// Aparelho atual x modelo sugerido (POST /comparar). Com o preco digitado, mostra em quanto
/// tempo a troca se paga (payback, calculado na API; o app so mostra).
class CompareScreen extends StatefulWidget {
  final Query query;
  final SuggestedAppliance suggested;
  final ItemHome? item;
  final Result? current;

  const CompareScreen({super.key, required this.query, required this.suggested, this.item, this.current});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  final _price = TextEditingController();
  late Future<Comparison> _comparison;
  bool _calculatingPayback = false;
  String? _priceError;
  bool _done = false; // ja trocou ou adicionou na casa

  @override
  void initState() {
    super.initState();
    _comparison = _compare();
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<Comparison> _compare({double? price}) => widget.query.estimated
      ? Api.compareEstimated(widget.current!, widget.suggested.appliance.id, widget.query.toApi(), newPrice: price)
      : Api.compare(
          widget.query.appliance.id,
          widget.suggested.appliance.id,
          widget.query.toApi(),
          newPrice: price,
        );

  Future<void> _calculatePayback() async {
    final price = readNumber(_price.text);
    if (price == null || price <= 0) {
      setState(() => _priceError = tr('Digite o preço em reais. Ex.: 2.499,90.', 'Enter the price in reais. E.g.: 2,499.90.'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _priceError = null;
      _calculatingPayback = true;
    });
    try {
      // o setState nao pode receber um Future: espera a resposta e so depois troca o estado
      final comparison = await _compare(price: price);
      // o Eco-Coach usa essa troca com os numeros calculados aqui (economia e payback)
      home.registerSwap(
        EvaluatedSwap(
          appliance: '${readable(comparison.current.category)} ${comparison.current.name}',
          alternative: comparison.rewritten.name,
          monthlySavings: comparison.monthlySavings,
          paybackMonths: comparison.payback?.months,
          // o aparelho de "Minha casa" ou o resultado que a pessoa pode adicionar depois (o mesmo objeto)
          current: widget.item?.result ?? widget.current,
        ),
      );
      if (!mounted) return;
      setState(() {
        _comparison = Future.value(comparison);
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _priceError = e.message);
    } finally {
      if (mounted) setState(() => _calculatingPayback = false);
    }
  }

  void _addToHome(Comparison c) {
    final newQuery = widget.query.copy(appliance: widget.suggested.appliance);
    final navigator = Navigator.of(context);
    final notices = ScaffoldMessenger.of(context);
    if (widget.item != null) {
      home.replace(widget.item!, newQuery, c.rewritten);
      navigator.popUntil((route) => route.isFirst); // volta para Minha casa
      notices.showSnackBar(
        SnackBar(content: Text(tr('Trocado por ${c.rewritten.name}.', 'Replaced with ${c.rewritten.name}.')), duration: noticeDuration),
      );
      return;
    }
    home.add(newQuery, c.rewritten);
    setState(() => _done = true);
    notifyAdded(notices, tr('${c.rewritten.name} foi para a sua casa.', '${c.rewritten.name} was added to your home.'));
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return AppPage(
      title: tr('Vale a pena trocar?', 'Is it worth replacing?'),
      footer: FilledButton.icon(
        onPressed: _calculatingPayback ? null : _calculatePayback,
        icon: _calculatingPayback
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.timer_outlined),
        label: Text(
          _calculatingPayback ? tr('Calculando...', 'Calculating...') : tr('Ver em quanto tempo se paga', 'See how long it takes to pay off'),
        ),
      ),
      child: FutureBuilder<Comparison>(
        future: _comparison,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done && !snap.hasData) {
            return Loading(text: tr('Comparando...', 'Comparing...'));
          }
          if (snap.hasError && !snap.hasData) {
            return ErrorMessage(
              snap.error.toString(),
              tryAgain: () => setState(() {
                _comparison = _compare();
              }),
            );
          }
          final c = snap.data!;
          final saves = c.monthlySavings > 0;
          return ListView(
            children: [
              SideBySide(
                _Column(tr('Seu modelo', 'Your model'), c.current, highlight: false),
                _Column(tr('Modelo novo', 'New model'), c.rewritten, highlight: true),
                middle: Padding(
                  padding: const EdgeInsets.all(Spacing.pp),
                  child: Icon(Icons.arrow_forward, color: t.highlight, semanticLabel: tr('trocar por', 'replace with')),
                ),
              ),
              const SizedBox(height: Spacing.p),
              HighlightCard(
                title: saves
                    ? tr('Você economiza por mês', 'You save per month')
                    : tr('Não há economia por mês', 'No savings per month'),
                value: c.monthlySavings,
                format: reais,
                cor: saves ? t.savings : t.alert,
                footer: tr(
                  '${reais(c.yearlySavings)} por ano · ${number(c.monthlySavingsKwh)} kWh a menos por mês',
                  '${reais(c.yearlySavings)} per year · ${number(c.monthlySavingsKwh)} kWh less per month',
                ),
              ),
              SectionTitle(tr('Em quanto tempo a troca se paga?', 'How long until it pays off?')),
              Text(
                tr(
                  'Digite o preço do modelo novo que você encontrou na loja. '
                      'Calculamos em quantos meses a economia na conta paga a compra.',
                  'Enter the price of the new model you found in the store. '
                      'We calculate how many months of bill savings it takes to pay for it.',
                ),
                style: t.secondary,
              ),
              const SizedBox(height: Spacing.pm),
              TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onSubmitted: (_) => _calculatePayback(),
                decoration: InputDecoration(
                  labelText: tr('Preço do modelo novo', 'Price of the new model'),
                  hintText: tr('Ex.: 2.499,90', 'E.g.: 2,499.90'),
                  prefixText: 'R\$ ',
                  errorText: _priceError,
                ),
              ),
              // o resultado aparece com animacao e os meses "contam" ate o valor
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (child, animation) => SizeTransition(
                  sizeFactor: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: c.payback == null
                    ? const SizedBox.shrink()
                    : Padding(
                        key: ValueKey(c.payback!.newPrice),
                        padding: const EdgeInsets.only(top: Spacing.m),
                        child: PaybackCard(c.payback!),
                      ),
              ),
              const SizedBox(height: Spacing.g),
              if (!_done)
                OutlinedButton.icon(
                  onPressed: () => _addToHome(c),
                  icon: Icon(widget.item != null ? Icons.swap_horiz : Icons.add_home_outlined),
                  label: Text(
                    widget.item != null
                        ? tr('Trocar na minha casa', 'Replace it in my home')
                        : tr('Adicionar este modelo à minha casa', 'Add this model to my home'),
                  ),
                ),
              const SizedBox(height: Spacing.m),
              NoticeList(c.notices),
            ],
          );
        },
      ),
    );
  }
}

class _Column extends StatelessWidget {
  final String title;
  final Result r;
  final bool highlight;

  const _Column(this.title, this.r, {required this.highlight});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return MergeSemantics(
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radius),
          side: BorderSide(color: highlight ? t.savings : t.border, width: highlight ? 2 : 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.pm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.label.copyWith(color: highlight ? t.savings : t.secondaryText)),
              const SizedBox(height: Spacing.pp),
              Text(r.name, style: t.strong, maxLines: 3, overflow: TextOverflow.ellipsis),
              if (r.detail.isNotEmpty) Text(r.detail, style: t.secondary),
              const SizedBox(height: Spacing.p),
              Text(reais(r.monthlyCost), style: t.averageValue),
              Text(tr('por mês · ${number(r.monthlyKwh)} kWh', 'per month · ${number(r.monthlyKwh)} kWh'), style: t.secondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Em quanto tempo a troca se paga. A cor (verde ate 5 anos, amarelo acima, vermelho se nao se paga)
/// sempre vem com uma frase que diz a mesma coisa. 5 anos e um corte do grupo, nao uma regra oficial.
class PaybackCard extends StatelessWidget {
  final Payback p;

  const PaybackCard(this.p, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final months = p.months;
    final (cor, verdict, icon) = months == null
        ? (t.alert, tr('Não se paga', 'Does not pay off'), Icons.money_off)
        : months <= 60
        ? (t.savings, tr('Se paga rápido', 'Pays off quickly'), Icons.savings_outlined)
        : (t.highlight, tr('Demora para se pagar', 'Takes a long time to pay off'), Icons.hourglass_bottom);
    return MergeSemantics(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Spacing.g),
        decoration: t.highlightCard(cor),
        child: Column(
          children: [
            Icon(icon, color: cor, size: t.largeIcon),
            const SizedBox(height: Spacing.p),
            Text(verdict, style: t.title.copyWith(color: cor), textAlign: TextAlign.center),
            const SizedBox(height: Spacing.pp),
            if (months != null) ...[
              if (months < 1)
                Text(
                  tr('em menos de 1 mês', 'in less than 1 month'),
                  style: t.value.copyWith(color: cor),
                  textAlign: TextAlign.center,
                )
              else
                AnimatedValue(
                  months,
                  format: (v) => tr('em ${number(v, homes: 0)} meses', 'in ${number(v, homes: 0)} months'),
                  style: t.value.copyWith(color: cor),
                ),
              if (p.years != null && months >= 12)
                Text(tr('cerca de ${number(p.years!, homes: 1)} anos', 'about ${number(p.years!, homes: 1)} years'), style: t.strong),
              const SizedBox(height: Spacing.p),
            ],
            Text(p.text, textAlign: TextAlign.center, style: t.body),
            const SizedBox(height: Spacing.pp),
            Text(
              tr('Preço considerado: ${reais(p.newPrice)}', 'Price used: ${reais(p.newPrice)}'),
              style: t.secondary,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
