// Identidade visual do Iamp: fundo preto, amarelo de energia nos destaques e texto branco.
// Modo claro (opcao no menu): mesmos papeis de cor numa paleta clara (Palette.light). O amarelo
// #FFD000 nao tem contraste no branco, entao no claro ele fica so em preenchimentos (botao, aba
// escolhida, com texto preto) e os detalhes (icones, bordas, valor em destaque) usam um ambar escuro.
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

class AppColors {
  static const black = Color(0xFF000000);
  static const surface = Color(0xFF141414); // cartoes
  static const highSurface = Color(0xFF1F1F1F); // campos, menus
  // detalhes (bordas, contornos, icones) em amarelo; o texto continua branco
  static const border = Color(0x8CFFD000); // amarelo 55%: contraste 4,5:1 no preto (minimo 3:1 para bordas)
  static const divider = Color(0x40FFD000); // amarelo 25%: linhas entre itens de lista
  static const track = Color(0xFF2A2A2A); // fundo das barras de progresso
  static const yellow = Color(0xFFFFD000);
  static const yellowDark = Color(0xFF2B2300); // fundo de destaque suave
  static const green = Color(0xFF3DDC84); // economia
  static const red = Color(0xFFFF5C5C); // alerta
  static const errorBackground = Color(0xFF1F0E0E);
  // texto: hierarquia por opacidade do branco (sem cinza escuro sobre o preto)
  static const white = Color(0xFFFFFFFF); // titulos e valores (100%)
  static const body = Color(0xE6FFFFFF); // texto corrido (90%)
  static const secondary = Color(0xCCFFFFFF); // texto de apoio (80%, contraste ~13:1)
  static const example = Color(0xB3FFFFFF); // exemplo dentro do campo (70%, contraste ~10:1)
}

/// Cores de um modo (escuro ou claro), com os mesmos papeis. O tema e a extensao Iamp saem daqui.
class Palette {
  final Brightness brightness;
  final Color background;
  final Color surface; // cartoes
  final Color highSurface; // campos, menus
  final Color border;
  final Color divider;
  final Color track;
  final Color fill; // preenchimento de acao (botao, aba escolhida): sempre o amarelo
  final Color onFill; // texto e icone sobre o preenchimento
  final Color accent; // destaque sobre o fundo: icones, valor principal, links
  final Color softHighlight; // fundo de destaque suave
  final Color green;
  final Color red;
  final Color errorBackground;
  final Color onErrorBackground;
  final Color strongText;
  final Color bodyText;
  final Color secondaryText;
  final Color exampleText;

  const Palette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.highSurface,
    required this.border,
    required this.divider,
    required this.track,
    required this.fill,
    required this.onFill,
    required this.accent,
    required this.softHighlight,
    required this.green,
    required this.red,
    required this.errorBackground,
    required this.onErrorBackground,
    required this.strongText,
    required this.bodyText,
    required this.secondaryText,
    required this.exampleText,
  });

  static const dark = Palette(
    brightness: Brightness.dark,
    background: AppColors.black,
    surface: AppColors.surface,
    highSurface: AppColors.highSurface,
    border: AppColors.border,
    divider: AppColors.divider,
    track: AppColors.track,
    fill: AppColors.yellow,
    onFill: AppColors.black,
    accent: AppColors.yellow,
    softHighlight: AppColors.yellowDark,
    green: AppColors.green,
    red: AppColors.red,
    errorBackground: AppColors.errorBackground,
    onErrorBackground: Color(0xFFFFDAD6),
    strongText: AppColors.white,
    bodyText: AppColors.body,
    secondaryText: AppColors.secondary,
    exampleText: AppColors.example,
  );

  /// Claro: contraste AA conferido no branco e na superficie (ambar 6,4:1, verde 5,4:1, vermelho 5,9:1,
  /// borda 4,2:1; texto mais apagado = preto a 70%, ~8:1).
  static const light = Palette(
    brightness: Brightness.light,
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF6F3E8),
    highSurface: Color(0xFFECE8DA),
    border: Color(0xFF9A7600),
    divider: Color(0x409A7600),
    track: Color(0xFFE3DFD0),
    fill: AppColors.yellow,
    onFill: AppColors.black,
    accent: Color(0xFF7A5A00),
    softHighlight: Color(0xFFFFF3BF),
    green: Color(0xFF0A7A3D),
    red: Color(0xFFC0271F),
    errorBackground: Color(0xFFFDECEA),
    onErrorBackground: Color(0xFF5C0F0A),
    strongText: Color(0xFF111111),
    bodyText: Color(0xE6000000),
    secondaryText: Color(0xCC000000),
    exampleText: Color(0xB3000000),
  );
}

/// Modo claro ligado? O MaterialApp escuta este valor (main.dart). Comeca no escuro (a identidade
/// do app) e a escolha, como o idioma, nao fica gravada.
final lightMode = ValueNotifier<bool>(false);

/// Espacamentos em multiplos de 4 e 8 (grade de 8).
class Spacing {
  static const pp = 4.0;
  static const p = 8.0;
  static const pm = 12.0;
  static const m = 16.0;
  static const g = 24.0;
  static const gg = 32.0;
}

const _numbers = [FontFeature.tabularFigures()]; // digitos alinhados em valores

/// Estilos, cores com significado e medidas do app, guardados no ThemeData.
/// Uso nas telas: `final t = Iamp.de(context);` e depois `t.forte`, `t.economia`, `t.raio`...
@immutable
class Iamp extends ThemeExtension<Iamp> {
  // textos: 4 tamanhos (34, 22, 18, 16) e 2 pesos
  final TextStyle value; // valor principal da tela (R$ por mes)
  final TextStyle averageValue; // valores em cartoes
  final TextStyle question; // a pergunta de cada etapa
  final TextStyle title;
  final TextStyle strong;
  final TextStyle body;
  final TextStyle number;
  final TextStyle secondary;
  final TextStyle label;

  // cores com significado
  final Color highlight; // destaque sobre o fundo: icone, valor principal (amarelo; ambar escuro no claro)
  final Color highlightFill; // preenchimento amarelo (aba escolhida, item aberto do menu)
  final Color onFill; // texto e icone sobre o preenchimento (preto)
  final Color savings; // verde
  final Color alert; // vermelho
  final Color surface;
  final Color highlightBackground;
  final Color errorBackground;
  final Color border;
  final Color strongText;
  final Color secondaryText;

  // medidas
  final double radius;
  final double smallRadius;
  final double icon;
  final double largeIcon;
  final double hugeIcon;
  final double touchTarget; // 48dp: minimo do Android e do iOS
  final double progressBar;
  final double maxWidth; // navegador e tablet: conteudo centralizado

  const Iamp({
    required this.value,
    required this.averageValue,
    required this.question,
    required this.title,
    required this.strong,
    required this.body,
    required this.number,
    required this.secondary,
    required this.label,
    required this.highlight,
    required this.highlightFill,
    required this.onFill,
    required this.savings,
    required this.alert,
    required this.surface,
    required this.highlightBackground,
    required this.errorBackground,
    required this.border,
    required this.strongText,
    required this.secondaryText,
    required this.radius,
    required this.smallRadius,
    required this.icon,
    required this.largeIcon,
    required this.hugeIcon,
    required this.touchTarget,
    required this.progressBar,
    required this.maxWidth,
  });

  /// Estilos e cores de um modo. Os tamanhos sao os mesmos; so as cores mudam.
  factory Iamp.forPalette(Palette c) => Iamp(
    value: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, fontFeatures: _numbers, color: c.accent),
    averageValue: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFeatures: _numbers, color: c.strongText),
    question: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c.strongText, height: 1.3),
    title: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c.strongText),
    strong: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.strongText),
    body: TextStyle(fontSize: 18, color: c.bodyText, height: 1.4),
    number: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFeatures: _numbers, color: c.strongText),
    secondary: TextStyle(fontSize: 16, color: c.secondaryText, height: 1.35),
    label: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c.secondaryText),
    highlight: c.accent,
    highlightFill: c.fill,
    onFill: c.onFill,
    savings: c.green,
    alert: c.red,
    surface: c.surface,
    highlightBackground: c.softHighlight,
    errorBackground: c.errorBackground,
    border: c.border,
    strongText: c.strongText,
    secondaryText: c.secondaryText,
    radius: 16,
    smallRadius: 8,
    icon: 24,
    largeIcon: 32,
    hugeIcon: 64,
    touchTarget: 48,
    progressBar: 8,
    maxWidth: 640,
  );

  /// Modo escuro (o padrao do app).
  static final defaults = Iamp.forPalette(Palette.dark);

  /// Le do tema; fora do app (testes de um widget so) usa o padrao.
  static Iamp de(BuildContext context) => Theme.of(context).extension<Iamp>() ?? defaults;

  /// Cartao do valor principal: contorno e brilho suave na cor (amarelo = gasto, verde = economia).
  BoxDecoration highlightCard(Color cor, {bool circle = false}) => BoxDecoration(
    color: surface,
    shape: circle ? BoxShape.circle : BoxShape.rectangle,
    borderRadius: circle ? null : BorderRadius.circular(radius),
    border: Border.all(color: cor.withValues(alpha: 0.7), width: 1.5),
    boxShadow: [BoxShadow(color: cor.withValues(alpha: 0.18), blurRadius: 32, spreadRadius: -4)],
  );

  /// Etiqueta pequena com fundo suave (ex.: "30% menos", "Perfil Moderado").
  BoxDecoration badge(Color cor) => BoxDecoration(
    color: cor.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(smallRadius),
    border: Border.all(color: cor.withValues(alpha: 0.6)),
  );

  @override
  Iamp copyWith() => this;

  @override
  Iamp lerp(Iamp? other, double t) => t < 0.5 || other == null ? this : other;
}

/// Transicao entre as etapas (toda troca de tela): a tela nova entra deslizando um pouco da direita
/// enquanto aparece, e a anterior recua para a esquerda e apaga; ao voltar, o caminho inverso.
/// Curta (280 ms) para nao atrasar quem ja conhece o app. Com "remover animacoes" ligado no sistema
/// (acessibilidade), a tela troca direto.
class StepTransition extends PageTransitionsBuilder {
  const StepTransition();

  static const duration = Duration(milliseconds: 280);
  static final _enter = Tween(begin: const Offset(0.16, 0), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic));
  static final _leave = Tween(begin: Offset.zero, end: const Offset(-0.10, 0)).chain(CurveTween(curve: Curves.easeOutCubic));
  static final _appear = CurveTween(curve: Curves.easeOut);
  static final _fade = Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeOut));

  @override
  Duration get transitionDuration => duration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return SlideTransition(
      position: secondaryAnimation.drive(_leave),
      child: FadeTransition(
        opacity: secondaryAnimation.drive(_fade),
        child: SlideTransition(
          position: animation.drive(_enter),
          child: FadeTransition(opacity: animation.drive(_appear), child: child),
        ),
      ),
    );
  }
}

ThemeData iampTheme({bool light = false}) {
  final c = light ? Palette.light : Palette.dark;
  final t = Iamp.forPalette(c);
  final schema = ColorScheme(
    brightness: c.brightness,
    primary: c.fill,
    onPrimary: c.onFill,
    primaryContainer: c.softHighlight,
    onPrimaryContainer: c.accent,
    secondary: c.green,
    onSecondary: c.onFill,
    secondaryContainer: c.highSurface,
    onSecondaryContainer: c.strongText,
    error: c.red,
    onError: c.onFill,
    errorContainer: c.errorBackground,
    onErrorContainer: c.onErrorBackground,
    surface: c.background,
    onSurface: c.strongText,
    onSurfaceVariant: c.secondaryText,
    surfaceContainerLowest: c.background,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.highSurface,
    surfaceContainerHighest: c.highSurface,
    outline: c.border,
    outlineVariant: c.border,
  );

  final base = ThemeData(colorScheme: schema, useMaterial3: true);
  const buttonText = TextStyle(fontSize: 18, fontWeight: FontWeight.bold);
  final text = base.textTheme
      .copyWith(
        headlineSmall: t.question,
        titleLarge: t.title,
        titleMedium: t.strong,
        titleSmall: t.label,
        bodyLarge: t.body,
        bodyMedium: t.body,
        bodySmall: t.secondary,
        labelLarge: buttonText,
        labelMedium: t.label,
        labelSmall: t.secondary,
      )
      .apply(bodyColor: c.bodyText, displayColor: c.strongText);

  final corners = RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radius));
  final fieldCorners = BorderRadius.circular(t.radius - 4);
  // botoes principais com 56dp: alvo confortavel na zona do polegar
  const buttonHeight = Size.fromHeight(56);
  const buttonSpacing = EdgeInsets.symmetric(horizontal: Spacing.m, vertical: Spacing.pm);

  return base.copyWith(
    scaffoldBackgroundColor: c.background,
    // a mesma transicao em todas as plataformas (Android, iOS, navegador)
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {for (final p in TargetPlatform.values) p: const StepTransition()},
    ),
    textTheme: text,
    extensions: [t],
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.strongText,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: t.title,
      iconTheme: IconThemeData(color: c.accent), // seta de voltar
      actionsIconTheme: IconThemeData(color: c.accent),
    ),
    iconTheme: IconThemeData(color: c.accent, size: t.icon),
    cardTheme: CardThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: Spacing.pp),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius),
        side: BorderSide(color: c.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.m, vertical: Spacing.m + 2),
      border: OutlineInputBorder(borderRadius: fieldCorners),
      enabledBorder: OutlineInputBorder(
        borderRadius: fieldCorners,
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: fieldCorners,
        borderSide: BorderSide(color: c.accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: fieldCorners,
        borderSide: BorderSide(color: c.red, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: fieldCorners,
        borderSide: BorderSide(color: c.red, width: 2),
      ),
      labelStyle: TextStyle(color: c.secondaryText, fontSize: 18),
      floatingLabelStyle: TextStyle(color: c.accent, fontSize: 18),
      helperStyle: t.secondary,
      helperMaxLines: 4,
      errorStyle: t.secondary.copyWith(color: c.red),
      errorMaxLines: 4,
      hintStyle: TextStyle(color: c.exampleText, fontSize: 18),
      suffixStyle: t.body,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.fill,
        foregroundColor: c.onFill,
        disabledBackgroundColor: const Color(0x66FFD000),
        disabledForegroundColor: c.onFill,
        minimumSize: buttonHeight,
        padding: buttonSpacing,
        shape: corners,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.strongText,
        iconColor: c.accent,
        minimumSize: buttonHeight,
        padding: buttonSpacing,
        shape: corners,
        side: BorderSide(color: c.border),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        minimumSize: Size(t.touchTarget, t.touchTarget),
        padding: const EdgeInsets.symmetric(horizontal: Spacing.pm, vertical: Spacing.pm),
        textStyle: buttonText,
      ),
    ),
    // alvo de toque minimo de 48dp em todos os botoes de icone
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: Size(t.touchTarget, t.touchTarget),
        foregroundColor: c.accent,
        disabledForegroundColor: const Color(0x66FFD000),
        iconSize: t.icon + 4,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent, linearTrackColor: c.track),
    dividerTheme: DividerThemeData(color: c.divider, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: c.accent,
      textColor: c.strongText,
      titleTextStyle: t.strong,
      subtitleTextStyle: t.secondary,
      minVerticalPadding: Spacing.pm,
      minTileHeight: 64,
      contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.m),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.highSurface,
      contentTextStyle: t.body.copyWith(color: c.strongText),
      actionTextColor: c.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius),
        side: BorderSide(color: c.border),
      ),
    ),
    // secoes que abrem (busca agrupada por tipo de aparelho): sem linhas extras, seta amarela
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: c.accent,
      collapsedIconColor: c.accent,
      textColor: c.strongText,
      collapsedTextColor: c.strongText,
      shape: Border(),
      collapsedShape: Border(),
      tilePadding: EdgeInsets.symmetric(horizontal: Spacing.m, vertical: Spacing.pp),
      childrenPadding: EdgeInsets.zero,
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: c.fill,
      textColor: c.onFill,
      textStyle: t.label.copyWith(fontSize: 13),
    ),
    // navegacao inferior: icone + texto; a aba escolhida tem o fundo amarelo E o texto em negrito
    // (nao depende so da cor)
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.fill,
      height: 80,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? c.onFill : c.accent,
          size: t.icon + 4,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c.accent)
            : TextStyle(fontSize: 16, color: c.bodyText),
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.accent : c.secondaryText,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.onFill : c.secondaryText,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.fill : c.highSurface,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(color: c.highSurface, shape: corners, textStyle: t.body),
  );
}
