// Pecas usadas por varias telas: estrutura da pagina, cartoes de opcao, valores em destaque,
// avisos e erros. Cores, textos e tamanhos vem do tema (Iamp.de(context)).

import 'package:flutter/material.dart';

import '../casa.dart';
import '../navegacao.dart';
import '../tema.dart';

export '../casa.dart' show Consulta, EscolhaTarifa;

/// Fonte do sistema muito aumentada (150% ou mais): as telas empilham o que ficaria lado a lado.
bool fonteGrande(BuildContext context) => MediaQuery.textScalerOf(context).scale(10) >= 15;

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
    'liquidificador' => Icons.blender_outlined,
    'cafeteira_eletrica' => Icons.coffee_maker_outlined,
    'chaleira_eletrica' => Icons.emoji_food_beverage_outlined,
    'forno_eletrico' => Icons.microwave_outlined,
    'aspirador_po' => Icons.cleaning_services_outlined,
    'torradeira' => Icons.breakfast_dining_outlined,
    _ => Icons.electrical_services,
  };
}

String _primeiraMaiuscula(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');

/// Nome de um aparelho do tipo (ex.: botoes da escolha do tipo, linha do item na casa).
String nomeDaCategoria(String categoria) => switch (categoria) {
  'refrigerador' => 'Geladeira ou freezer',
  'televisor' => 'Televisão',
  'ar_condicionado' => 'Ar-condicionado',
  'ventilador_de_mesa' => 'Ventilador de mesa',
  'ventilador_de_teto' => 'Ventilador de teto',
  'chuveiro' => 'Chuveiro elétrico',
  'lampada_led' => 'Lâmpada LED',
  'lampada_fluorescente' => 'Lâmpada fluorescente',
  'lampada_vapor_sodio' => 'Lâmpada de vapor de sódio',
  'microondas' => 'Micro-ondas',
  'maquina_de_lavar' => 'Máquina de lavar',
  'bomba' => "Bomba d'água",
  _ => _primeiraMaiuscula(categoria),
};

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
  _ => _primeiraMaiuscula(categoria),
};

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

  void limpar() => definir(null);

  void dispose() {
    horas.dispose();
    minutos.dispose();
  }
}

/// Tempo de uso em dois campos (horas e minutos). Com fonte grande, um embaixo do outro.
class CampoTempo extends StatelessWidget {
  final ControleTempo controle;
  final String? rotulo;
  final String? ajuda;
  final VoidCallback? aoConfirmar;

  const CampoTempo({super.key, required this.controle, this.rotulo, this.ajuda, this.aoConfirmar});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    Widget parte(TextEditingController c, String nome, String sufixo) => TextField(
      controller: c,
      keyboardType: TextInputType.number,
      onSubmitted: (_) => aoConfirmar?.call(),
      decoration: InputDecoration(labelText: nome, suffixText: sufixo),
    );
    final horas = parte(controle.horas, 'Horas', 'h');
    final minutos = parte(controle.minutos, 'Minutos', 'min');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rotulo != null) ...[
          Text(rotulo!, style: t.forte),
          const SizedBox(height: Espaco.p),
        ],
        if (fonteGrande(context)) ...[
          horas,
          const SizedBox(height: Espaco.pm),
          minutos,
        ] else
          Row(
            children: [
              Expanded(child: horas),
              const SizedBox(width: Espaco.p),
              Expanded(child: minutos),
            ],
          ),
        if (ajuda != null) ...[
          const SizedBox(height: Espaco.p),
          Text(ajuda!, style: t.secundario),
        ],
      ],
    );
  }
}

/// Tempo que o aviso "foi para a sua casa" fica na tela antes de sumir sozinho.
const duracaoAviso = Duration(seconds: 5);

/// Aviso de aparelho adicionado, com o botao "Ver" (abre a aba Minha casa).
/// Desde o Flutter 3.29 um SnackBar com botao fica na tela ate alguem tocar (persist);
/// aqui ele some sozinho depois de [duracaoAviso].
/// Recebe o messenger guardado antes: o aviso pode continuar depois de sair da tela.
void avisarAdicionado(ScaffoldMessengerState avisos, String texto) {
  avisos
    ..hideCurrentSnackBar() // adicionar varios seguidos nao enfileira avisos
    ..showSnackBar(
      SnackBar(
        content: Text(texto),
        duration: duracaoAviso,
        persist: false,
        action: SnackBarAction(label: 'Ver', onPressed: () => irPara(Aba.casa, fecharAtual: true)),
      ),
    );
}

/// Marca do app: raio amarelo + "Iamp".
class LogoIamp extends StatelessWidget {
  const LogoIamp({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Semantics(
      label: 'Iamp',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, color: t.destaque, size: t.iconeGrande),
          Text('Iamp', style: t.titulo.copyWith(letterSpacing: 1)),
        ],
      ),
    );
  }
}

/// Em qual etapa do fluxo a pessoa esta (ex.: 2 de 6). Aparece em texto e na barra.
class Etapa {
  final int atual;
  final int total;

  const Etapa(this.atual, this.total);
}

/// Calculo de um aparelho do catalogo: tipo, modelo, uso, estado, distribuidora e resultado.
const totalEtapas = 6;

/// Etapa do calculo do catalogo. A estimativa (aparelho fora do catalogo) tem as proprias perguntas
/// e nao mostra essa contagem.
Etapa? etapaDoCalculo(Consulta consulta, int atual) => consulta.estimado ? null : Etapa(atual, totalEtapas);

/// Estrutura de toda tela: barra com o titulo, largura maxima, etapa do fluxo (opcional)
/// e o botao principal fixo embaixo (zona do polegar no celular).
class Pagina extends StatelessWidget {
  final String titulo;
  final Widget filho;
  final Etapa? etapa;
  final Widget? tituloWidget; // substitui o texto do titulo (ex.: logo na tela inicial)
  final Widget? rodape; // acao principal, fixa embaixo

  const Pagina({super.key, required this.titulo, required this.filho, this.etapa, this.tituloWidget, this.rodape});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    // com fonte grande a barra de cima cresce junto (ate 1,75x) para o titulo nao cortar
    final alturaBarra = MediaQuery.textScalerOf(context).scale(kToolbarHeight).clamp(kToolbarHeight, kToolbarHeight * 1.75);
    final e = etapa;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: alturaBarra,
        title: tituloWidget ?? Text(titulo, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        bottom: rodape == null,
        child: _Largura(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (e != null) ...[
                LinearProgressIndicator(
                  value: e.atual / e.total,
                  minHeight: t.barraProgresso / 2,
                  semanticsLabel: 'Etapa ${e.atual} de ${e.total}',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Espaco.m, Espaco.pm, Espaco.m, 0),
                  child: ExcludeSemantics(child: Text('Etapa ${e.atual} de ${e.total}', style: t.rotulo)),
                ),
              ],
              Expanded(
                child: Padding(padding: const EdgeInsets.all(Espaco.m), child: filho),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: rodape == null
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: t.borda)),
              ),
              child: SafeArea(
                top: false,
                child: _Largura(
                  encolher: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Espaco.m, Espaco.pm, Espaco.m, Espaco.m),
                    child: rodape,
                  ),
                ),
              ),
            ),
    );
  }
}

/// Em tela larga (navegador, tablet) o conteudo fica centralizado com largura maxima.
/// encolher: ocupa so a altura do conteudo (no rodape; sem isso o Align toma a tela inteira).
class _Largura extends StatelessWidget {
  final Widget child;
  final bool encolher;

  const _Largura({required this.child, this.encolher = false});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    heightFactor: encolher ? 1 : null,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: Iamp.de(context).larguraMaxima),
      child: child,
    ),
  );
}

/// A pergunta da etapa, grande, com uma explicacao curta embaixo.
class CabecalhoPergunta extends StatelessWidget {
  final String pergunta;
  final String? ajuda;

  const CabecalhoPergunta(this.pergunta, {super.key, this.ajuda});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Espaco.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(pergunta, style: t.pergunta)),
          if (ajuda != null) ...[
            const SizedBox(height: Espaco.p),
            Text(ajuda!, style: t.secundario),
          ],
        ],
      ),
    );
  }
}

/// Opcao grande para tocar (uma decisao por tela). Mostra um sinal de "escolhido"
/// alem da cor, e o leitor de tela anuncia o titulo, a explicacao e se esta selecionada.
class CartaoOpcao extends StatelessWidget {
  final IconData? icone;
  final String titulo;
  final String? subtitulo;
  final bool selecionada;
  final VoidCallback onTap;

  const CartaoOpcao({
    super.key,
    this.icone,
    required this.titulo,
    this.subtitulo,
    this.selecionada = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      color: selecionada ? t.fundoDestaque : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.raio),
        side: BorderSide(color: selecionada ? t.destaque : t.borda, width: selecionada ? 2 : 1),
      ),
      child: Semantics(
        selected: selecionada,
        button: true,
        child: ListTile(
          leading: icone == null ? null : Icon(icone, size: t.iconeGrande),
          title: Text(titulo),
          subtitle: subtitulo == null ? null : Text(subtitulo!),
          trailing: Icon(selecionada ? Icons.check_circle : Icons.chevron_right, color: t.destaque),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Numero que "conta" ate o valor quando aparece e quando muda (ex.: total da casa).
/// O leitor de tela ouve so o valor final, nao os numeros intermediarios.
class ValorAnimado extends StatelessWidget {
  final double valor;
  final String Function(double) formatar;
  final TextStyle estilo;

  const ValorAnimado(this.valor, {super.key, required this.formatar, required this.estilo});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: formatar(valor),
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: valor),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(formatar(v), style: estilo, textAlign: TextAlign.center),
      ),
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
  final Color? cor;

  const CartaoDestaque({
    super.key,
    required this.titulo,
    required this.valor,
    required this.formatar,
    this.rodape,
    this.cor,
  });

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final c = cor ?? t.destaque;
    return MergeSemantics(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: Espaco.pp),
        padding: const EdgeInsets.all(Espaco.g),
        decoration: t.cartaoDestaque(c),
        child: Column(
          children: [
            Text(titulo, style: t.rotulo, textAlign: TextAlign.center),
            const SizedBox(height: Espaco.pp),
            ValorAnimado(valor, formatar: formatar, estilo: t.valor.copyWith(color: c)),
            if (rodape != null) ...[
              const SizedBox(height: Espaco.pp),
              Text(rodape!, style: t.secundario, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

/// Cartao pequeno: rotulo discreto em cima, valor em destaque embaixo.
class CartaoInfo extends StatelessWidget {
  final String titulo;
  final String valor;
  final String? detalhe;

  const CartaoInfo(this.titulo, this.valor, {super.key, this.detalhe});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return MergeSemantics(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Espaco.pm, vertical: Espaco.m),
          child: Column(
            children: [
              Text(titulo, style: t.secundario, textAlign: TextAlign.center),
              const SizedBox(height: Espaco.pp),
              Text(valor, style: t.numero, textAlign: TextAlign.center),
              if (detalhe != null) Text(detalhe!, style: t.secundario, textAlign: TextAlign.center),
            ],
          ),
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
    final t = Iamp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final aviso in avisos)
          Padding(
            padding: const EdgeInsets.only(bottom: Espaco.p),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.info_outline, size: t.icone - 4, color: t.destaque),
                ),
                const SizedBox(width: Espaco.p),
                Expanded(child: Text(aviso, style: t.secundario)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Titulo de secao (em amarelo, com o leitor de tela anunciando como cabecalho).
class Titulo extends StatelessWidget {
  final String texto;

  const Titulo(this.texto, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Padding(
      padding: const EdgeInsets.only(top: Espaco.g, bottom: Espaco.p),
      child: Semantics(
        header: true,
        child: Text(texto, style: t.forte.copyWith(color: t.destaque)),
      ),
    );
  }
}

/// Erro com icone e texto (nao so a cor vermelha) e, quando da, o botao de tentar de novo.
class MensagemErro extends StatelessWidget {
  final String mensagem;
  final VoidCallback? tentarDeNovo;

  const MensagemErro(this.mensagem, {super.key, this.tentarDeNovo});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Semantics(
      liveRegion: true,
      child: Card(
        color: t.fundoErro,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.raio),
          side: BorderSide(color: t.alerta.withValues(alpha: 0.7)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Espaco.m),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: t.alerta),
                  const SizedBox(width: Espaco.pm),
                  Expanded(child: Text(mensagem, style: t.corpo)),
                ],
              ),
              if (tentarDeNovo != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: tentarDeNovo,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar de novo'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carregando, com uma frase do que esta acontecendo (nao so a rodinha).
class Carregando extends StatelessWidget {
  final String texto;

  const Carregando({super.key, this.texto = 'Carregando...'});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Espaco.g),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: Espaco.m),
            Text(texto, style: t.secundario, textAlign: TextAlign.center),
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
    final t = Iamp.de(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (filho, animacao) => ScaleTransition(
        scale: Tween(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: animacao, curve: Curves.easeOutBack)),
        child: FadeTransition(opacity: animacao, child: filho),
      ),
      child: feito
          ? OutlinedButton.icon(
              key: const ValueKey('feito'),
              style: OutlinedButton.styleFrom(side: BorderSide(color: t.economia)),
              onPressed: onFeito,
              icon: Icon(Icons.check_circle, color: t.economia),
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

/// Barra de "quanto do total" com o numero escrito ao lado (nao so o tamanho da barra).
class BarraParte extends StatelessWidget {
  final double fracao;
  final String descricao;

  const BarraParte(this.fracao, {super.key, required this.descricao});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fracao.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(t.raioPequeno / 2),
        child: LinearProgressIndicator(value: v, minHeight: t.barraProgresso, semanticsLabel: descricao),
      ),
    );
  }
}

/// Dois blocos lado a lado com a mesma altura; com fonte grande, um embaixo do outro.
class LadoALado extends StatelessWidget {
  final Widget esquerda;
  final Widget direita;
  final Widget? meio;

  const LadoALado(this.esquerda, this.direita, {super.key, this.meio});

  @override
  Widget build(BuildContext context) {
    if (fonteGrande(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [esquerda, if (meio != null) Center(child: RotatedBox(quarterTurns: 1, child: meio)), direita],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: esquerda),
          meio == null ? const SizedBox(width: Espaco.p) : Center(child: meio),
          Expanded(child: direita),
        ],
      ),
    );
  }
}
