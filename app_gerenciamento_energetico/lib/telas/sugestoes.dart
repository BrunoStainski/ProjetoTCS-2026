import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../idioma.dart';
import '../tema.dart';
import 'comparar.dart';
import 'comum.dart';

/// Modelos equivalentes que gastam menos (POST /sugestoes), com o mesmo uso e a mesma tarifa.
/// item: quando veio de "Minha casa", permite trocar o aparelho la.
class TelaSugestoes extends StatefulWidget {
  final Consulta consulta;
  final ItemCasa? item;
  final Resultado? atual;

  const TelaSugestoes({super.key, required this.consulta, this.item, this.atual});

  @override
  State<TelaSugestoes> createState() => _TelaSugestoesState();
}

class _TelaSugestoesState extends State<TelaSugestoes> {
  late Future<Sugestoes> _sugestoes;

  @override
  void initState() {
    super.initState();
    _sugestoes = _buscar();
  }

  Future<Sugestoes> _buscar() => widget.consulta.estimado
      ? Api.sugestoesEstimado(widget.atual!, widget.consulta.paraApi())
      : Api.sugestoes(widget.consulta.aparelho.id, widget.consulta.paraApi());

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final aparelho = widget.consulta.aparelho;
    final nome = widget.atual?.nome ?? aparelho.nome;
    return Pagina(
      titulo: tr('Gastar menos', 'Spend less'),
      filho: FutureBuilder<Sugestoes>(
        future: _sugestoes,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Carregando(texto: tr('Procurando modelos que gastam menos...', 'Looking for models that use less...'));
          }
          if (snap.hasError) {
            return MensagemErro(
              snap.error.toString(),
              tentarDeNovo: () => setState(() {
                _sugestoes = _buscar();
              }),
            );
          }
          final s = snap.data!;
          return ListView(
            children: [
              CabecalhoPergunta(
                tr('Modelos parecidos que gastam menos', 'Similar models that use less'),
                ajuda: tr(
                  'Mesmo tamanho, mesmo uso e a mesma tarifa do seu aparelho. Toque num modelo para comparar.',
                  'Same size, same use and the same rate as your appliance. Tap a model to compare.',
                ),
              ),
              MergeSemantics(
                child: Card(
                  child: ListTile(
                    leading: Icon(iconeDaCategoria(aparelho.categoria)),
                    title: Text(tr('Seu aparelho: $nome', 'Your appliance: $nome')),
                    subtitle: Text(
                      tr(
                        '${reais(s.custoAtual)} por mês · ${numero(s.kwhAtual)} kWh',
                        '${reais(s.custoAtual)} per month · ${numero(s.kwhAtual)} kWh',
                      ),
                    ),
                  ),
                ),
              ),
              if (s.criterio != null) ...[
                Titulo(tr('Comparando com modelos de', 'Comparing with models of')),
                Text(s.criterio!, style: t.corpo),
              ],
              const SizedBox(height: Espaco.pm),
              if (s.mensagem != null)
                Card(
                  color: t.fundoDestaque,
                  child: Padding(
                    padding: const EdgeInsets.all(Espaco.m),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.tips_and_updates_outlined),
                        const SizedBox(width: Espaco.pm),
                        Expanded(child: Text(s.mensagem!, style: t.corpo)),
                      ],
                    ),
                  ),
                ),
              for (final sugerido in s.sugestoes) _CartaoSugestao(sugerido, onTap: () => _abrir(sugerido)),
              if (s.suspeitosDescartados > 0) ...[
                const SizedBox(height: Espaco.p),
                ListaAvisos([
                  tr(
                    '${s.suspeitosDescartados} modelo(s) com consumo irreal (erro do Inmetro) ficaram de fora.',
                    '${s.suspeitosDescartados} model(s) with unrealistic consumption (Inmetro data error) were left out.',
                  ),
                ]),
              ],
            ],
          );
        },
      ),
    );
  }

  void _abrir(AparelhoSugerido sugerido) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TelaComparar(consulta: widget.consulta, sugerido: sugerido, item: widget.item, atual: widget.atual),
      ),
    );
  }
}

class _CartaoSugestao extends StatelessWidget {
  final AparelhoSugerido s;
  final VoidCallback onTap;

  const _CartaoSugestao(this.s, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final a = s.aparelho;
    final economia = tr('${reais(s.economiaMes)} a menos por mês', '${reais(s.economiaMes)} less per month');
    return MergeSemantics(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Espaco.m),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.nome, style: t.forte),
                      if (a.detalhe.isNotEmpty || s.tipo.isNotEmpty)
                        Text([if (a.detalhe.isNotEmpty) a.detalhe, if (s.tipo.isNotEmpty) s.tipo].join(' · '),
                            style: t.secundario),
                      const SizedBox(height: Espaco.p),
                      // economia em verde e escrita por extenso ("a menos"), nao so pela cor
                      Text(economia, style: t.valorMedio.copyWith(color: t.economia)),
                      const SizedBox(height: Espaco.pp),
                      Wrap(
                        spacing: Espaco.p,
                        runSpacing: Espaco.pp,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: Espaco.p, vertical: 2),
                            decoration: t.selo(t.economia),
                            child: Text(
                              tr('${numero(s.economiaPercentual, casas: 0)}% menos', '${numero(s.economiaPercentual, casas: 0)}% less'),
                              style: t.rotulo.copyWith(color: t.economia),
                            ),
                          ),
                          Text(tr('Gasta ${reais(s.custoMes)} por mês', 'Costs ${reais(s.custoMes)} per month'), style: t.secundario),
                        ],
                      ),
                      Text(tr('${numero(s.kwhMes)} kWh por mês', '${numero(s.kwhMes)} kWh per month'), style: t.secundario),
                    ],
                  ),
                ),
                const SizedBox(width: Espaco.p),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
