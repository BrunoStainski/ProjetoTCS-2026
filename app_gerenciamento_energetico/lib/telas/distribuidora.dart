// Tarifa de energia, uma decisao por tela:
// etapa 4 (TelaEstado): o estado, ou usar a mesma tarifa de antes;
// etapa 5 (TelaDistribuidora): a distribuidora do estado;
// opcional (TelaTarifaConta): digitar a tarifa que esta na conta de luz.

import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
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
      titulo: 'Sua energia',
      etapa: etapaDoCalculo(widget.consulta, 4),
      filho: ListView(
        children: [
          if (ultima != null) ...[
            const CabecalhoPergunta('Usar a mesma conta de luz de antes?'),
            CartaoOpcao(
              icone: Icons.bolt,
              titulo: 'Sim, usar ${ultima.descricao}',
              subtitulo: 'Tarifa de ${reais(ultima.tarifaKwh, casas: 4)} por kWh',
              onTap: () => calcularCom(context, widget.consulta, ultima),
            ),
            const SizedBox(height: Espaco.m),
            Text('Ou escolha outro estado:', style: t.forte),
            const SizedBox(height: Espaco.p),
          ] else
            const CabecalhoPergunta(
              'Em qual estado você mora?',
              ajuda: 'Assim achamos a sua distribuidora de energia e o preço do kWh.',
            ),
          FutureBuilder<List<String>>(
            future: _ufs,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Carregando(texto: 'Carregando os estados...');
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
            titulo: 'Prefiro digitar a tarifa da minha conta',
            subtitulo: 'Se você tem a conta de luz em mãos.',
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
          if (snap.connectionState != ConnectionState.done) return const Carregando(texto: 'Carregando as distribuidoras...');
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
              const CabecalhoPergunta(
                'Qual é a sua distribuidora de energia?',
                ajuda: 'É a empresa que manda a conta de luz. O nome aparece no alto da conta.',
              ),
              if (todas.length > 5) ...[
                TextField(
                  controller: _filtro,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Procurar pelo nome', prefixIcon: Icon(Icons.search)),
                ),
                const SizedBox(height: Espaco.p),
              ],
              if (lista.isEmpty) Text('Nenhuma distribuidora com esse nome.', style: t.corpo),
              for (final d in lista)
                CartaoOpcao(
                  titulo: d.nome,
                  subtitulo: 'Tarifa de ${reais(d.tarifaKwh, casas: 4)} por kWh',
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
      setState(() => _erro = 'Informe o valor em reais por kWh. Ex.: 0,85.');
      return;
    }
    setState(() => _erro = null);
    calcularCom(context, widget.consulta, EscolhaTarifa.manual(tarifa));
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Tarifa da conta',
      etapa: etapaDoCalculo(widget.consulta, 5),
      rodape: FilledButton(onPressed: _calcular, child: const Text('Calcular')),
      filho: ListView(
        children: [
          const CabecalhoPergunta(
            'Quanto custa o kWh na sua conta?',
            ajuda: 'Divida o valor total da conta pelo consumo do mês em kWh. '
                'Ex.: R\$ 170,00 ÷ 200 kWh = 0,85.',
          ),
          TextField(
            controller: _tarifa,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onSubmitted: (_) => _calcular(),
            decoration: InputDecoration(
              labelText: 'Reais por kWh',
              hintText: 'Ex.: 0,85',
              prefixText: 'R\$ ',
              errorText: _erro,
            ),
          ),
        ],
      ),
    );
  }
}
