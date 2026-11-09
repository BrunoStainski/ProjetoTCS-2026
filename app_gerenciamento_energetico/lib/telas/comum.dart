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
    'air_fryer' => Icons.soup_kitchen_outlined,
    'secador_cabelo' => Icons.air,
    'ferro_passar' => Icons.iron_outlined,
    'sanduicheira' => Icons.breakfast_dining_outlined,
    _ => Icons.electrical_services,
  };
}

class ControleTempo {
  final horas = TextEditingController();
  final minutos = TextEditingController();

  bool get vazio => horas.text.trim().isEmpty && minutos.text.trim().isEmpty;

  int? _parte(TextEditingController c) => c.text.trim().isEmpty ? 0 : int.tryParse(c.text.trim());

  bool get valido {
    if (vazio) return true;
    final h = _parte(horas);
    final m = _parte(minutos);
    return h != null && m != null && h >= 0 && m >= 0 && m < 60 && h * 60 + m <= 24 * 60;
  }

  double? get horasDia => vazio || !valido ? null : (_parte(horas)! * 60 + _parte(minutos)!) / 60;

  void definir(double? horasDia) {
    if (horasDia == null) {
      horas.clear();
      minutos.clear();
      return;
    }
    final total = (horasDia * 60).round();
    horas.text = '${total ~/ 60}';
    minutos.text = '${total % 60}';
  }

  void dispose() {
    horas.dispose();
    minutos.dispose();
  }
}

class CampoTempo extends StatelessWidget {
  final ControleTempo controle;
  final String rotulo;
  final String? ajuda;
  final VoidCallback? aoConfirmar;

  const CampoTempo({super.key, required this.controle, required this.rotulo, this.ajuda, this.aoConfirmar});

  @override
  Widget build(BuildContext context) {
    Widget parte(TextEditingController c, String nome, String sufixo) => Expanded(
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        onSubmitted: (_) => aoConfirmar?.call(),
        decoration: InputDecoration(labelText: nome, suffixText: sufixo),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rotulo, style: Estilos.forte),
        const SizedBox(height: Espaco.p),
        Row(
          children: [
            parte(controle.horas, 'Horas', 'h'),
            const SizedBox(width: Espaco.p),
            parte(controle.minutos, 'Minutos', 'min'),
          ],
        ),
        if (ajuda != null) ...[
          const SizedBox(height: 4),
          Text(ajuda!, style: Estilos.secundario),
        ],
      ],
    );
  }
}

/// Nome do tipo de aparelho para titulos (ex.: secoes da busca).
String tituloDaCategoria(String categoria) => switch (categoria) {
  'refrigerador' => 'Geladeiras',
  'televisor' => 'Televisores',
  'ar_condicionado' => 'Ar-condicionado',
  'ventilador_de_mesa' => 'Ventiladores de mesa',
  'ventilador_de_teto' => 'Ventiladores de teto',
  'chuveiro' => 'Chuveiros',
  'lampada_led' => 'Lâmpadas LED',
  'lampada_fluorescente' => 'Lâmpadas fluorescentes',
  'lampada_vapor_sodio' => 'Lâmpadas de vapor de sódio',
  'microondas' => 'Micro-ondas',
  'maquina_de_lavar' => 'Máquinas de lavar',
  'bomba' => "Bombas d'água",
  _ => categoria.isEmpty ? categoria : categoria[0].toUpperCase() + categoria.substring(1).replaceAll('_', ' '),
};

/// Tempo que o aviso "foi para a sua casa" fica na tela antes de sumir sozinho.
const duracaoAviso = Duration(seconds: 5);

/// Aviso de aparelho adicionado, com o botao "Ver" (abre Minha casa).
/// Desde o Flutter 3.29 um SnackBar com botao fica na tela ate alguem tocar (persist);
/// aqui ele some sozinho depois de [duracaoAviso].
/// Recebe o navegador e o messenger guardados antes: o aviso pode continuar depois de sair da tela.
void avisarAdicionado(ScaffoldMessengerState avisos, NavigatorState navegador, String texto) {
  avisos
    ..hideCurrentSnackBar() // adicionar varios seguidos nao enfileira avisos
    ..showSnackBar(
      SnackBar(
        content: Text(texto),
        duration: duracaoAviso,
        persist: false,
        action: SnackBarAction(label: 'Ver', onPressed: () => abrirMinhaCasaNo(navegador)),
      ),
    );
}

/// Marca do app: raio amarelo + "iamp".
class LogoIamp extends StatelessWidget {
  const LogoIamp({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bolt, color: Cores.amarelo, size: 28),
        Text(
          'iamp',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1, color: Cores.branco),
        ),
      ],
    );
  }
}

/// Estrutura de toda tela: barra com o titulo, botao "Minha casa", largura maxima
/// e, opcionalmente, o botao principal fixo embaixo (zona do polegar no celular).
class Pagina extends StatelessWidget {
  final String titulo;
  final Widget filho;
  final int? passo; // 1 a 4 no fluxo de calculo; null nas outras telas
  final bool mostrarCasa;
  final Widget? tituloWidget; // substitui o texto do titulo (ex.: logo na tela inicial)
  final Widget? rodape; // acao principal, fixa embaixo

  const Pagina({
    super.key,
    required this.titulo,
    required this.filho,
    this.passo,
    this.mostrarCasa = true,
    this.tituloWidget,
    this.rodape,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: tituloWidget ?? Text(titulo),
        actions: [
          if (mostrarCasa) const BotaoCasa(),
          const SizedBox(width: Espaco.p),
        ],
        bottom: passo == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(value: passo! / 4),
              ),
      ),
      body: SafeArea(
        bottom: rodape == null,
        child: _Largura(
          child: Padding(padding: const EdgeInsets.all(Espaco.m), child: filho),
        ),
      ),
      bottomNavigationBar: rodape == null
          ? null
          : DecoratedBox(
              decoration: const BoxDecoration(
                color: Cores.preto,
                border: Border(top: BorderSide(color: Cores.borda)),
              ),
              child: SafeArea(
                top: false,
                child: _Largura(
                  encolher: true,
                  child: Padding(padding: const EdgeInsets.fromLTRB(Espaco.m, 12, Espaco.m, Espaco.m), child: rodape),
                ),
              ),
            ),
    );
  }
}

/// Em tela larga (navegador, tablet) o conteudo fica centralizado com no maximo 640.
/// encolher: ocupa so a altura do conteudo (no rodape; sem isso o Align toma a tela inteira).
class _Largura extends StatelessWidget {
  final Widget child;
  final bool encolher;

  const _Largura({required this.child, this.encolher = false});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    heightFactor: encolher ? 1 : null,
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: child),
  );
}

/// Abre "Minha casa"; o numero mostra quantos aparelhos ja foram adicionados e pula quando muda.
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
          label: TweenAnimationBuilder<double>(
            key: ValueKey(casa.totalAparelhos),
            tween: Tween(begin: 1.6, end: 1),
            duration: const Duration(milliseconds: 400),
            curve: Curves.elasticOut,
            builder: (_, escala, filho) => Transform.scale(scale: escala, child: filho),
            child: Text('${casa.totalAparelhos}'),
          ),
          child: const Icon(Icons.home_outlined),
        ),
        onPressed: () => abrirMinhaCasa(context),
      ),
    );
  }
}

const rotaMinhaCasa = '/minha-casa';

void abrirMinhaCasa(BuildContext context) => abrirMinhaCasaNo(Navigator.of(context));

void abrirMinhaCasaNo(NavigatorState navegador) {
  // se "Minha casa" ja esta aberta mais atras, volta para ela em vez de abrir outra
  if (TelaMinhaCasa.abertas > 0) {
    navegador.popUntil(ModalRoute.withName(rotaMinhaCasa));
    return;
  }
  navegador.push(
    MaterialPageRoute(
      settings: const RouteSettings(name: rotaMinhaCasa),
      builder: (_) => const TelaMinhaCasa(),
    ),
  );
}

/// Numero que "conta" ate o valor quando aparece e quando muda (ex.: total da casa).
class ValorAnimado extends StatelessWidget {
  final double valor;
  final String Function(double) formatar;
  final TextStyle estilo;

  const ValorAnimado(this.valor, {super.key, required this.formatar, required this.estilo});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: valor),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(formatar(v), style: estilo, textAlign: TextAlign.center),
    );
  }
}

/// Valor principal da tela: fundo escuro, borda e brilho suave na cor do destaque.
/// Amarelo para gasto, verde para economia.
class CartaoDestaque extends StatelessWidget {
  final String titulo;
  final double valor;
  final String Function(double) formatar;
  final String? rodape;
  final Color cor;

  const CartaoDestaque({
    super.key,
    required this.titulo,
    required this.valor,
    required this.formatar,
    this.rodape,
    this.cor = Cores.amarelo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: Espaco.g, vertical: Espaco.g),
      decoration: BoxDecoration(
        color: Cores.superficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.7), width: 1.5),
        boxShadow: [BoxShadow(color: cor.withValues(alpha: 0.18), blurRadius: 32, spreadRadius: -4)],
      ),
      child: Column(
        children: [
          Text(titulo, style: Estilos.rotulo),
          const SizedBox(height: 4),
          ValorAnimado(
            valor,
            formatar: formatar,
            estilo: Estilos.valor.copyWith(color: cor),
          ),
          if (rodape != null) ...[
            const SizedBox(height: 4),
            Text(rodape!, style: Estilos.secundario, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// Cartao pequeno: rotulo discreto em cima, valor em destaque embaixo.
class CartaoInfo extends StatelessWidget {
  final String titulo;
  final String valor;

  const CartaoInfo(this.titulo, this.valor, {super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: Espaco.m),
        child: Column(
          children: [
            Text(titulo, style: Estilos.secundario),
            const SizedBox(height: 4),
            Text(
              valor,
              style: Estilos.numero.copyWith(color: Cores.branco),
              textAlign: TextAlign.center,
            ),
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
            padding: const EdgeInsets.only(bottom: Espaco.p),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 16, color: Cores.amarelo),
                const SizedBox(width: Espaco.p),
                Expanded(child: Text(aviso, style: Estilos.secundario)),
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
    padding: const EdgeInsets.only(top: Espaco.g, bottom: Espaco.p),
    child: Text(texto.toUpperCase(), style: Estilos.rotulo.copyWith(color: Cores.amarelo, letterSpacing: 0.8)),
  );
}

class MensagemErro extends StatelessWidget {
  final String mensagem;
  final VoidCallback? tentarDeNovo;

  const MensagemErro(this.mensagem, {super.key, this.tentarDeNovo});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1F0E0E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Cores.vermelho.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Espaco.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: Cores.vermelho),
                const SizedBox(width: 12),
                Expanded(child: Text(mensagem, style: Estilos.corpo)),
              ],
            ),
            if (tentarDeNovo != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: tentarDeNovo, child: const Text('Tentar de novo')),
              ),
          ],
        ),
      ),
    );
  }
}

/// Botao principal que vira "feito" com animacao (ex.: Adicionar -> Na sua casa).
class BotaoComConfirmacao extends StatelessWidget {
  final bool feito;
  final String textoAcao;
  final IconData iconeAcao;
  final VoidCallback onAcao;
  final String textoFeito;
  final VoidCallback onFeito;

  const BotaoComConfirmacao({
    super.key,
    required this.feito,
    required this.textoAcao,
    required this.iconeAcao,
    required this.onAcao,
    required this.textoFeito,
    required this.onFeito,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (filho, animacao) => ScaleTransition(
        scale: Tween(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: animacao, curve: Curves.easeOutBack)),
        child: FadeTransition(opacity: animacao, child: filho),
      ),
      child: feito
          ? OutlinedButton.icon(
              key: const ValueKey('feito'),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Cores.verde)),
              onPressed: onFeito,
              icon: const Icon(Icons.check_circle, color: Cores.verde),
              label: Text(textoFeito),
            )
          : FilledButton.icon(
              key: const ValueKey('acao'),
              onPressed: onAcao,
              icon: Icon(iconeAcao),
              label: Text(textoAcao),
            ),
    );
  }
}
