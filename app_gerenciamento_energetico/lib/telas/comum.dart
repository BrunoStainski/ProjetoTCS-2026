import 'package:flutter/material.dart';

import '../casa.dart';
import '../tema.dart';
import 'minha_casa.dart';

export '../casa.dart' show Consulta, EscolhaTarifa;

IconData iconeDaCategoria(String categoria) {
  if (categoria.startsWith('lampada')) return Icons.lightbulb_outline;
  if (categoria.startsWith('ventilador')) return Icons.wind_power;
  return switch (categoria) {
    'refrigerador' => Icons.kitchen,
    'televisor' => Icons.tv,
    'ar_condicionado' => Icons.ac_unit,
    'chuveiro' => Icons.shower,
    'microondas' => Icons.microwave,
    'maquina_de_lavar' => Icons.local_laundry_service,
    'bomba' => Icons.water_drop_outlined,
    _ => Icons.electrical_services,
  };
}

/// Marca do app: raio amarelo + "iamp".
class LogoIamp extends StatelessWidget {
  final double tamanho;

  const LogoIamp({super.key, this.tamanho = 22});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bolt, color: Cores.amarelo, size: tamanho + 4),
        Text('iamp',
            style: TextStyle(fontSize: tamanho, fontWeight: FontWeight.w800, letterSpacing: 1, color: Cores.branco)),
      ],
    );
  }
}

/// Estrutura de toda tela: barra com o titulo, botao "Minha casa" e largura maxima
/// (para o app ficar bom no navegador e no Windows).
class Pagina extends StatelessWidget {
  final String titulo;
  final Widget filho;
  final int? passo; // 1 a 4 no fluxo de calculo; null nas outras telas
  final bool mostrarCasa;
  final Widget? tituloWidget; // substitui o texto do titulo (ex.: logo na tela inicial)

  const Pagina({
    super.key,
    required this.titulo,
    required this.filho,
    this.passo,
    this.mostrarCasa = true,
    this.tituloWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: tituloWidget ?? Text(titulo),
        actions: [if (mostrarCasa) const BotaoCasa(), const SizedBox(width: 8)],
        bottom: passo == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(value: passo! / 4),
              ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(padding: const EdgeInsets.all(16), child: filho),
          ),
        ),
      ),
    );
  }
}

/// Abre "Minha casa"; o numero mostra quantos aparelhos ja foram adicionados.
class BotaoCasa extends StatelessWidget {
  const BotaoCasa({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: casa,
      builder: (context, _) => IconButton(
        tooltip: 'Minha casa',
        icon: Badge(
          isLabelVisible: !casa.vazia,
          label: Text('${casa.totalAparelhos}'),
          child: const Icon(Icons.home_outlined),
        ),
        onPressed: () => abrirMinhaCasa(context),
      ),
    );
  }
}

const rotaMinhaCasa = '/minha-casa';

void abrirMinhaCasa(BuildContext context) {
  // se "Minha casa" ja esta aberta mais atras, volta para ela em vez de abrir outra
  if (TelaMinhaCasa.abertas > 0) {
    Navigator.popUntil(context, ModalRoute.withName(rotaMinhaCasa));
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute(settings: const RouteSettings(name: rotaMinhaCasa), builder: (_) => const TelaMinhaCasa()),
  );
}

/// Cartao amarelo com o numero principal da tela (ex.: gasto por mes).
class CartaoDestaque extends StatelessWidget {
  final String titulo;
  final String valor;
  final String? rodape;

  const CartaoDestaque({super.key, required this.titulo, required this.valor, this.rodape});

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Card(
      color: Cores.amarelo,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(titulo, style: texto.titleMedium?.copyWith(color: Cores.preto)),
            Text(valor,
                style: texto.displaySmall?.copyWith(color: Cores.preto, fontWeight: FontWeight.w900)),
            if (rodape != null) Text(rodape!, style: const TextStyle(color: Cores.preto)),
          ],
        ),
      ),
    );
  }
}

/// Cartao pequeno com titulo e valor (ex.: Consumo / 41,25 kWh/mes).
class CartaoInfo extends StatelessWidget {
  final String titulo;
  final String valor;

  const CartaoInfo(this.titulo, this.valor, {super.key});

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(titulo, style: texto.labelMedium?.copyWith(color: Cores.cinza)),
            Text(valor, style: texto.titleMedium, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Avisos da API (impostos, estimativas, dados sinteticos...).
class ListaAvisos extends StatelessWidget {
  final List<String> avisos;

  const ListaAvisos(this.avisos, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final aviso in avisos)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 18, color: Cores.amarelo),
                const SizedBox(width: 8),
                Expanded(child: Text(aviso, style: const TextStyle(color: Cores.cinza, fontSize: 13))),
              ],
            ),
          ),
      ],
    );
  }
}

class Titulo extends StatelessWidget {
  final String texto;

  const Titulo(this.texto, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(texto, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Cores.amarelo)),
      );
}

class MensagemErro extends StatelessWidget {
  final String mensagem;
  final VoidCallback? tentarDeNovo;

  const MensagemErro(this.mensagem, {super.key, this.tentarDeNovo});

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Card(
      color: cores.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(mensagem, style: TextStyle(color: cores.onErrorContainer)),
            if (tentarDeNovo != null) TextButton(onPressed: tentarDeNovo, child: const Text('Tentar de novo')),
          ],
        ),
      ),
    );
  }
}
