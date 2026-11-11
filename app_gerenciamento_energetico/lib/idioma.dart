// Idioma do app. O Iamp sempre abre em portugues (o idioma nativo); no menu (Idioma) a pessoa
// troca para o ingles, para apresentar o app para quem nao fala portugues. A escolha nao fica gravada:
// ao abrir o app de novo, ele volta para o portugues.
//
// Como traduzir um texto da tela: escreva as duas versoes no proprio lugar, tr('Calcular', 'Calculate').
// Assim quem muda o portugues ve o ingles ao lado. Os textos que vem da API (avisos, "Como calculamos",
// plano do Eco-Coach...) chegam no idioma certo: o app manda o idioma no cabecalho Accept-Language.
// Os textos do proprio Flutter (voltar, copiar, colar...) seguem o `locale` do MaterialApp (main.dart).

import 'package:flutter/widgets.dart';

enum Idioma {
  pt(Locale('pt', 'BR'), 'pt-BR', 'Português'),
  en(Locale('en', 'US'), 'en', 'English');

  final Locale locale;

  /// Valor do cabecalho Accept-Language enviado para a API.
  final String cabecalho;

  /// Nome do idioma escrito nele mesmo (quem nao entende o idioma atual ainda acha o seu).
  final String nome;

  const Idioma(this.locale, this.cabecalho, this.nome);
}

/// Idioma atual. O MaterialApp escuta este valor para trocar o `locale`.
final idioma = ValueNotifier<Idioma>(Idioma.pt);

bool get emIngles => idioma.value == Idioma.en;

/// Texto no idioma atual: tr('Gasto por mês', 'Cost per month').
String tr(String pt, String en) => emIngles ? en : pt;

/// Troca o idioma e desenha de novo todas as telas abertas, ja com os textos novos.
/// Os widgets leem o idioma com tr() durante o build; marcar todos para reconstruir faz cada um
/// chamar o tr() de novo (sem isso, so mudariam os textos das telas abertas depois da troca).
void mudarIdioma(Idioma novo) {
  if (idioma.value == novo) return;
  idioma.value = novo;
  void reconstruir(Element elemento) {
    elemento.markNeedsBuild();
    elemento.visitChildren(reconstruir);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(reconstruir);
}
