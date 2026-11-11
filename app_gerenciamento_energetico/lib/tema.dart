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
  final Color highlight; // acao e valor principal (amarelo)
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

  static const defaults = Iamp(
    value: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, fontFeatures: _numbers, color: AppColors.yellow),
    averageValue: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFeatures: _numbers, color: AppColors.white),
    question: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.white, height: 1.3),
    title: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.white),
    strong: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.white),
    body: TextStyle(fontSize: 18, color: AppColors.body, height: 1.4),
    number: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFeatures: _numbers, color: AppColors.white),
    secondary: TextStyle(fontSize: 16, color: AppColors.secondary, height: 1.35),
    label: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.secondary),
    highlight: AppColors.yellow,
    savings: AppColors.green,
    alert: AppColors.red,
    surface: AppColors.surface,
    highlightBackground: AppColors.yellowDark,
    errorBackground: AppColors.errorBackground,
    border: AppColors.border,
    strongText: AppColors.white,
    secondaryText: AppColors.secondary,
    radius: 16,
    smallRadius: 8,
    icon: 24,
    largeIcon: 32,
    hugeIcon: 64,
    touchTarget: 48,
    progressBar: 8,
    maxWidth: 640,
  );

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

ThemeData iampTheme() {
  const t = Iamp.defaults;
  const schema = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.yellow,
    onPrimary: AppColors.black,
    primaryContainer: AppColors.yellowDark,
    onPrimaryContainer: AppColors.yellow,
    secondary: AppColors.green,
    onSecondary: AppColors.black,
    secondaryContainer: AppColors.highSurface,
    onSecondaryContainer: AppColors.white,
    error: AppColors.red,
    onError: AppColors.black,
    errorContainer: AppColors.errorBackground,
    onErrorContainer: Color(0xFFFFDAD6),
    surface: AppColors.black,
    onSurface: AppColors.white,
    onSurfaceVariant: AppColors.secondary,
    surfaceContainerLowest: AppColors.black,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.highSurface,
    surfaceContainerHighest: AppColors.highSurface,
    outline: AppColors.border,
    outlineVariant: AppColors.border,
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
      .apply(bodyColor: AppColors.body, displayColor: AppColors.white);

  final corners = RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radius));
  final fieldCorners = BorderRadius.circular(t.radius - 4);
  // botoes principais com 56dp: alvo confortavel na zona do polegar
  const buttonHeight = Size.fromHeight(56);
  const buttonSpacing = EdgeInsets.symmetric(horizontal: Spacing.m, vertical: Spacing.pm);

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.black,
    textTheme: text,
    extensions: const [t],
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.black,
      foregroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: t.title,
      iconTheme: const IconThemeData(color: AppColors.yellow), // seta de voltar
      actionsIconTheme: const IconThemeData(color: AppColors.yellow),
    ),
    iconTheme: IconThemeData(color: AppColors.yellow, size: t.icon),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: Spacing.pp),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.m, vertical: Spacing.m + 2),
      border: OutlineInputBorder(borderRadius: fieldCorners),
      enabledBorder: OutlineInputBorder(
        borderRadius: fieldCorners,
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: fieldCorners,
        borderSide: const BorderSide(color: AppColors.yellow, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: fieldCorners,
        borderSide: const BorderSide(color: AppColors.red, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: fieldCorners,
        borderSide: const BorderSide(color: AppColors.red, width: 2),
      ),
      labelStyle: const TextStyle(color: AppColors.secondary, fontSize: 18),
      floatingLabelStyle: const TextStyle(color: AppColors.yellow, fontSize: 18),
      helperStyle: t.secondary,
      helperMaxLines: 4,
      errorStyle: t.secondary.copyWith(color: AppColors.red),
      errorMaxLines: 4,
      hintStyle: const TextStyle(color: AppColors.example, fontSize: 18),
      suffixStyle: t.body,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.yellow,
        foregroundColor: AppColors.black,
        disabledBackgroundColor: const Color(0x66FFD000),
        disabledForegroundColor: AppColors.black,
        minimumSize: buttonHeight,
        padding: buttonSpacing,
        shape: corners,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.white,
        iconColor: AppColors.yellow,
        minimumSize: buttonHeight,
        padding: buttonSpacing,
        shape: corners,
        side: const BorderSide(color: AppColors.border),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.yellow,
        minimumSize: Size(t.touchTarget, t.touchTarget),
        padding: const EdgeInsets.symmetric(horizontal: Spacing.pm, vertical: Spacing.pm),
        textStyle: buttonText,
      ),
    ),
    // alvo de toque minimo de 48dp em todos os botoes de icone
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: Size(t.touchTarget, t.touchTarget),
        foregroundColor: AppColors.yellow,
        disabledForegroundColor: const Color(0x66FFD000),
        iconSize: t.icon + 4,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.yellow, linearTrackColor: AppColors.track),
    dividerTheme: const DividerThemeData(color: AppColors.divider, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.yellow,
      textColor: AppColors.white,
      titleTextStyle: t.strong,
      subtitleTextStyle: t.secondary,
      minVerticalPadding: Spacing.pm,
      minTileHeight: 64,
      contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.m),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.highSurface,
      contentTextStyle: t.body.copyWith(color: AppColors.white),
      actionTextColor: AppColors.yellow,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    // secoes que abrem (busca agrupada por tipo de aparelho): sem linhas extras, seta amarela
    expansionTileTheme: const ExpansionTileThemeData(
      iconColor: AppColors.yellow,
      collapsedIconColor: AppColors.yellow,
      textColor: AppColors.white,
      collapsedTextColor: AppColors.white,
      shape: Border(),
      collapsedShape: Border(),
      tilePadding: EdgeInsets.symmetric(horizontal: Spacing.m, vertical: Spacing.pp),
      childrenPadding: EdgeInsets.zero,
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: AppColors.yellow,
      textColor: AppColors.black,
      textStyle: t.label.copyWith(fontSize: 13),
    ),
    // navegacao inferior: icone + texto; a aba escolhida tem o fundo amarelo E o texto em negrito
    // (nao depende so da cor)
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.yellow,
      height: 80,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? AppColors.black : AppColors.yellow,
          size: t.icon + 4,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.yellow)
            : const TextStyle(fontSize: 16, color: AppColors.body),
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? AppColors.yellow : AppColors.secondary,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? AppColors.black : AppColors.secondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? AppColors.yellow : AppColors.highSurface,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(color: AppColors.highSurface, shape: corners, textStyle: t.body),
  );
}
