import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../tema.dart';
import 'comparar.dart';
import 'comum.dart';

/// Modelos equivalentes que gastam menos (POST /sugestoes), com o mesmo uso e a mesma tarifa.
/// item: quando veio de "Minha casa", permite trocar o aparelho la.
class TelaSugestoes extends StatefulWidget {
  final Consulta consulta;
  final ItemCasa? item;

  const TelaSugestoes({super.key, required this.consulta, this.item});

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

  Future<Sugestoes> _buscar() => Api.sugestoes(widget.consulta.aparelho.id, widget.consulta.paraApi());

  @override
  Widget build(BuildContext context) {
    final aparelho = widget.consulta.aparelho;
    return Pagina(
      titulo: 'Modelos mais econômicos',
      filho: FutureBuilder<Sugestoes>(
        future: _sugestoes,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
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
              Card(
                child: ListTile(
                  leading: Icon(iconeDaCategoria(aparelho.categoria)),
                  title: Text('Seu modelo: ${aparelho.nome}'),
                  subtitle: Text(
                    '${numero(s.kwhAtual)} kWh/mês - ${reais(s.custoAtual)} por mês',
                    style: Estilos.secundario,
                  ),
                ),
              ),
              if (s.criterio != null) ...[const Titulo('Comparando com modelos de'), Text(s.criterio!)],
              const SizedBox(height: 12),
              if (s.mensagem != null)
                Card(
                  color: Cores.amareloEscuro,
                  child: Padding(
                    padding: const EdgeInsets.all(Espaco.m),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.tips_and_updates_outlined, color: Cores.amarelo),
                        const SizedBox(width: 12),
                        Expanded(child: Text(s.mensagem!)),
                      ],
                    ),
                  ),
                ),
              for (final sugerido in s.sugestoes) _CartaoSugestao(sugerido, onTap: () => _abrir(sugerido)),
              if (s.suspeitosDescartados > 0) ...[
                const SizedBox(height: 8),
                ListaAvisos([
                  '${s.suspeitosDescartados} modelo(s) com consumo baixo demais para ser real '
                      '(provável erro no dado do Inmetro) ficaram de fora.',
                ]),
              ],
              if (s.sugestoes.isNotEmpty)
                const ListaAvisos(['Mesmo uso e mesma tarifa do seu aparelho. Toque num modelo para ver o payback.']),
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
        builder: (_) => TelaComparar(consulta: widget.consulta, sugerido: sugerido, item: widget.item),
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
    final a = s.aparelho;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Espaco.m),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.nome, style: Estilos.forte),
                    Text(
                      [if (a.detalhe.isNotEmpty) a.detalhe, if (s.tipo.isNotEmpty) s.tipo].join(' - '),
                      style: Estilos.secundario,
                    ),
                    const SizedBox(height: Espaco.p),
                    Text('${numero(s.kwhMes)} kWh/mês · ${reais(s.custoMes)}/mês', style: Estilos.secundario),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // economia em verde: o valor e maior que o rotulo
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('-${reais(s.economiaMes)}', style: Estilos.valorMedio.copyWith(color: Cores.verde)),
                  const Text('por mês', style: Estilos.secundario),
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: Espaco.p, vertical: 2),
                    decoration: BoxDecoration(
                      color: Cores.verde.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${numero(s.economiaPercentual, casas: 0)}% menos',
                      style: Estilos.rotulo.copyWith(color: Cores.verde),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Cores.amarelo),
            ],
          ),
        ),
      ),
    );
  }
}
