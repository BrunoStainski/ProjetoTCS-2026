import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../tema.dart';
import 'comum.dart';

/// Aparelho atual x modelo sugerido (POST /comparar). Com o preco digitado, mostra o payback.
/// O payback e calculado na API (Python); o app so mostra.
class TelaComparar extends StatefulWidget {
  final Consulta consulta;
  final AparelhoSugerido sugerido;
  final ItemCasa? item;

  const TelaComparar({super.key, required this.consulta, required this.sugerido, this.item});

  @override
  State<TelaComparar> createState() => _TelaCompararState();
}

class _TelaCompararState extends State<TelaComparar> {
  final _preco = TextEditingController();
  late Future<Comparacao> _comparacao;
  bool _calculandoPayback = false;
  String? _erroPreco;
  bool _feito = false; // ja trocou ou adicionou na casa

  @override
  void initState() {
    super.initState();
    _comparacao = _comparar();
  }

  @override
  void dispose() {
    _preco.dispose();
    super.dispose();
  }

  Future<Comparacao> _comparar({double? preco}) => Api.comparar(
    widget.consulta.aparelho.id,
    widget.sugerido.aparelho.id,
    widget.consulta.paraApi(),
    precoNovo: preco,
  );

  Future<void> _calcularPayback() async {
    final preco = lerNumero(_preco.text);
    if (preco == null || preco <= 0) {
      setState(() => _erroPreco = 'Informe o preço em reais (ex.: 2.499,90).');
      return;
    }
    setState(() {
      _erroPreco = null;
      _calculandoPayback = true;
    });
    try {
      // o setState nao pode receber um Future: espera a resposta e so depois troca o estado
      final comparacao = await _comparar(preco: preco);
      if (!mounted) return;
      setState(() {
        _comparacao = Future.value(comparacao);
      });
    } on ApiErro catch (e) {
      if (mounted) setState(() => _erroPreco = e.mensagem);
    } finally {
      if (mounted) setState(() => _calculandoPayback = false);
    }
  }

  void _levarParaCasa(Comparacao c) {
    final nova = widget.consulta.copiar(aparelho: widget.sugerido.aparelho);
    final navegador = Navigator.of(context);
    final avisos = ScaffoldMessenger.of(context);
    if (widget.item != null) {
      casa.trocar(widget.item!, nova, c.novo);
      navegador.popUntil(ModalRoute.withName(rotaMinhaCasa));
      avisos.showSnackBar(SnackBar(content: Text('Trocado por ${c.novo.nome}.')));
      return;
    }
    casa.adicionar(nova, c.novo);
    setState(() => _feito = true);
    avisos.showSnackBar(
      SnackBar(
        content: Text('${c.novo.nome} foi para a sua casa.'),
        // o aviso pode continuar na tela depois de sair daqui: usa o navegador, nao o context
        action: SnackBarAction(label: 'Ver', onPressed: () => abrirMinhaCasaNo(navegador)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Vale a pena trocar?',
      rodape: FilledButton.icon(
        onPressed: _calculandoPayback ? null : _calcularPayback,
        icon: _calculandoPayback
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Cores.preto),
              )
            : const Icon(Icons.timer_outlined),
        label: const Text('Calcular payback'),
      ),
      filho: FutureBuilder<Comparacao>(
        future: _comparacao,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError && !snap.hasData) {
            return MensagemErro(
              snap.error.toString(),
              tentarDeNovo: () => setState(() {
                _comparacao = _comparar();
              }),
            );
          }
          final c = snap.data!;
          return ListView(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _Coluna('Seu modelo', c.atual, destaque: false)),
                  const Padding(
                    padding: EdgeInsets.only(top: 56, left: 4, right: 4),
                    child: Icon(Icons.arrow_forward, color: Cores.amarelo),
                  ),
                  Expanded(child: _Coluna('Modelo novo', c.novo, destaque: true)),
                ],
              ),
              const SizedBox(height: Espaco.p),
              CartaoDestaque(
                titulo: 'Economia por mês',
                valor: c.economiaMes,
                formatar: reais,
                cor: c.economiaMes > 0 ? Cores.verde : Cores.vermelho,
                rodape: '${reais(c.economiaAno)} por ano · ${numero(c.economiaKwhMes)} kWh/mês a menos',
              ),
              const Titulo('Em quanto tempo a troca se paga?'),
              const Text(
                'O catálogo do Inmetro não tem preços. Digite o preço que você encontrou na loja.',
                style: Estilos.secundario,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _preco,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onSubmitted: (_) => _calcularPayback(),
                decoration: InputDecoration(
                  labelText: 'Preço do modelo novo (R\$)',
                  hintText: 'Ex.: 2.499,90',
                  errorText: _erroPreco,
                ),
              ),
              // momento de pico: o payback aparece com animacao e os meses "contam" ate o valor
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (filho, animacao) => SizeTransition(
                  sizeFactor: animacao,
                  child: FadeTransition(opacity: animacao, child: filho),
                ),
                child: c.payback == null
                    ? const SizedBox.shrink()
                    : Padding(
                        key: ValueKey(c.payback!.precoNovo),
                        padding: const EdgeInsets.only(top: Espaco.m),
                        child: _CartaoPayback(c.payback!),
                      ),
              ),
              const SizedBox(height: Espaco.g),
              if (!_feito)
                OutlinedButton.icon(
                  onPressed: () => _levarParaCasa(c),
                  icon: Icon(widget.item != null ? Icons.swap_horiz : Icons.add_home_outlined, color: Cores.amarelo),
                  label: Text(widget.item != null ? 'Trocar na minha casa' : 'Adicionar este modelo à minha casa'),
                ),
              const SizedBox(height: Espaco.m),
              ListaAvisos(c.avisos),
            ],
          );
        },
      ),
    );
  }
}

class _Coluna extends StatelessWidget {
  final String titulo;
  final Resultado r;
  final bool destaque;

  const _Coluna(this.titulo, this.r, {required this.destaque});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: destaque ? Cores.verde : Cores.borda),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: Estilos.rotulo.copyWith(color: destaque ? Cores.verde : Cores.cinza)),
            const SizedBox(height: 4),
            Text(r.nome, style: Estilos.forte, maxLines: 3, overflow: TextOverflow.ellipsis),
            if (r.detalhe.isNotEmpty) Text(r.detalhe, style: Estilos.secundario),
            const SizedBox(height: Espaco.p),
            Text(reais(r.custoMes), style: Estilos.valorMedio.copyWith(color: Cores.branco)),
            Text('por mês · ${numero(r.kwhMes)} kWh', style: Estilos.secundario),
          ],
        ),
      ),
    );
  }
}

/// Payback: verde quando se paga em ate 5 anos, amarelo quando demora mais, vermelho quando nao se paga.
/// (5 anos e um corte do grupo para a cor, nao uma regra oficial.)
class _CartaoPayback extends StatelessWidget {
  final Payback p;

  const _CartaoPayback(this.p);

  @override
  Widget build(BuildContext context) {
    final meses = p.meses;
    final cor = meses == null
        ? Cores.vermelho
        : meses <= 60
        ? Cores.verde
        : Cores.amarelo;
    return Container(
      padding: const EdgeInsets.all(Espaco.g),
      decoration: BoxDecoration(
        color: Cores.superficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.7), width: 1.5),
        boxShadow: [BoxShadow(color: cor.withValues(alpha: 0.18), blurRadius: 32, spreadRadius: -4)],
      ),
      child: Column(
        children: [
          Icon(meses == null ? Icons.money_off : Icons.savings_outlined, color: cor, size: 32),
          const SizedBox(height: Espaco.p),
          if (meses != null) ...[
            if (meses < 1)
              Text('menos de 1 mês', style: Estilos.valor.copyWith(color: cor))
            else
              ValorAnimado(
                meses,
                formatar: (v) => '${numero(v, casas: 0)} meses',
                estilo: Estilos.valor.copyWith(color: cor),
              ),
            if (p.anos != null && meses >= 12) Text('cerca de ${numero(p.anos!, casas: 1)} anos', style: Estilos.forte),
            const SizedBox(height: Espaco.p),
          ],
          Text(p.texto, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text('Preço considerado: ${reais(p.precoNovo)}', style: Estilos.secundario),
        ],
      ),
    );
  }
}
