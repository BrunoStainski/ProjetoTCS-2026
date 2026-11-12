// Tarifa de energia, uma decisao por tela:
// etapa 4 (StateScreen): o estado, ou usar a mesma tarifa de antes;
// etapa 5 (DistributorScreen): a distribuidora do estado;
// opcional (BillTariffScreen): digitar a tarifa que esta na conta de luz.

import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../idioma.dart';
import '../tema.dart';
import 'comum.dart';
import 'resultado.dart';

const stateNames = {
  'AC': 'Acre',
  'AL': 'Alagoas',
  'AM': 'Amazonas',
  'AP': 'Amapá',
  'BA': 'Bahia',
  'CE': 'Ceará',
  'DF': 'Distrito Federal',
  'ES': 'Espírito Santo',
  'GO': 'Goiás',
  'MA': 'Maranhão',
  'MG': 'Minas Gerais',
  'MS': 'Mato Grosso do Sul',
  'MT': 'Mato Grosso',
  'PA': 'Pará',
  'PB': 'Paraíba',
  'PE': 'Pernambuco',
  'PI': 'Piauí',
  'PR': 'Paraná',
  'RJ': 'Rio de Janeiro',
  'RN': 'Rio Grande do Norte',
  'RO': 'Rondônia',
  'RR': 'Roraima',
  'RS': 'Rio Grande do Sul',
  'SC': 'Santa Catarina',
  'SE': 'Sergipe',
  'SP': 'São Paulo',
  'TO': 'Tocantins',
};

/// Calcula com a tarifa escolhida e abre o resultado.
void calculateWith(BuildContext context, Query query, TariffChoice tariff) {
  query.tariff = tariff;
  home.rememberTariff(tariff);
  Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(query: query)));
}

/// Etapa 4: em qual estado a pessoa mora (ou a mesma tarifa da ultima vez).
class StateScreen extends StatefulWidget {
  final Query query;

  const StateScreen({super.key, required this.query});

  @override
  State<StateScreen> createState() => _StateScreenState();
}

class _StateScreenState extends State<StateScreen> {
  late Future<List<String>> _ufs;

  @override
  void initState() {
    super.initState();
    _ufs = Api.ufs();
  }

  void _choose(String uf) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => DistributorScreen(query: widget.query, uf: uf)));
  }

  void _typeTariff() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => BillTariffScreen(query: widget.query)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final last = home.lastTariff;
    return AppPage(
      title: tr('Sua energia', 'Your electricity'),
      step: calculationStep(widget.query, 4),
      child: ListView(
        children: [
          if (last != null) ...[
            QuestionHeader(tr('Usar a mesma conta de luz de antes?', 'Use the same electricity bill as before?')),
            OptionCard(
              icon: Icons.bolt,
              title: tr('Sim, usar ${last.description}', 'Yes, use ${last.description}'),
              subtitle: tr(
                'Tarifa de ${reais(last.tariffKwh, homes: 4)} por kWh',
                'Rate of ${reais(last.tariffKwh, homes: 4)} per kWh',
              ),
              onTap: () => calculateWith(context, widget.query, last),
            ),
            const SizedBox(height: Spacing.m),
            Text(tr('Ou escolha outro estado:', 'Or pick another state:'), style: t.strong),
            const SizedBox(height: Spacing.p),
          ] else
            QuestionHeader(
              tr('Em qual estado você mora?', 'Which Brazilian state do you live in?'),
              help: tr(
                'Assim achamos a sua distribuidora de energia e o preço do kWh.',
                'This is how we find your power company and the price of a kWh.',
              ),
            ),
          FutureBuilder<List<String>>(
            future: _ufs,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Loading(text: tr('Carregando os estados...', 'Loading states...'));
              }
              if (snap.hasError) {
                return ErrorMessage(
                  snap.error.toString(),
                  tryAgain: () => setState(() {
                    _ufs = Api.ufs();
                  }),
                );
              }
              final ufs = [...snap.data!]..sort((a, b) => (stateNames[a] ?? a).compareTo(stateNames[b] ?? b));
              return Column(
                children: [
                  for (final uf in ufs)
                    OptionCard(title: stateNames[uf] ?? uf, subtitle: uf, onTap: () => _choose(uf)),
                ],
              );
            },
          ),
          const SizedBox(height: Spacing.m),
          OptionCard(
            icon: Icons.receipt_long,
            title: tr('Prefiro digitar a tarifa da minha conta', "I'd rather type the rate from my bill"),
            subtitle: tr('Se você tem a conta de luz em mãos.', 'If you have your electricity bill at hand.'),
            onTap: _typeTariff,
          ),
        ],
      ),
    );
  }
}

/// Etapa 5: qual distribuidora atende a casa (aparece na conta de luz).
class DistributorScreen extends StatefulWidget {
  final Query query;
  final String uf;

  const DistributorScreen({super.key, required this.query, required this.uf});

  @override
  State<DistributorScreen> createState() => _DistributorScreenState();
}

class _DistributorScreenState extends State<DistributorScreen> {
  final _filter = TextEditingController();
  late Future<List<Distributor>> _distributors;

  @override
  void initState() {
    super.initState();
    _distributors = Api.distributors(uf: widget.uf);
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<Distributor> _filtered(List<Distributor> itemList) {
    final target = _filter.text.trim().toLowerCase();
    return target.isEmpty ? itemList : itemList.where((d) => d.name.toLowerCase().contains(target)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return AppPage(
      title: stateNames[widget.uf] ?? widget.uf,
      step: calculationStep(widget.query, 5),
      child: FutureBuilder<List<Distributor>>(
        future: _distributors,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Loading(text: tr('Carregando as distribuidoras...', 'Loading power companies...'));
          }
          if (snap.hasError) {
            return ErrorMessage(
              snap.error.toString(),
              tryAgain: () => setState(() {
                _distributors = Api.distributors(uf: widget.uf);
              }),
            );
          }
          final all = snap.data!;
          final itemList = _filtered(all);
          return ListView(
            children: [
              QuestionHeader(
                tr('Qual é a sua distribuidora de energia?', 'Which is your power company?'),
                help: tr(
                  'É a empresa que manda a conta de luz. O nome aparece no alto da conta.',
                  'It is the company that sends your electricity bill. Its name is at the top of the bill.',
                ),
              ),
              if (all.length > 5) ...[
                TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: tr('Procurar pelo nome', 'Search by name'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: Spacing.p),
              ],
              if (itemList.isEmpty) Text(tr('Nenhuma distribuidora com esse nome.', 'No power company with that name.'), style: t.body),
              for (final d in itemList)
                OptionCard(
                  title: d.name,
                  subtitle: tr(
                    'Tarifa de ${reais(d.tariffKwh, homes: 4)} por kWh',
                    'Rate of ${reais(d.tariffKwh, homes: 4)} per kWh',
                  ),
                  onTap: () => calculateWith(context, widget.query, TariffChoice.fromDistributor(d)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Tarifa digitada a partir da conta de luz.
class BillTariffScreen extends StatefulWidget {
  final Query query;

  const BillTariffScreen({super.key, required this.query});

  @override
  State<BillTariffScreen> createState() => _BillTariffScreenState();
}

class _BillTariffScreenState extends State<BillTariffScreen> {
  final _tariff = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _tariff.dispose();
    super.dispose();
  }

  void _calculate() {
    final tariff = readNumber(_tariff.text);
    if (tariff == null || tariff <= 0 || tariff > 10) {
      setState(() => _error = tr('Informe o valor em reais por kWh. Ex.: 0,85.', 'Enter the price in reais per kWh. E.g.: 0.85.'));
      return;
    }
    setState(() => _error = null);
    calculateWith(context, widget.query, TariffChoice.manual(tariff));
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: tr('Tarifa da conta', 'Rate from your bill'),
      step: calculationStep(widget.query, 5),
      footer: FilledButton(onPressed: _calculate, child: Text(tr('Calcular', 'Calculate'))),
      child: ListView(
        children: [
          QuestionHeader(
            tr('Quanto custa o kWh na sua conta?', 'How much does a kWh cost on your bill?'),
            help: tr(
              'Divida o valor total da conta pelo consumo do mês em kWh. '
                  'Ex.: R\$ 170,00 ÷ 200 kWh = 0,85.',
              "Divide the bill's total by the month's consumption in kWh. "
                  'E.g.: R\$ 170.00 ÷ 200 kWh = 0.85.',
            ),
          ),
          TextField(
            controller: _tariff,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onSubmitted: (_) => _calculate(),
            decoration: InputDecoration(
              labelText: tr('Reais por kWh', 'Reais (R\$) per kWh'),
              hintText: tr('Ex.: 0,85', 'E.g.: 0.85'),
              prefixText: 'R\$ ',
              errorText: _error,
            ),
          ),
        ],
      ),
    );
  }
}
