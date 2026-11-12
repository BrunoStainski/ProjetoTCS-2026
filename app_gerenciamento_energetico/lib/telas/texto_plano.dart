// Mostra o plano do Eco-Coach (markdown simples vindo do Gemini) no visual do app,
// sem pacote extra. Entende: titulos (#), linhas inteiras em **negrito** como titulo,
// listas (-, *, •, 1.), **negrito** no meio do texto e citacoes [n] / [1, 2] em amarelo.
// Titulos ficam em letras normais (nao em CAIXA ALTA), que sao mais faceis de ler.

import 'package:flutter/material.dart';

import '../tema.dart';

final _citation = RegExp(r'\[(\d+(?:\s*,\s*\d+)*)\]');
final _bold = RegExp(r'\*\*(.+?)\*\*');
final _numbered = RegExp(r'^(\d+)[.)]\s+');
final _marker = RegExp(r'^[-*•]\s+');

/// Texto de uma linha -> pedacos com estilo (negrito e citacoes destacadas).
/// strong/citation: cores do negrito e das citacoes (mudam com o modo claro/escuro; padrao = escuro).
List<TextSpan> textPieces(
  String text,
  TextStyle base, {
  Color strong = AppColors.white,
  Color citation = AppColors.yellow,
}) {
  final pieces = <TextSpan>[];
  // primeiro separa o negrito, depois as citacoes dentro de cada parte
  var start = 0;
  for (final m in _bold.allMatches(text)) {
    if (m.start > start) pieces.addAll(_withCitations(text.substring(start, m.start), base, citation));
    pieces.addAll(_withCitations(m.group(1)!, base.copyWith(fontWeight: FontWeight.bold, color: strong), citation));
    start = m.end;
  }
  if (start < text.length) pieces.addAll(_withCitations(text.substring(start), base, citation));
  return pieces;
}

List<TextSpan> _withCitations(String text, TextStyle style, Color citation) {
  final pieces = <TextSpan>[];
  var start = 0;
  for (final m in _citation.allMatches(text)) {
    if (m.start > start) pieces.add(TextSpan(text: _withoutAsterisks(text.substring(start, m.start)), style: style));
    final numbers = m.group(1)!.split(',').map((n) => n.trim()).join(', ');
    pieces.add(
      TextSpan(
        text: '[$numbers]',
        style: style.copyWith(color: citation, fontWeight: FontWeight.bold),
      ),
    );
    start = m.end;
  }
  if (start < text.length) pieces.add(TextSpan(text: _withoutAsterisks(text.substring(start)), style: style));
  return pieces;
}

// *italico* e _italico_ viram texto normal (o app usa so 2 pesos e nenhum italico)
String _withoutAsterisks(String s) => s.replaceAll(RegExp(r'(?<!\w)[*_](?!\s)|(?<!\s)[*_](?!\w)'), '');

class PlanText extends StatelessWidget {
  final String markdown;

  const PlanText(this.markdown, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final blocks = <Widget>[];
    for (final rawLine in markdown.split('\n')) {
      final indent = rawLine.length - rawLine.trimLeft().length;
      final line = rawLine.trim();
      if (line.isEmpty || line == '---') {
        if (blocks.isNotEmpty) blocks.add(const SizedBox(height: Spacing.p));
        continue;
      }
      final title = line.startsWith('#')
          ? line.replaceFirst(RegExp(r'^#+\s*'), '')
          : (line.startsWith('**') && line.endsWith('**') && _bold.allMatches(line).length == 1)
          ? line.substring(2, line.length - 2)
          : null;
      if (title != null) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(top: Spacing.p, bottom: Spacing.pp),
            child: Semantics(
              header: true,
              child: Text(
                title.replaceAll('*', '').replaceAll(RegExp(r':$'), ''),
                style: t.strong.copyWith(color: t.highlight),
              ),
            ),
          ),
        );
        continue;
      }
      final numbered = _numbered.firstMatch(line);
      final marker = _marker.firstMatch(line);
      if (numbered != null || marker != null) {
        final text = line.substring((numbered ?? marker)!.end);
        blocks.add(
          Padding(
            padding: EdgeInsets.only(left: indent > 1 ? Spacing.g : 0, bottom: Spacing.p),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: Spacing.p),
                  child: numbered != null
                      ? Text('${numbered.group(1)}.', style: t.strong.copyWith(color: t.highlight))
                      : Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(Icons.bolt, size: t.icon - 4, color: t.highlight),
                        ),
                ),
                Expanded(child: Text.rich(TextSpan(children: textPieces(text, t.body, strong: t.strongText, citation: t.highlight)))),
              ],
            ),
          ),
        );
        continue;
      }
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.p),
          child: Text.rich(TextSpan(children: textPieces(line, t.body, strong: t.strongText, citation: t.highlight))),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
  }
}
