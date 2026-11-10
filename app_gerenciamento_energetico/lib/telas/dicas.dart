import 'package:flutter/material.dart';

import '../api.dart';
import '../tema.dart';
import 'comum.dart';
import 'eco_coach.dart';
import 'texto_plano.dart';

/// Dicas do Eco-Coach para um aparelho so (eletroportateis, que nao tem modelos para comparar).
class TelaDicas extends StatefulWidget {
  final Resultado resultado;
  final Future<Dicas> Function(Resultado) buscarDicas;

  const TelaDicas({super.key, required this.resultado, this.buscarDicas = Api.dicas});

  @override
  State<TelaDicas> createState() => _TelaDicasState();
}

class _TelaDicasState extends State<TelaDicas> {
  late Future<Dicas> _dicas;

  @override
  void initState() {
    super.initState();
    _dicas = widget.buscarDicas(widget.resultado);
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final r = widget.resultado;
    return Pagina(
      titulo: 'Como gastar menos',
      filho: FutureBuilder<Dicas>(
        future: _dicas,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Carregando(texto: 'O Eco-Coach está preparando dicas para o seu aparelho...');
          }
          if (snap.hasError) {
            return MensagemErro(
              snap.error.toString(),
              tentarDeNovo: () => setState(() {
                _dicas = widget.buscarDicas(r);
              }),
            );
          }
          final d = snap.data!;
          return ListView(
            children: [
              MergeSemantics(
                child: Card(
                  child: ListTile(
                    leading: Icon(iconeDaCategoria(r.categoria)),
                    title: Text(r.nome),
                    subtitle: Text('${reais(r.custoMes)} por mês · ${numero(r.kwhMes)} kWh'),
                  ),
                ),
              ),
              const SizedBox(height: Espaco.m),
              TextoPlano(d.texto),
              if (d.fontes.isNotEmpty) ...[
                const Titulo('Fontes'),
                for (final f in d.fontes) CartaoFonte(f),
              ],
              const SizedBox(height: Espaco.m),
              ListaAvisos([d.aviso]),
              SizedBox(height: t.alvoToque),
            ],
          );
        },
      ),
    );
  }
}
