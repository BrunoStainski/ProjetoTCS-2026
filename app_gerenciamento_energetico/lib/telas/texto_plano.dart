// Mostra o plano do Eco-Coach (markdown simples vindo do Gemini) no visual do app,
// sem pacote extra. Entende: titulos (#), linhas inteiras em **negrito** como titulo,
// listas (-, *, •, 1.), **negrito** no meio do texto e citacoes [n] / [1, 2] em amarelo.

import 'package:flutter/material.dart';

import '../tema.dart';

final _citacao = RegExp(r'\[(\d+(?:\s*,\s*\d+)*)\]');
final _negrito = RegExp(r'\*\*(.+?)\*\*');
final _numerada = RegExp(r'^(\d+)[.)]\s+');
final _marcador = RegExp(r'^[-*•]\s+');

/// Texto de uma linha -> pedacos com estilo (negrito e citacoes destacadas).
List<TextSpan> pedacosDoTexto(String texto, TextStyle base) {
  final pedacos = <TextSpan>[];
  // primeiro separa o negrito, depois as citacoes dentro de cada parte
  var inicio = 0;
  for (final m in _negrito.allMatches(texto)) {
    if (m.start > inicio) pedacos.addAll(_comCitacoes(texto.substring(inicio, m.start), base));
    pedacos.addAll(_comCitacoes(m.group(1)!, base.copyWith(fontWeight: FontWeight.bold, color: Cores.branco)));
    inicio = m.end;
  }
  if (inicio < texto.length) pedacos.addAll(_comCitacoes(texto.substring(inicio), base));
  return pedacos;
}

List<TextSpan> _comCitacoes(String texto, TextStyle estilo) {
  final pedacos = <TextSpan>[];
  var inicio = 0;
  for (final m in _citacao.allMatches(texto)) {
    if (m.start > inicio) pedacos.add(TextSpan(text: _semAsteriscos(texto.substring(inicio, m.start)), style: estilo));
    final numeros = m.group(1)!.split(',').map((n) => n.trim()).join(', ');
    pedacos.add(
      TextSpan(
        text: '[$numeros]',
        style: estilo.copyWith(color: Cores.amarelo, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
    inicio = m.end;
  }
  if (inicio < texto.length) pedacos.add(TextSpan(text: _semAsteriscos(texto.substring(inicio)), style: estilo));
  return pedacos;
}

// *italico* e _italico_ viram texto normal (o app usa so 2 pesos e nenhum italico)
String _semAsteriscos(String s) => s.replaceAll(RegExp(r'(?<!\w)[*_](?!\s)|(?<!\s)[*_](?!\w)'), '');

class TextoPlano extends StatelessWidget {
  final String markdown;

  const TextoPlano(this.markdown, {super.key});

  @override
  Widget build(BuildContext context) {
    final blocos = <Widget>[];
    for (final linhaCrua in markdown.split('\n')) {
      final recuo = linhaCrua.length - linhaCrua.trimLeft().length;
      final linha = linhaCrua.trim();
      if (linha.isEmpty || linha == '---') {
        if (blocos.isNotEmpty) blocos.add(const SizedBox(height: Espaco.p));
        continue;
      }
      final titulo = linha.startsWith('#')
          ? linha.replaceFirst(RegExp(r'^#+\s*'), '')
          : (linha.startsWith('**') && linha.endsWith('**') && _negrito.allMatches(linha).length == 1)
          ? linha.substring(2, linha.length - 2)
          : null;
      if (titulo != null) {
        blocos.add(
          Padding(
            padding: const EdgeInsets.only(top: Espaco.p, bottom: 4),
            child: Text(
              titulo.replaceAll('*', '').replaceAll(RegExp(r':$'), '').toUpperCase(),
              style: Estilos.rotulo.copyWith(color: Cores.amarelo, letterSpacing: 0.8),
            ),
          ),
        );
        continue;
      }
      final numerada = _numerada.firstMatch(linha);
      final marcador = _marcador.firstMatch(linha);
      if (numerada != null || marcador != null) {
        final texto = linha.substring((numerada ?? marcador)!.end);
        blocos.add(
          Padding(
            padding: EdgeInsets.only(left: recuo > 1 ? Espaco.g : 0, bottom: Espaco.p),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: numerada != null
                      ? Text('${numerada.group(1)}.', style: Estilos.forte.copyWith(color: Cores.amarelo))
                      : const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.bolt, size: 18, color: Cores.amarelo),
                        ),
                ),
                Expanded(child: Text.rich(TextSpan(children: pedacosDoTexto(texto, Estilos.corpo)))),
              ],
            ),
          ),
        );
        continue;
      }
      blocos.add(
        Padding(
          padding: const EdgeInsets.only(bottom: Espaco.p),
          child: Text.rich(TextSpan(children: pedacosDoTexto(linha, Estilos.corpo))),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocos);
  }
}
