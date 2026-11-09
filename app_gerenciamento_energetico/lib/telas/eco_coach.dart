import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../tema.dart';
import 'comum.dart';
import 'texto_plano.dart';

/// Eco-Coach (POST /eco-coach): plano de economia escrito por IA a partir de dicas oficiais
/// (Inmetro e Cemig). Os numeros sao calculados pelo iamp; o LLM so escreve e cita as fontes [n].
class TelaEcoCoach extends StatefulWidget {
  const TelaEcoCoach({super.key});

  @override
  State<TelaEcoCoach> createState() => _TelaEcoCoachState();
}

class _TelaEcoCoachState extends State<TelaEcoCoach> {
  late Future<EcoCoach> _plano;

  @override
  void initState() {
    super.initState();
    // usa o plano guardado se a casa nao mudou (o plano gratuito do Gemini tem limite de uso)
    _plano = casa.plano != null ? Future.value(casa.plano!) : _gerar();
  }

  Future<EcoCoach> _gerar() async {
    final plano = await Api.ecoCoach(casa.moradores, casa.itensParaEcoCoach(), casa.trocas);
    casa.guardarPlano(plano);
    return plano;
  }

  void _gerarDeNovo() {
    setState(() {
      _plano = _gerar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EcoCoach>(
      future: _plano,
      builder: (context, snap) {
        final carregando = snap.connectionState != ConnectionState.done;
        return Pagina(
          titulo: 'Eco-Coach',
          rodape: carregando
              ? null
              : OutlinedButton.icon(
                  onPressed: _gerarDeNovo,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Gerar outro plano'),
                ),
          filho: carregando
              ? const _Pensando()
              : snap.hasError
              ? MensagemErro(snap.error.toString(), tentarDeNovo: _gerarDeNovo)
              : _Conteudo(snap.data!),
        );
      },
    );
  }
}

/// Espera do LLM: raio pulsando e o que esta acontecendo (pode levar alguns segundos).
class _Pensando extends StatefulWidget {
  const _Pensando();

  @override
  State<_Pensando> createState() => _PensandoState();
}

class _PensandoState extends State<_Pensando> with SingleTickerProviderStateMixin {
  late final AnimationController _pulso = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: Tween(begin: 0.85, end: 1.15).animate(CurvedAnimation(parent: _pulso, curve: Curves.easeInOut)),
            child: Container(
              padding: const EdgeInsets.all(Espaco.g),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Cores.superficie,
                border: Border.all(color: Cores.borda, width: 1.5),
                boxShadow: [BoxShadow(color: Cores.amarelo.withValues(alpha: 0.25), blurRadius: 40)],
              ),
              child: const Icon(Icons.bolt, size: 48, color: Cores.amarelo),
            ),
          ),
          const SizedBox(height: Espaco.g),
          const Text('Montando seu plano', style: Estilos.titulo),
          const SizedBox(height: Espaco.p),
          const Text(
            'O Eco-Coach está lendo as dicas oficiais do Inmetro e da Cemig para os aparelhos que mais pesam na '
            'sua conta. Pode levar alguns segundos.',
            textAlign: TextAlign.center,
            style: Estilos.corpo,
          ),
        ],
      ),
    );
  }
}

class _Conteudo extends StatelessWidget {
  final EcoCoach p;

  const _Conteudo(this.p);

  static const _cores = {'Consciente': Cores.verde, 'Moderado': Cores.amarelo, 'Ineficiente': Cores.vermelho};

  @override
  Widget build(BuildContext context) {
    final cor = _cores[p.perfil] ?? Cores.amarelo;
    return ListView(
      children: [
        // resumo calculado pelo iamp (nao pela IA)
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: cor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cor.withValues(alpha: 0.6)),
              ),
              child: Text('Perfil ${p.perfil}', style: Estilos.rotulo.copyWith(color: cor)),
            ),
            const Spacer(),
            Text(
              p.custoTotal != null ? '${reais(p.custoTotal!)}/mês' : '${numero(p.kwhTotal)} kWh/mês',
              style: Estilos.numero.copyWith(color: Cores.branco),
            ),
          ],
        ),
        const Titulo('O que mais pesa'),
        for (final m in p.maioresConsumos) _LinhaConsumo(m),
        const Titulo('Seu plano de economia'),
        Container(
          padding: const EdgeInsets.all(Espaco.m),
          decoration: BoxDecoration(
            color: Cores.superficie,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Cores.borda),
            boxShadow: [BoxShadow(color: Cores.amarelo.withValues(alpha: 0.10), blurRadius: 32, spreadRadius: -4)],
          ),
          child: TextoPlano(p.plano),
        ),
        if (p.fontes.isNotEmpty) ...[const Titulo('Fontes citadas'), for (final f in p.fontes) _CartaoFonte(f)],
        const SizedBox(height: Espaco.m),
        ListaAvisos([p.aviso, 'Texto escrito por IA (${p.modelo}). Ela pode errar: confira nas fontes.']),
      ],
    );
  }
}

class _LinhaConsumo extends StatelessWidget {
  final MaiorConsumo m;

  const _LinhaConsumo(this.m);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconeDaCategoria(m.categoria), size: 20),
              const SizedBox(width: Espaco.p),
              Expanded(child: Text(_maiuscula(m.nome), style: Estilos.forte)),
              Text('${numero(m.percentual, casas: 0)}%', style: Estilos.numero.copyWith(color: Cores.branco)),
            ],
          ),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: m.percentual / 100),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: v, minHeight: 8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ['${numero(m.kwhMes)} kWh/mês', if (m.custoMes != null) '${reais(m.custoMes!)}/mês'].join(' · '),
            style: Estilos.secundario,
          ),
        ],
      ),
    );
  }

  static String _maiuscula(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _CartaoFonte extends StatelessWidget {
  final FonteCitada f;

  const _CartaoFonte(this.f);

  @override
  Widget build(BuildContext context) {
    final onde = [
      if (f.secao != null && f.secao!.isNotEmpty) f.secao!,
      if (f.pagina != null) 'p. ${f.pagina}',
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Cores.amareloEscuro,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Cores.borda),
              ),
              child: Text('${f.n}', style: Estilos.forte.copyWith(color: Cores.amarelo)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${f.orgao} · ${f.documento}', style: Estilos.forte),
                  if (onde.isNotEmpty) Text(onde, style: Estilos.secundario),
                  const SizedBox(height: 4),
                  // sem pacote para abrir links: o endereco pode ser selecionado e copiado
                  SelectableText(f.url, style: Estilos.secundario.copyWith(color: Cores.amarelo)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
