// Identidade visual do iamp: fundo preto, amarelo de energia nos destaques e texto branco.
// Para mudar uma cor, mude so aqui.

import 'package:flutter/material.dart';

class Cores {
  static const preto = Color(0xFF000000);
  static const superficie = Color(0xFF111111); // cartoes
  static const superficieAlta = Color(0xFF1C1C1C); // campos e itens selecionados
  static const borda = Color(0xFF2E2E2E);
  static const amarelo = Color(0xFFFFD000);
  static const amareloEscuro = Color(0xFF2B2300); // fundo de destaque suave
  static const branco = Color(0xFFFFFFFF);
  static const cinza = Color(0xFFB0B0B0); // texto secundario
  static const erro = Color(0xFFFF6B6B);
}

ThemeData temaIamp() {
  const esquema = ColorScheme(
    brightness: Brightness.dark,
    primary: Cores.amarelo,
    onPrimary: Cores.preto,
    primaryContainer: Cores.amareloEscuro,
    onPrimaryContainer: Cores.amarelo,
    secondary: Cores.branco,
    onSecondary: Cores.preto,
    secondaryContainer: Cores.superficieAlta,
    onSecondaryContainer: Cores.branco,
    error: Cores.erro,
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
  final texto = base.textTheme.apply(bodyColor: Cores.branco, displayColor: Cores.branco);

  return base.copyWith(
    scaffoldBackgroundColor: Cores.preto,
    textTheme: texto,
    appBarTheme: const AppBarTheme(
      backgroundColor: Cores.preto,
      foregroundColor: Cores.branco,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: Cores.superficie,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: Cores.borda),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Cores.superficie,
      border: OutlineInputBorder(borderSide: BorderSide(color: Cores.borda)),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Cores.borda)),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Cores.amarelo, width: 2)),
      labelStyle: TextStyle(color: Cores.cinza),
      floatingLabelStyle: TextStyle(color: Cores.amarelo),
      helperStyle: TextStyle(color: Cores.cinza),
      hintStyle: TextStyle(color: Color(0xFF6E6E6E)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Cores.amarelo,
        foregroundColor: Cores.preto,
        minimumSize: const Size.fromHeight(48),
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Cores.branco,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: Cores.amarelo),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Cores.amarelo)),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Cores.amarelo,
      linearTrackColor: Cores.borda,
    ),
    dividerTheme: const DividerThemeData(color: Cores.borda),
    listTileTheme: const ListTileThemeData(iconColor: Cores.amarelo, textColor: Cores.branco),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Cores.superficieAlta,
      contentTextStyle: TextStyle(color: Cores.branco),
      actionTextColor: Cores.amarelo,
      behavior: SnackBarBehavior.floating,
    ),
    badgeTheme: const BadgeThemeData(backgroundColor: Cores.amarelo, textColor: Cores.preto),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: Cores.amarelo,
        selectedForegroundColor: Cores.preto,
        foregroundColor: Cores.branco,
        side: const BorderSide(color: Cores.borda),
      ),
    ),
  );
}
