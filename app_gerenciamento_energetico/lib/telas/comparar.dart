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
    final novo = _comparar(preco: preco);
    try {
      await novo;
      setState(() => _comparacao = novo);
    } on ApiErro catch (e) {
      setState(() => _erroPreco = e.mensagem);
    } finally {
      setState(() => _calculandoPayback = false);
    }
  }

  void _levarParaCasa(Comparacao c) {
    final nova = widget.consulta.copiar(aparelho: widget.sugerido.aparelho);
    if (widget.item != null) {
      casa.trocar(widget.item!, nova, c.novo);
      Navigator.popUntil(context, ModalRoute.withName(rotaMinhaCasa));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Trocado por ${c.novo.nome}.')));
      return;
    }
    casa.adicionar(nova, c.novo);
    setState(() => _feito = true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${c.novo.nome} foi para a sua casa.'),
      action: SnackBarAction(label: 'Ver', onPressed: () => abrirMinhaCasa(context)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Vale a pena trocar?',
      filho: FutureBuilder<Comparacao>(
        future: _comparacao,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError && !snap.hasData) {
            return MensagemErro(snap.error.toString(), tentarDeNovo: () => setState(() => _comparacao = _comparar()));
          }
          final c = snap.data!;
          return ListView(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _Coluna('Seu modelo', c.atual, destaque: false)),
                  const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: Icon(Icons.arrow_forward, color: Cores.amarelo),
                  ),
                  Expanded(child: _Coluna('Modelo novo', c.novo, destaque: true)),
                ],
              ),
              const SizedBox(height: 8),
              CartaoDestaque(
                titulo: 'Economia por mês',
                valor: reais(c.economiaMes),
                rodape: '${reais(c.economiaAno)} por ano - ${numero(c.economiaKwhMes)} kWh/mês a menos',
              ),
              const Titulo('Em quanto tempo a troca se paga?'),
              const Text('O catálogo do Inmetro não tem preços. Digite o preço que você encontrou na loja.',
                  style: TextStyle(color: Cores.cinza)),
              const SizedBox(height: 8),
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
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _calculandoPayback ? null : _calcularPayback,
                child: _calculandoPayback
                    ? const SizedBox(
                        height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Cores.preto))
                    : const Text('Calcular payback'),
              ),
              if (c.payback != null) ...[
                const SizedBox(height: 12),
                _CartaoPayback(c.payback!),
              ],
              const SizedBox(height: 16),
              if (!_feito)
                OutlinedButton.icon(
                  onPressed: () => _levarParaCasa(c),
                  icon: Icon(widget.item != null ? Icons.swap_horiz : Icons.add_home_outlined, color: Cores.amarelo),
                  label: Text(widget.item != null ? 'Trocar na minha casa' : 'Adicionar este modelo à minha casa'),
                ),
              const SizedBox(height: 16),
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
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: destaque ? Cores.amarelo : Cores.borda),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: TextStyle(color: destaque ? Cores.amarelo : Cores.cinza, fontSize: 12)),
            const SizedBox(height: 4),
            Text(r.nome, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 3, overflow: TextOverflow.ellipsis),
            if (r.detalhe.isNotEmpty) Text(r.detalhe, style: const TextStyle(color: Cores.cinza, fontSize: 12)),
            const SizedBox(height: 8),
            Text('${numero(r.kwhMes)} kWh/mês'),
            Text(reais(r.custoMes), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Text('por mês', style: TextStyle(color: Cores.cinza, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _CartaoPayback extends StatelessWidget {
  final Payback p;

  const _CartaoPayback(this.p);

  @override
  Widget build(BuildContext context) {
    final meses = p.meses;
    return Card(
      color: Cores.amareloEscuro,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: Cores.amarelo),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (meses != null) ...[
              Text(meses < 1 ? 'menos de 1 mês' : '${numero(meses, casas: 0)} meses',
                  style: const TextStyle(color: Cores.amarelo, fontSize: 32, fontWeight: FontWeight.w900)),
              if (p.anos != null && meses >= 12)
                Text('cerca de ${numero(p.anos!, casas: 1)} anos', style: const TextStyle(color: Cores.branco)),
              const SizedBox(height: 8),
            ],
            Text(p.texto, textAlign: TextAlign.center),
            Text('Preço considerado: ${reais(p.precoNovo)}', style: const TextStyle(color: Cores.cinza, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
