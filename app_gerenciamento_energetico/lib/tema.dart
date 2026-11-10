// Identidade visual do Iamp: fundo preto, amarelo de energia nos destaques e texto branco.
// Regra 60/30/10: 60% preto (fundo), 30% branco e superficies escuras, 10% amarelo
// (botoes e o valor principal). Verde e vermelho so aparecem quando tem significado:
// verde = economia / coisa boa, vermelho = alerta / erro. A cor nunca e o unico aviso:
// sempre vem junto um texto ou um icone diferente.
//
// Tudo o que e visual fica aqui: cores, textos, tamanhos e espacamentos. As telas leem
// pelo Theme (Iamp.de(context)) e nao escrevem cor nem tamanho solto.
//
// Acessibilidade (publico geral, incluindo pessoas mais velhas):
// - texto base de 18 e nada abaixo de 16; o app respeita o tamanho de fonte do sistema;
// - contraste AA: nenhum texto em cinza escuro; o mais apagado e o branco a 80% (~13:1 no preto);
// - alvo de toque minimo de 48dp em tudo que se toca.

import 'package:flutter/material.dart';

class Cores {
  static const preto = Color(0xFF000000);
  static const superficie = Color(0xFF141414); // cartoes
  static const superficieAlta = Color(0xFF1F1F1F); // campos, menus
  // detalhes (bordas, contornos, icones) em amarelo; o texto continua branco
  static const borda = Color(0x8CFFD000); // amarelo 55%: contraste 4,5:1 no preto (minimo 3:1 para bordas)
  static const divisoria = Color(0x40FFD000); // amarelo 25%: linhas entre itens de lista
  static const trilho = Color(0xFF2A2A2A); // fundo das barras de progresso
  static const amarelo = Color(0xFFFFD000);
  static const amareloEscuro = Color(0xFF2B2300); // fundo de destaque suave
  static const verde = Color(0xFF3DDC84); // economia
  static const vermelho = Color(0xFFFF5C5C); // alerta
  static const fundoErro = Color(0xFF1F0E0E);
  // texto: hierarquia por opacidade do branco (sem cinza escuro sobre o preto)
  static const branco = Color(0xFFFFFFFF); // titulos e valores (100%)
  static const corpo = Color(0xE6FFFFFF); // texto corrido (90%)
  static const secundario = Color(0xCCFFFFFF); // texto de apoio (80%, contraste ~13:1)
  static const exemplo = Color(0xB3FFFFFF); // exemplo dentro do campo (70%, contraste ~10:1)
}

/// Espacamentos em multiplos de 4 e 8 (grade de 8).
class Espaco {
  static const pp = 4.0;
  static const p = 8.0;
  static const pm = 12.0;
  static const m = 16.0;
  static const g = 24.0;
  static const gg = 32.0;
}

const _numeros = [FontFeature.tabularFigures()]; // digitos alinhados em valores

/// Estilos, cores com significado e medidas do app, guardados no ThemeData.
/// Uso nas telas: `final t = Iamp.de(context);` e depois `t.forte`, `t.economia`, `t.raio`...
@immutable
class Iamp extends ThemeExtension<Iamp> {
  // textos: 4 tamanhos (34, 22, 18, 16) e 2 pesos
  final TextStyle valor; // valor principal da tela (R$ por mes)
  final TextStyle valorMedio; // valores em cartoes
  final TextStyle pergunta; // a pergunta de cada etapa
  final TextStyle titulo;
  final TextStyle forte;
  final TextStyle corpo;
  final TextStyle numero;
  final TextStyle secundario;
  final TextStyle rotulo;

  // cores com significado
  final Color destaque; // acao e valor principal (amarelo)
  final Color economia; // verde
  final Color alerta; // vermelho
  final Color superficie;
  final Color fundoDestaque;
  final Color fundoErro;
  final Color borda;
  final Color textoForte;
  final Color textoSecundario;

  // medidas
  final double raio;
  final double raioPequeno;
  final double icone;
  final double iconeGrande;
  final double iconeEnorme;
  final double alvoToque; // 48dp: minimo do Android e do iOS
  final double barraProgresso;
  final double larguraMaxima; // navegador e tablet: conteudo centralizado

  const Iamp({
    required this.valor,
    required this.valorMedio,
    required this.pergunta,
    required this.titulo,
    required this.forte,
    required this.corpo,
    required this.numero,
    required this.secundario,
    required this.rotulo,
    required this.destaque,
    required this.economia,
    required this.alerta,
    required this.superficie,
    required this.fundoDestaque,
    required this.fundoErro,
    required this.borda,
    required this.textoForte,
    required this.textoSecundario,
    required this.raio,
    required this.raioPequeno,
    required this.icone,
    required this.iconeGrande,
    required this.iconeEnorme,
    required this.alvoToque,
    required this.barraProgresso,
    required this.larguraMaxima,
  });

  static const padrao = Iamp(
    valor: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, fontFeatures: _numeros, color: Cores.amarelo),
    valorMedio: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFeatures: _numeros, color: Cores.branco),
    pergunta: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Cores.branco, height: 1.3),
    titulo: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Cores.branco),
    forte: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Cores.branco),
    corpo: TextStyle(fontSize: 18, color: Cores.corpo, height: 1.4),
    numero: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFeatures: _numeros, color: Cores.branco),
    secundario: TextStyle(fontSize: 16, color: Cores.secundario, height: 1.35),
    rotulo: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Cores.secundario),
    destaque: Cores.amarelo,
    economia: Cores.verde,
    alerta: Cores.vermelho,
    superficie: Cores.superficie,
    fundoDestaque: Cores.amareloEscuro,
    fundoErro: Cores.fundoErro,
    borda: Cores.borda,
    textoForte: Cores.branco,
    textoSecundario: Cores.secundario,
    raio: 16,
    raioPequeno: 8,
    icone: 24,
    iconeGrande: 32,
    iconeEnorme: 64,
    alvoToque: 48,
    barraProgresso: 8,
    larguraMaxima: 640,
  );

  /// Le do tema; fora do app (testes de um widget so) usa o padrao.
  static Iamp de(BuildContext context) => Theme.of(context).extension<Iamp>() ?? padrao;

  /// Cartao do valor principal: contorno e brilho suave na cor (amarelo = gasto, verde = economia).
  BoxDecoration cartaoDestaque(Color cor, {bool circulo = false}) => BoxDecoration(
    color: superficie,
    shape: circulo ? BoxShape.circle : BoxShape.rectangle,
    borderRadius: circulo ? null : BorderRadius.circular(raio),
    border: Border.all(color: cor.withValues(alpha: 0.7), width: 1.5),
    boxShadow: [BoxShadow(color: cor.withValues(alpha: 0.18), blurRadius: 32, spreadRadius: -4)],
  );

  /// Etiqueta pequena com fundo suave (ex.: "30% menos", "Perfil Moderado").
  BoxDecoration selo(Color cor) => BoxDecoration(
    color: cor.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(raioPequeno),
    border: Border.all(color: cor.withValues(alpha: 0.6)),
  );

  @override
  Iamp copyWith() => this;

  @override
  Iamp lerp(Iamp? other, double t) => t < 0.5 || other == null ? this : other;
}

ThemeData temaIamp() {
  const t = Iamp.padrao;
  const esquema = ColorScheme(
    brightness: Brightness.dark,
    primary: Cores.amarelo,
    onPrimary: Cores.preto,
    primaryContainer: Cores.amareloEscuro,
    onPrimaryContainer: Cores.amarelo,
    secondary: Cores.verde,
    onSecondary: Cores.preto,
    secondaryContainer: Cores.superficieAlta,
    onSecondaryContainer: Cores.branco,
    error: Cores.vermelho,
    onError: Cores.preto,
    errorContainer: Cores.fundoErro,
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Cores.preto,
    onSurface: Cores.branco,
    onSurfaceVariant: Cores.secundario,
    surfaceContainerLowest: Cores.preto,
    surfaceContainerLow: Cores.superficie,
    surfaceContainer: Cores.superficie,
    surfaceContainerHigh: Cores.superficieAlta,
    surfaceContainerHighest: Cores.superficieAlta,
    outline: Cores.borda,
    outlineVariant: Cores.borda,
  );

  final base = ThemeData(colorScheme: esquema, useMaterial3: true);
  const textoBotao = TextStyle(fontSize: 18, fontWeight: FontWeight.bold);
  final texto = base.textTheme
      .copyWith(
        headlineSmall: t.pergunta,
        titleLarge: t.titulo,
        titleMedium: t.forte,
        titleSmall: t.rotulo,
        bodyLarge: t.corpo,
        bodyMedium: t.corpo,
        bodySmall: t.secundario,
        labelLarge: textoBotao,
        labelMedium: t.rotulo,
        labelSmall: t.secundario,
      )
      .apply(bodyColor: Cores.corpo, displayColor: Cores.branco);

  final cantos = RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.raio));
  final cantosCampo = BorderRadius.circular(t.raio - 4);
  // botoes principais com 56dp: alvo confortavel na zona do polegar
  const alturaBotao = Size.fromHeight(56);
  const espacoBotao = EdgeInsets.symmetric(horizontal: Espaco.m, vertical: Espaco.pm);

  return base.copyWith(
    scaffoldBackgroundColor: Cores.preto,
    textTheme: texto,
    extensions: const [t],
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: Cores.preto,
      foregroundColor: Cores.branco,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: t.titulo,
      iconTheme: const IconThemeData(color: Cores.amarelo), // seta de voltar
      actionsIconTheme: const IconThemeData(color: Cores.amarelo),
    ),
    iconTheme: IconThemeData(color: Cores.amarelo, size: t.icone),
    cardTheme: CardThemeData(
      color: Cores.superficie,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: Espaco.pp),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.raio),
        side: const BorderSide(color: Cores.borda),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Cores.superficie,
      contentPadding: const EdgeInsets.symmetric(horizontal: Espaco.m, vertical: Espaco.m + 2),
      border: OutlineInputBorder(borderRadius: cantosCampo),
      enabledBorder: OutlineInputBorder(
        borderRadius: cantosCampo,
        borderSide: const BorderSide(color: Cores.borda),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: cantosCampo,
        borderSide: const BorderSide(color: Cores.amarelo, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: cantosCampo,
        borderSide: const BorderSide(color: Cores.vermelho, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: cantosCampo,
        borderSide: const BorderSide(color: Cores.vermelho, width: 2),
      ),
      labelStyle: const TextStyle(color: Cores.secundario, fontSize: 18),
      floatingLabelStyle: const TextStyle(color: Cores.amarelo, fontSize: 18),
      helperStyle: t.secundario,
      helperMaxLines: 4,
      errorStyle: t.secundario.copyWith(color: Cores.vermelho),
      errorMaxLines: 4,
      hintStyle: const TextStyle(color: Cores.exemplo, fontSize: 18),
      suffixStyle: t.corpo,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Cores.amarelo,
        foregroundColor: Cores.preto,
        disabledBackgroundColor: const Color(0x66FFD000),
        disabledForegroundColor: Cores.preto,
        minimumSize: alturaBotao,
        padding: espacoBotao,
        shape: cantos,
        textStyle: textoBotao,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Cores.branco,
        iconColor: Cores.amarelo,
        minimumSize: alturaBotao,
        padding: espacoBotao,
        shape: cantos,
        side: const BorderSide(color: Cores.borda),
        textStyle: textoBotao,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Cores.amarelo,
        minimumSize: Size(t.alvoToque, t.alvoToque),
        padding: const EdgeInsets.symmetric(horizontal: Espaco.pm, vertical: Espaco.pm),
        textStyle: textoBotao,
      ),
    ),
    // alvo de toque minimo de 48dp em todos os botoes de icone
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: Size(t.alvoToque, t.alvoToque),
        foregroundColor: Cores.amarelo,
        disabledForegroundColor: const Color(0x66FFD000),
        iconSize: t.icone + 4,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Cores.amarelo, linearTrackColor: Cores.trilho),
    dividerTheme: const DividerThemeData(color: Cores.divisoria, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: Cores.amarelo,
      textColor: Cores.branco,
      titleTextStyle: t.forte,
      subtitleTextStyle: t.secundario,
      minVerticalPadding: Espaco.pm,
      minTileHeight: 64,
      contentPadding: const EdgeInsets.symmetric(horizontal: Espaco.m),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Cores.superficieAlta,
      contentTextStyle: t.corpo.copyWith(color: Cores.branco),
      actionTextColor: Cores.amarelo,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.raio),
        side: const BorderSide(color: Cores.borda),
      ),
    ),
    // secoes que abrem (busca agrupada por tipo de aparelho): sem linhas extras, seta amarela
    expansionTileTheme: const ExpansionTileThemeData(
      iconColor: Cores.amarelo,
      collapsedIconColor: Cores.amarelo,
      textColor: Cores.branco,
      collapsedTextColor: Cores.branco,
      shape: Border(),
      collapsedShape: Border(),
      tilePadding: EdgeInsets.symmetric(horizontal: Espaco.m, vertical: Espaco.pp),
      childrenPadding: EdgeInsets.zero,
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: Cores.amarelo,
      textColor: Cores.preto,
      textStyle: t.rotulo.copyWith(fontSize: 13),
    ),
    // navegacao inferior: icone + texto; a aba escolhida tem o fundo amarelo E o texto em negrito
    // (nao depende so da cor)
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Cores.superficie,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Cores.amarelo,
      height: 80,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (estados) => IconThemeData(
          color: estados.contains(WidgetState.selected) ? Cores.preto : Cores.amarelo,
          size: t.icone + 4,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (estados) => estados.contains(WidgetState.selected)
            ? const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Cores.amarelo)
            : const TextStyle(fontSize: 16, color: Cores.corpo),
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (estados) => estados.contains(WidgetState.selected) ? Cores.amarelo : Cores.secundario,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (estados) => estados.contains(WidgetState.selected) ? Cores.preto : Cores.secundario,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (estados) => estados.contains(WidgetState.selected) ? Cores.amarelo : Cores.superficieAlta,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(color: Cores.superficieAlta, shape: cantos, textStyle: t.corpo),
  );
}
