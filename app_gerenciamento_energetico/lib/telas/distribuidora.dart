// Tarifa de energia, uma decisao por tela:
// etapa 4 (TelaEstado): o estado, ou usar a mesma tarifa de antes;
// etapa 5 (TelaDistribuidora): a distribuidora do estado;
// opcional (TelaTarifaConta): digitar a tarifa que esta na conta de luz.

import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../idioma.dart';
import '../tema.dart';
import 'comum.dart';
import 'resultado.dart';

const nomesDosEstados = {
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
void calcularCom(BuildContext context, Consulta consulta, EscolhaTarifa tarifa) {
  consulta.tarifa = tarifa;
  casa.lembrarTarifa(tarifa);
  Navigator.push(context, MaterialPageRoute(builder: (_) => TelaResultado(consulta: consulta)));
}

/// Etapa 4: em qual estado a pessoa mora (ou a mesma tarifa da ultima vez).
class TelaEstado extends StatefulWidget {
  final Consulta consulta;

  const TelaEstado({super.key, required this.consulta});

  @override
  State<TelaEstado> createState() => _TelaEstadoState();
}

class _TelaEstadoState extends State<TelaEstado> {
  late Future<List<String>> _ufs;

  @override
  void initState() {
    super.initState();
    _ufs = Api.ufs();
  }

  void _escolher(String uf) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => TelaDistribuidora(consulta: widget.consulta, uf: uf)));
  }

  void _digitarTarifa() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => TelaTarifaConta(consulta: widget.consulta)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final ultima = casa.ultimaTarifa;
    return Pagina(
      titulo: tr('Sua energia', 'Your electricity'),
      etapa: etapaDoCalculo(widget.consulta, 4),
      filho: ListView(
        children: [
          if (ultima != null) ...[
            CabecalhoPergunta(tr('Usar a mesma conta de luz de antes?', 'Use the same electricity bill as before?')),
            CartaoOpcao(
              icone: Icons.bolt,
              titulo: tr('Sim, usar ${ultima.descricao}', 'Yes, use ${ultima.descricao}'),
              subtitulo: tr(
                'Tarifa de ${reais(ultima.tarifaKwh, casas: 4)} por kWh',
                'Rate of ${reais(ultima.tarifaKwh, casas: 4)} per kWh',
              ),
              onTap: () => calcularCom(context, widget.consulta, ultima),
            ),
            const SizedBox(height: Espaco.m),
            Text(tr('Ou escolha outro estado:', 'Or pick another state:'), style: t.forte),
            const SizedBox(height: Espaco.p),
          ] else
            CabecalhoPergunta(
              tr('Em qual estado você mora?', 'Which Brazilian state do you live in?'),
              ajuda: tr(
                'Assim achamos a sua distribuidora de energia e o preço do kWh.',
                'This is how we find your power company and the price of a kWh.',
              ),
            ),
          FutureBuilder<List<String>>(
            future: _ufs,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Carregando(texto: tr('Carregando os estados...', 'Loading states...'));
              }
              if (snap.hasError) {
                return MensagemErro(
                  snap.error.toString(),
                  tentarDeNovo: () => setState(() {
                    _ufs = Api.ufs();
                  }),
                );
              }
              final ufs = [...snap.data!]..sort((a, b) => (nomesDosEstados[a] ?? a).compareTo(nomesDosEstados[b] ?? b));
              return Column(
                children: [
                  for (final uf in ufs)
                    CartaoOpcao(titulo: nomesDosEstados[uf] ?? uf, subtitulo: uf, onTap: () => _escolher(uf)),
                ],
              );
            },
          ),
          const SizedBox(height: Espaco.m),
          CartaoOpcao(
            icone: Icons.receipt_long,
            titulo: tr('Prefiro digitar a tarifa da minha conta', "I'd rather type the rate from my bill"),
            subtitulo: tr('Se você tem a conta de luz em mãos.', 'If you have your electricity bill at hand.'),
            onTap: _digitarTarifa,
          ),
        ],
      ),
    );
  }
}

/// Etapa 5: qual distribuidora atende a casa (aparece na conta de luz).
class TelaDistribuidora extends StatefulWidget {
  final Consulta consulta;
  final String uf;

  const TelaDistribuidora({super.key, required this.consulta, required this.uf});

  @override
  State<TelaDistribuidora> createState() => _TelaDistribuidoraState();
}

class _TelaDistribuidoraState extends State<TelaDistribuidora> {
  final _filtro = TextEditingController();
  late Future<List<Distribuidora>> _distribuidoras;

  @override
  void initState() {
    super.initState();
    _distribuidoras = Api.distribuidoras(uf: widget.uf);
  }

  @override
  void dispose() {
    _filtro.dispose();
    super.dispose();
  }

  List<Distribuidora> _filtradas(List<Distribuidora> lista) {
    final alvo = _filtro.text.trim().toLowerCase();
    return alvo.isEmpty ? lista : lista.where((d) => d.nome.toLowerCase().contains(alvo)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Pagina(
      titulo: nomesDosEstados[widget.uf] ?? widget.uf,
      etapa: etapaDoCalculo(widget.consulta, 5),
      filho: FutureBuilder<List<Distribuidora>>(
        future: _distribuidoras,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Carregando(texto: tr('Carregando as distribuidoras...', 'Loading power companies...'));
          }
          if (snap.hasError) {
            return MensagemErro(
              snap.error.toString(),
              tentarDeNovo: () => setState(() {
                _distribuidoras = Api.distribuidoras(uf: widget.uf);
              }),
            );
          }
          final todas = snap.data!;
          final lista = _filtradas(todas);
          return ListView(
            children: [
              CabecalhoPergunta(
                tr('Qual é a sua distribuidora de energia?', 'Which is your power company?'),
                ajuda: tr(
                  'É a empresa que manda a conta de luz. O nome aparece no alto da conta.',
                  'It is the company that sends your electricity bill. Its name is at the top of the bill.',
                ),
              ),
              if (todas.length > 5) ...[
                TextField(
                  controller: _filtro,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: tr('Procurar pelo nome', 'Search by name'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: Espaco.p),
              ],
              if (lista.isEmpty) Text(tr('Nenhuma distribuidora com esse nome.', 'No power company with that name.'), style: t.corpo),
              for (final d in lista)
                CartaoOpcao(
                  titulo: d.nome,
                  subtitulo: tr(
                    'Tarifa de ${reais(d.tarifaKwh, casas: 4)} por kWh',
                    'Rate of ${reais(d.tarifaKwh, casas: 4)} per kWh',
                  ),
                  onTap: () => calcularCom(context, widget.consulta, EscolhaTarifa.daDistribuidora(d)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Tarifa digitada a partir da conta de luz.
class TelaTarifaConta extends StatefulWidget {
  final Consulta consulta;

  const TelaTarifaConta({super.key, required this.consulta});

  @override
  State<TelaTarifaConta> createState() => _TelaTarifaContaState();
}

class _TelaTarifaContaState extends State<TelaTarifaConta> {
  final _tarifa = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _tarifa.dispose();
    super.dispose();
  }

  void _calcular() {
    final tarifa = lerNumero(_tarifa.text);
    if (tarifa == null || tarifa <= 0 || tarifa > 10) {
      setState(() => _erro = tr('Informe o valor em reais por kWh. Ex.: 0,85.', 'Enter the price in reais per kWh. E.g.: 0.85.'));
      return;
    }
    setState(() => _erro = null);
    calcularCom(context, widget.consulta, EscolhaTarifa.manual(tarifa));
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: tr('Tarifa da conta', 'Rate from your bill'),
      etapa: etapaDoCalculo(widget.consulta, 5),
      rodape: FilledButton(onPressed: _calcular, child: Text(tr('Calcular', 'Calculate'))),
      filho: ListView(
        children: [
          CabecalhoPergunta(
            tr('Quanto custa o kWh na sua conta?', 'How much does a kWh cost on your bill?'),
            ajuda: tr(
              'Divida o valor total da conta pelo consumo do mês em kWh. '
                  'Ex.: R\$ 170,00 ÷ 200 kWh = 0,85.',
              "Divide the bill's total by the month's consumption in kWh. "
                  'E.g.: R\$ 170.00 ÷ 200 kWh = 0.85.',
            ),
          ),
          TextField(
            controller: _tarifa,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onSubmitted: (_) => _calcular(),
            decoration: InputDecoration(
              labelText: tr('Reais por kWh', 'Reais (R\$) per kWh'),
              hintText: tr('Ex.: 0,85', 'E.g.: 0.85'),
              prefixText: 'R\$ ',
              errorText: _erro,
            ),
          ),
        ],
      ),
    );
  }
}
