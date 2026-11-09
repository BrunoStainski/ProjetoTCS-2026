// Identidade visual do iamp: fundo preto, amarelo de energia nos destaques e texto branco.
// Regra 60/30/10: 60% preto (fundo), 30% branco e superficies escuras, 10% amarelo
// (botoes e o valor principal). Verde e vermelho so aparecem quando tem significado:
// verde = economia / coisa boa, vermelho = alerta / erro.
// Para mudar uma cor ou um tamanho de texto, mude so aqui.

import 'package:flutter/material.dart';

class Cores {
  static const preto = Color(0xFF000000);
  static const superficie = Color(0xFF141414); // cartoes
  static const superficieAlta = Color(0xFF1F1F1F); // campos, menus
  // detalhes (bordas, contornos, icones) em amarelo; o texto continua branco
  static const borda = Color(0x8CFFD000); // amarelo 55%: cartoes, campos, botoes de contorno
  static const divisoria = Color(0x40FFD000); // amarelo 25%: linhas entre itens de lista
  static const trilho = Color(0xFF2A2A2A); // fundo das barras de progresso
  static const amarelo = Color(0xFFFFD000);
  static const amareloEscuro = Color(0xFF2B2300); // fundo de destaque suave
  static const verde = Color(0xFF3DDC84); // economia
  static const vermelho = Color(0xFFFF5C5C); // alerta
  // texto: hierarquia por opacidade do branco
  static const branco = Color(0xFFFFFFFF); // titulos e valores (100%)
  static const corpo = Color(0xCCFFFFFF); // texto corrido (80%)
  static const cinza = Color(0x99FFFFFF); // texto secundario (60%)
}

/// Escala de texto: 4 tamanhos (32, 20, 16, 13) e 2 pesos (normal e negrito).
class Estilos {
  static const _numeros = [FontFeature.tabularFigures()]; // digitos alinhados em valores

  static const valor = TextStyle(fontSize: 32, fontWeight: FontWeight.bold, fontFeatures: _numeros);
  static const titulo = TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Cores.branco);
  static const valorMedio = TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFeatures: _numeros);
  static const corpo = TextStyle(fontSize: 16, color: Cores.corpo);
  static const forte = TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Cores.branco);
  static const numero = TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFeatures: _numeros);
  static const secundario = TextStyle(fontSize: 13, color: Cores.cinza);
  static const rotulo = TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Cores.cinza);
}

/// Espacamentos em multiplos de 8 (e 4 para ajustes finos).
class Espaco {
  static const p = 8.0;
  static const m = 16.0;
  static const g = 24.0;
  static const gg = 32.0;
}

ThemeData temaIamp() {
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
    errorContainer: Color(0xFF3A1414),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Cores.preto,
    onSurface: Cores.branco,
    onSurfaceVariant: Cores.cinza,
    surfaceContainerLowest: Cores.preto,
    surfaceContainerLow: Cores.superficie,
    surfaceContainer: Cores.superficie,
    surfaceContainerHigh: Cores.superficieAlta,
    surfaceContainerHighest: Cores.superficieAlta,
    outline: Color(0xFF5A5A5A),
    outlineVariant: Cores.borda,
  );

  final base = ThemeData(colorScheme: esquema, useMaterial3: true);
  final texto = base.textTheme
      .copyWith(
        headlineSmall: Estilos.titulo.copyWith(fontSize: 20),
        titleLarge: Estilos.titulo,
        titleMedium: Estilos.forte,
        titleSmall: Estilos.rotulo,
        bodyLarge: Estilos.corpo,
        bodyMedium: Estilos.corpo,
        bodySmall: Estilos.secundario,
        labelLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        labelMedium: Estilos.rotulo,
      )
      .apply(bodyColor: Cores.corpo, displayColor: Cores.branco);

  const cantos = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16)));

  return base.copyWith(
    scaffoldBackgroundColor: Cores.preto,
    textTheme: texto,
    appBarTheme: const AppBarTheme(
      backgroundColor: Cores.preto,
      foregroundColor: Cores.branco,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: Estilos.titulo,
      iconTheme: IconThemeData(color: Cores.amarelo), // seta de voltar
      actionsIconTheme: IconThemeData(color: Cores.amarelo), // botao da casa
    ),
    iconTheme: const IconThemeData(color: Cores.amarelo),
    cardTheme: const CardThemeData(
      color: Cores.superficie,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: Cores.borda),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Cores.superficie,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Cores.borda),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Cores.amarelo, width: 2),
      ),
      labelStyle: TextStyle(color: Cores.cinza),
      floatingLabelStyle: TextStyle(color: Cores.amarelo),
      helperStyle: Estilos.secundario,
      hintStyle: TextStyle(color: Color(0x66FFFFFF)),
    ),
    // botoes com 52dp de altura: alvo de toque confortavel na zona do polegar
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Cores.amarelo,
        foregroundColor: Cores.preto,
        disabledBackgroundColor: const Color(0x66FFD000),
        minimumSize: const Size.fromHeight(52),
        shape: cantos,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Cores.branco,
        iconColor: Cores.amarelo,
        minimumSize: const Size.fromHeight(52),
        shape: cantos,
        side: const BorderSide(color: Cores.borda),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Cores.amarelo, minimumSize: const Size(48, 48)),
    ),
    // Android: alvo de toque minimo de 48dp em todos os botoes de icone
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: Cores.amarelo,
        disabledForegroundColor: const Color(0x4DFFD000),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Cores.amarelo, linearTrackColor: Cores.trilho),
    dividerTheme: const DividerThemeData(color: Cores.divisoria, space: 1),
    listTileTheme: const ListTileThemeData(
      iconColor: Cores.amarelo,
      textColor: Cores.branco,
      minVerticalPadding: 12,
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Cores.superficieAlta,
      contentTextStyle: const TextStyle(color: Cores.branco, fontSize: 16),
      actionTextColor: Cores.amarelo,
      behavior: SnackBarBehavior.floating,
      shape: cantos,
    ),
    badgeTheme: const BadgeThemeData(backgroundColor: Cores.amarelo, textColor: Cores.preto),
    popupMenuTheme: const PopupMenuThemeData(color: Cores.superficieAlta, shape: cantos),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style:
          SegmentedButton.styleFrom(
            selectedBackgroundColor: Cores.amarelo,
            selectedForegroundColor: Cores.preto,
            foregroundColor: Cores.branco,
            minimumSize: const Size(0, 48),
            side: const BorderSide(color: Cores.borda),
          ).copyWith(
            // icone amarelo; no segmento selecionado (fundo amarelo) fica preto
            iconColor: WidgetStateProperty.resolveWith(
              (estados) => estados.contains(WidgetState.selected) ? Cores.preto : Cores.amarelo,
            ),
          ),
    ),
  );
}
