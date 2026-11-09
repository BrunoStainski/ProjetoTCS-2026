import 'package:flutter/material.dart';

import '../api.dart';
import '../tema.dart';
import 'comum.dart';
import 'texto_plano.dart';

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
    final r = widget.resultado;
    return Pagina(
      titulo: 'Como gastar menos',
      filho: FutureBuilder<Dicas>(
        future: _dicas,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: Espaco.m),
                  Text('O Eco-Coach está preparando dicas para o seu aparelho...', style: Estilos.secundario),
                ],
              ),
            );
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
              Card(
                child: ListTile(
                  leading: Icon(iconeDaCategoria(r.categoria), color: Cores.amarelo),
                  title: Text(r.nome, style: Estilos.forte),
                  subtitle: Text('${numero(r.kwhMes)} kWh/mês - ${reais(r.custoMes)} por mês', style: Estilos.secundario),
                ),
              ),
              const SizedBox(height: Espaco.m),
              TextoPlano(d.texto),
              if (d.fontes.isNotEmpty) ...[
                const Titulo('Fontes'),
                for (final f in d.fontes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espaco.p),
                    child: Text('[${f.n}] ${f.orgao} - ${f.documento}\n${f.url}', style: Estilos.secundario),
                  ),
              ],
              const SizedBox(height: Espaco.m),
              ListaAvisos([d.aviso]),
            ],
          );
        },
      ),
    );
  }
}
