import 'package:flutter/material.dart';

import '../api.dart';
import '../tema.dart';
import 'comum.dart';

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
              ...textoFormatado(d.texto),
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

List<Widget> textoFormatado(String texto) {
  final widgets = <Widget>[];
  for (final bruta in texto.split('\n')) {
    final linha = bruta.trim();
    if (linha.isEmpty) continue;
    final titulo = RegExp(r'^#{1,6}\s*(.+)$').firstMatch(linha);
    final item = RegExp(r'^(?:[-*•]|\d+[.)])\s+(.+)$').firstMatch(linha);
    if (titulo != null) {
      widgets.add(Titulo(titulo.group(1)!.replaceAll('*', '')));
    } else if (item != null) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: Espaco.p),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 7, right: Espaco.p),
                child: Icon(Icons.circle, size: 6, color: Cores.amarelo),
              ),
              Expanded(child: Text.rich(TextSpan(children: trechosComNegrito(item.group(1)!)), style: Estilos.corpo)),
            ],
          ),
        ),
      );
    } else {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: Espaco.p),
          child: Text.rich(TextSpan(children: trechosComNegrito(linha)), style: Estilos.corpo),
        ),
      );
    }
  }
  return widgets;
}

List<TextSpan> trechosComNegrito(String texto) {
  final partes = texto.split('**');
  return [
    for (var i = 0; i < partes.length; i++)
      if (partes[i].isNotEmpty)
        TextSpan(
          text: partes[i],
          style: i.isOdd ? const TextStyle(fontWeight: FontWeight.bold, color: Cores.branco) : null,
        ),
  ];
}
