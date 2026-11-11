import 'dart:async';

// Pecas usadas por varias telas: estrutura da pagina, cartoes de opcao, valores em destaque,
// avisos e erros. Cores, textos e tamanhos vem do tema (Iamp.de(context)).

import 'package:flutter/material.dart';

import '../casa.dart';
import '../idioma.dart';
import '../navegacao.dart';
import '../tema.dart';

export '../casa.dart' show Query, TariffChoice;

/// Fonte do sistema muito aumentada (150% ou mais): as telas empilham o que ficaria lado a lado.
bool largeFont(BuildContext context) => MediaQuery.textScalerOf(context).scale(10) >= 15;

IconData categoryIcon(String category) {
  if (category.startsWith('lampada')) return Icons.lightbulb_outline;
  if (category.startsWith('ventilador')) return Icons.wind_power;
  return switch (category) {
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

String _capitalizeFirst(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');

/// Nome de um aparelho do tipo (ex.: botoes da escolha do tipo, linha do item na casa).
String categoryName(String category) => switch (category) {
  'refrigerador' => tr('Geladeira ou freezer', 'Fridge or freezer'),
  'televisor' => tr('Televisão', 'TV'),
  'ar_condicionado' => tr('Ar-condicionado', 'Air conditioner'),
  'ventilador_de_mesa' => tr('Ventilador de mesa', 'Desk fan'),
  'ventilador_de_teto' => tr('Ventilador de teto', 'Ceiling fan'),
  'chuveiro' => tr('Chuveiro elétrico', 'Electric shower'),
  'lampada_led' => tr('Lâmpada LED', 'LED bulb'),
  'lampada_fluorescente' => tr('Lâmpada fluorescente', 'Fluorescent bulb'),
  'lampada_vapor_sodio' => tr('Lâmpada de vapor de sódio', 'Sodium vapor lamp'),
  'microondas' => tr('Micro-ondas', 'Microwave'),
  'maquina_de_lavar' => tr('Máquina de lavar', 'Washing machine'),
  'bomba' => tr("Bomba d'água", 'Water pump'),
  // eletroportateis (tabela portateis da API)
  'air_fryer' => 'Air fryer',
  'secador_cabelo' => tr('Secador de cabelo', 'Hair dryer'),
  'ferro_passar' => tr('Ferro de passar', 'Clothes iron'),
  'sanduicheira' => tr('Sanduicheira', 'Sandwich maker'),
  'liquidificador' => tr('Liquidificador', 'Blender'),
  'cafeteira_eletrica' => tr('Cafeteira elétrica', 'Coffee maker'),
  'chaleira_eletrica' => tr('Chaleira elétrica', 'Electric kettle'),
  'forno_eletrico' => tr('Forno elétrico de bancada', 'Countertop electric oven'),
  'aspirador_po' => tr('Aspirador de pó', 'Vacuum cleaner'),
  'torradeira' => tr('Torradeira', 'Toaster'),
  _ => _capitalizeFirst(category),
};

/// Nome do tipo de aparelho para titulos (ex.: secoes da busca).
String categoryTitle(String category) => switch (category) {
  'refrigerador' => tr('Geladeiras', 'Fridges'),
  'televisor' => tr('Televisores', 'TVs'),
  'ar_condicionado' => tr('Ar-condicionado', 'Air conditioners'),
  'ventilador_de_mesa' => tr('Ventiladores de mesa', 'Desk fans'),
  'ventilador_de_teto' => tr('Ventiladores de teto', 'Ceiling fans'),
  'chuveiro' => tr('Chuveiros', 'Electric showers'),
  'lampada_led' => tr('Lâmpadas LED', 'LED bulbs'),
  'lampada_fluorescente' => tr('Lâmpadas fluorescentes', 'Fluorescent bulbs'),
  'lampada_vapor_sodio' => tr('Lâmpadas de vapor de sódio', 'Sodium vapor lamps'),
  'microondas' => tr('Micro-ondas', 'Microwaves'),
  'maquina_de_lavar' => tr('Máquinas de lavar', 'Washing machines'),
  'bomba' => tr("Bombas d'água", 'Water pumps'),
  _ => _capitalizeFirst(category),
};

/// Velocidade do ventilador como a API manda ("media") para a tela ("Média").
String speedName(String speed) => switch (speed) {
  'baixa' => tr('Baixa', 'Low'),
  'media' => tr('Média', 'Medium'),
  'alta' => tr('Alta', 'High'),
  _ => _capitalizeFirst(speed),
};

/// Perfil do K-Means como a API manda ("Consciente", a chave do perfil) para a tela.
String profileName(String profile) => switch (profile) {
  'Consciente' => tr('Consciente', 'Efficient'),
  'Moderado' => tr('Moderado', 'Moderate'),
  'Ineficiente' => tr('Ineficiente', 'Inefficient'),
  _ => profile,
};

class TimeControl {
  final hours = TextEditingController();
  final minutes = TextEditingController();

  bool get isEmpty => hours.text.trim().isEmpty && minutes.text.trim().isEmpty;

  int? _part(TextEditingController c) => c.text.trim().isEmpty ? 0 : int.tryParse(c.text.trim());

  bool get valid {
    if (isEmpty) return true;
    final h = _part(hours);
    final m = _part(minutes);
    return h != null && m != null && h >= 0 && m >= 0 && m < 60 && h * 60 + m <= 24 * 60;
  }

  double? get dailyHours => isEmpty || !valid ? null : (_part(hours)! * 60 + _part(minutes)!) / 60;

  void define(double? dailyHours) {
    if (dailyHours == null) {
      hours.clear();
      minutes.clear();
      return;
    }
    final total = (dailyHours * 60).round();
    hours.text = '${total ~/ 60}';
    minutes.text = '${total % 60}';
  }

  void clear() => define(null);

  void dispose() {
    hours.dispose();
    minutes.dispose();
  }
}

/// Tempo de uso em dois campos (horas e minutos). Com fonte grande, um embaixo do outro.
class TimeField extends StatelessWidget {
  final TimeControl control;
  final String? label;
  final String? help;
  final VoidCallback? onConfirm;

  const TimeField({super.key, required this.control, this.label, this.help, this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    Widget piece(TextEditingController c, String name, String suffix) => TextField(
      controller: c,
      keyboardType: TextInputType.number,
      onSubmitted: (_) => onConfirm?.call(),
      decoration: InputDecoration(labelText: name, suffixText: suffix),
    );
    final hours = piece(control.hours, tr('Horas', 'Hours'), 'h');
    final minutes = piece(control.minutes, tr('Minutos', 'Minutes'), 'min');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: t.strong),
          const SizedBox(height: Spacing.p),
        ],
        if (largeFont(context)) ...[
          hours,
          const SizedBox(height: Spacing.pm),
          minutes,
        ] else
          Row(
            children: [
              Expanded(child: hours),
              const SizedBox(width: Spacing.p),
              Expanded(child: minutes),
            ],
          ),
        if (help != null) ...[
          const SizedBox(height: Spacing.p),
          Text(help!, style: t.secondary),
        ],
      ],
    );
  }
}

/// Tempo que o aviso "foi para a sua casa" fica na tela antes de sumir sozinho.
const noticeDuration = Duration(seconds: 5);

/// Aviso de aparelho adicionado, com o botao "Ver" (abre a aba Minha casa).
/// Desde o Flutter 3.29 um SnackBar com botao fica na tela ate alguem tocar (persist);
/// aqui ele some sozinho depois de [noticeDuration].
/// Recebe o messenger guardado antes: o aviso pode continuar depois de sair da tela.
void notifyAdded(ScaffoldMessengerState notices, String text) {
  notices
    ..hideCurrentSnackBar() // adicionar varios seguidos nao enfileira avisos
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        duration: noticeDuration,
        persist: false,
        action: SnackBarAction(label: tr('Ver', 'View'), onPressed: () => goTo(AppTab.home, closeCurrent: true)),
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
          Icon(Icons.bolt, color: t.highlight, size: t.largeIcon),
          Text('Iamp', style: t.title.copyWith(letterSpacing: 1)),
        ],
      ),
    );
  }
}

/// Marca do app no menu e nas boas-vindas: o icone (quadrado preto com o raio) com contorno
/// amarelo esmaecido e brilho suave, e o nome ao lado.
class IampBrand extends StatelessWidget {
  final double size; // lado do quadrado do icone
  final double? nameSize; // padrao: o titulo do app (22)

  const IampBrand({super.key, this.size = 48, this.nameSize});

  static const image = 'assets/icone/icone.png';

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final radius = BorderRadius.circular(size * 0.22);
    final icon = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: radius,
        border: Border.all(color: t.highlight.withValues(alpha: 0.35), width: size >= 72 ? 2 : 1.5),
        boxShadow: [BoxShadow(color: t.highlight.withValues(alpha: 0.18), blurRadius: size * 0.4)],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          image,
          fit: BoxFit.cover,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        ),
      ),
    );
    final name = Text('Iamp', style: t.title.copyWith(fontSize: nameSize, letterSpacing: 1));
    return Semantics(
      label: 'Iamp',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          SizedBox(width: size * 0.25),
          // com a fonte do sistema muito grande o nome encolhe em vez de passar da tela
          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: name)),
        ],
      ),
    );
  }
}

/// Em qual etapa do fluxo a pessoa esta (ex.: 2 de 6). Aparece em texto e na barra.
class FlowStep {
  final int current;
  final int total;

  const FlowStep(this.current, this.total);
}

/// Calculo de um aparelho do catalogo: tipo, modelo, uso, estado, distribuidora e resultado.
const totalSteps = 6;

/// Etapa do calculo do catalogo. A estimativa (aparelho fora do catalogo) tem as proprias perguntas
/// e nao mostra essa contagem.
FlowStep? calculationStep(Query query, int current) => query.estimated ? null : FlowStep(current, totalSteps);

/// Estrutura de toda tela: barra com o titulo, largura maxima, etapa do fluxo (opcional)
/// e o botao principal fixo embaixo (zona do polegar no celular).
class AppPage extends StatelessWidget {
  final String title;
  final Widget child;
  final FlowStep? step;
  final Widget? widgetTitle; // substitui o texto do titulo (ex.: logo na tela inicial)
  final Widget? footer; // acao principal, fixa embaixo

  const AppPage({super.key, required this.title, required this.child, this.step, this.widgetTitle, this.footer});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    // com fonte grande a barra de cima cresce junto (ate 1,75x) para o titulo nao cortar
    final barHeight = MediaQuery.textScalerOf(context).scale(kToolbarHeight).clamp(kToolbarHeight, kToolbarHeight * 1.75);
    final e = step;
    // botao do menu de acesso rapido na primeira tela de cada aba (nas outras fica a seta de voltar).
    // O menu mora na casca das abas (inicio.dart); fora dela (testes de uma tela so) nao aparece.
    final shell = Scaffold.maybeOf(context);
    final withMenu = (shell?.hasDrawer ?? false) && (ModalRoute.of(context)?.isFirst ?? false);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: barHeight,
        leading: withMenu ? IconButton(icon: const Icon(Icons.menu), tooltip: 'Menu', onPressed: shell!.openDrawer) : null,
        title: widgetTitle ?? Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        bottom: footer == null,
        child: _Width(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (e != null) ...[
                LinearProgressIndicator(
                  value: e.current / e.total,
                  minHeight: t.progressBar / 2,
                  semanticsLabel: tr('Etapa ${e.current} de ${e.total}', 'Step ${e.current} of ${e.total}'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.m, Spacing.pm, Spacing.m, 0),
                  child: ExcludeSemantics(
                    child: Text(tr('Etapa ${e.current} de ${e.total}', 'Step ${e.current} of ${e.total}'), style: t.label),
                  ),
                ),
              ],
              Expanded(
                child: Padding(padding: const EdgeInsets.all(Spacing.m), child: child),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: footer == null
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: t.border)),
              ),
              child: SafeArea(
                top: false,
                child: _Width(
                  shrink: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Spacing.m, Spacing.pm, Spacing.m, Spacing.m),
                    child: footer,
                  ),
                ),
              ),
            ),
    );
  }
}

/// Em tela larga (navegador, tablet) o conteudo fica centralizado com largura maxima.
/// encolher: ocupa so a altura do conteudo (no rodape; sem isso o Align toma a tela inteira).
class _Width extends StatelessWidget {
  final Widget child;
  final bool shrink;

  const _Width({required this.child, this.shrink = false});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    heightFactor: shrink ? 1 : null,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: Iamp.de(context).maxWidth),
      child: child,
    ),
  );
}

/// A pergunta da etapa, grande, com uma explicacao curta embaixo.
class QuestionHeader extends StatelessWidget {
  final String question;
  final String? help;

  const QuestionHeader(this.question, {super.key, this.help});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(question, style: t.question)),
          if (help != null) ...[
            const SizedBox(height: Spacing.p),
            Text(help!, style: t.secondary),
          ],
        ],
      ),
    );
  }
}

/// Opcao grande para tocar (uma decisao por tela). Mostra um sinal de "escolhido"
/// alem da cor, e o leitor de tela anuncia o titulo, a explicacao e se esta selecionada.
class OptionCard extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const OptionCard({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? t.highlightBackground : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius),
        side: BorderSide(color: selected ? t.highlight : t.border, width: selected ? 2 : 1),
      ),
      child: Semantics(
        selected: selected,
        button: true,
        child: ListTile(
          leading: icon == null ? null : Icon(icon, size: t.largeIcon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle!),
          trailing: Icon(selected ? Icons.check_circle : Icons.chevron_right, color: t.highlight),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Numero que "conta" ate o valor quando aparece e quando muda (ex.: total da casa).
/// O leitor de tela ouve so o valor final, nao os numeros intermediarios.
class AnimatedValue extends StatelessWidget {
  final double value;
  final String Function(double) format;
  final TextStyle style;

  const AnimatedValue(this.value, {super.key, required this.format, required this.style});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: format(value),
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(format(v), style: style, textAlign: TextAlign.center),
      ),
    );
  }
}

/// Valor principal da tela: fundo escuro, borda e brilho suave na cor do destaque.
/// Amarelo para gasto, verde para economia.
class HighlightCard extends StatelessWidget {
  final String title;
  final double value;
  final String Function(double) format;
  final String? footer;
  final Color? cor;

  const HighlightCard({
    super.key,
    required this.title,
    required this.value,
    required this.format,
    this.footer,
    this.cor,
  });

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final c = cor ?? t.highlight;
    return MergeSemantics(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: Spacing.pp),
        padding: const EdgeInsets.all(Spacing.g),
        decoration: t.highlightCard(c),
        child: Column(
          children: [
            Text(title, style: t.label, textAlign: TextAlign.center),
            const SizedBox(height: Spacing.pp),
            AnimatedValue(value, format: format, style: t.value.copyWith(color: c)),
            if (footer != null) ...[
              const SizedBox(height: Spacing.pp),
              Text(footer!, style: t.secondary, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

/// Cartao pequeno: rotulo discreto em cima, valor em destaque embaixo.
class InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final String? detail;

  const InfoCard(this.title, this.value, {super.key, this.detail});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return MergeSemantics(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.pm, vertical: Spacing.m),
          child: Column(
            children: [
              Text(title, style: t.secondary, textAlign: TextAlign.center),
              const SizedBox(height: Spacing.pp),
              Text(value, style: t.number, textAlign: TextAlign.center),
              if (detail != null) Text(detail!, style: t.secondary, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avisos da API (impostos, estimativas, dados sinteticos...).
class NoticeList extends StatelessWidget {
  final List<String> notices;

  const NoticeList(this.notices, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final notice in notices)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.p),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.info_outline, size: t.icon - 4, color: t.highlight),
                ),
                const SizedBox(width: Spacing.p),
                Expanded(child: Text(notice, style: t.secondary)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Titulo de secao (em amarelo, com o leitor de tela anunciando como cabecalho).
class SectionTitle extends StatelessWidget {
  final String text;

  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.g, bottom: Spacing.p),
      child: Semantics(
        header: true,
        child: Text(text, style: t.strong.copyWith(color: t.highlight)),
      ),
    );
  }
}

/// Erro com icone e texto (nao so a cor vermelha) e, quando da, o botao de tentar de novo.
class ErrorMessage extends StatelessWidget {
  final String message;
  final VoidCallback? tryAgain;

  const ErrorMessage(this.message, {super.key, this.tryAgain});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Semantics(
      liveRegion: true,
      child: Card(
        color: t.errorBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radius),
          side: BorderSide(color: t.alert.withValues(alpha: 0.7)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.m),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: t.alert),
                  const SizedBox(width: Spacing.pm),
                  Expanded(child: Text(message, style: t.body)),
                ],
              ),
              if (tryAgain != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: tryAgain,
                    icon: const Icon(Icons.refresh),
                    label: Text(tr('Tentar de novo', 'Try again')),
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
class Loading extends StatefulWidget {
  final String? text; // padrao: "Carregando..."

  const Loading({super.key, this.text});

  /// Depois desse tempo carregando, explica que o servidor pode estar acordando (Render gratis).
  static const waitBeforeHint = Duration(seconds: 8);

  @override
  State<Loading> createState() => _LoadingState();
}

class _LoadingState extends State<Loading> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(Loading.waitBeforeHint, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.g),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: Spacing.m),
            Text(widget.text ?? tr('Carregando...', 'Loading...'), style: t.secondary, textAlign: TextAlign.center),
            if (_slow) ...[
              const SizedBox(height: Spacing.p),
              Semantics(
                liveRegion: true,
                child: Text(
                  tr(
                    'O servidor estava em repouso e está acordando. Da primeira vez pode levar até 1 minuto.',
                    'The server was asleep and is waking up. The first time it can take up to 1 minute.',
                  ),
                  style: t.secondary,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Botao principal que vira "feito" com animacao (ex.: Adicionar -> Na sua casa).
class ConfirmButton extends StatelessWidget {
  final bool done;
  final String actionText;
  final IconData actionIcon;
  final VoidCallback onAction;
  final String doneText;
  final VoidCallback onDone;

  const ConfirmButton({
    super.key,
    required this.done,
    required this.actionText,
    required this.actionIcon,
    required this.onAction,
    required this.doneText,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: Tween(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: done
          ? OutlinedButton.icon(
              key: const ValueKey('feito'),
              style: OutlinedButton.styleFrom(side: BorderSide(color: t.savings)),
              onPressed: onDone,
              icon: Icon(Icons.check_circle, color: t.savings),
              label: Text(doneText),
            )
          : FilledButton.icon(
              key: const ValueKey('acao'),
              onPressed: onAction,
              icon: Icon(actionIcon),
              label: Text(actionText),
            ),
    );
  }
}

/// Barra de "quanto do total" com o numero escrito ao lado (nao so o tamanho da barra).
class PartBar extends StatelessWidget {
  final double fraction;
  final String description;

  const PartBar(this.fraction, {super.key, required this.description});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(t.smallRadius / 2),
        child: LinearProgressIndicator(value: v, minHeight: t.progressBar, semanticsLabel: description),
      ),
    );
  }
}

/// Dois blocos lado a lado com a mesma altura; com fonte grande, um embaixo do outro.
class SideBySide extends StatelessWidget {
  final Widget left;
  final Widget right;
  final Widget? middle;

  const SideBySide(this.left, this.right, {super.key, this.middle});

  @override
  Widget build(BuildContext context) {
    if (largeFont(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, if (middle != null) Center(child: RotatedBox(quarterTurns: 1, child: middle)), right],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          middle == null ? const SizedBox(width: Spacing.p) : Center(child: middle),
          Expanded(child: right),
        ],
      ),
    );
  }
}
