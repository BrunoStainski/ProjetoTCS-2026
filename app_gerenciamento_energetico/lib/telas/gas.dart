import 'package:flutter/material.dart';

import '../api.dart';
import '../tema.dart';
import 'comum.dart';

class TelaGas extends StatefulWidget {
  final Future<List<PrecoGlp>> Function() carregarPrecos;
  final Future<List<Fogao>> Function(String) buscarFogoes;
  final Future<ResultadoGas> Function(Map<String, dynamic>) calcular;

  const TelaGas({
    super.key,
    this.carregarPrecos = Api.precosGlp,
    this.buscarFogoes = Api.fogoes,
    this.calcular = Api.calcularGas,
  });

  @override
  State<TelaGas> createState() => _TelaGasState();
}

class _TelaGasState extends State<TelaGas> {
  final _busca = TextEditingController();
  final _bocas = ControleTempo()..definir(1);
  final _forno = ControleTempo()..definir(0.25);
  final _dias = TextEditingController(text: '30');
  final _botijao = TextEditingController();
  List<PrecoGlp>? _precos;
  String? _uf;
  bool _usarBotijao = false;
  List<Fogao>? _encontrados;
  Fogao? _fogao;
  ResultadoGas? _resultado;
  bool _calculando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarPrecos();
  }

  @override
  void dispose() {
    _busca.dispose();
    _dias.dispose();
    _botijao.dispose();
    _bocas.dispose();
    _forno.dispose();
    super.dispose();
  }

  Future<void> _carregarPrecos() async {
    try {
      final precos = await widget.carregarPrecos();
      if (mounted) setState(() => _precos = precos);
    } catch (_) {
      if (mounted) setState(() => _erro = 'Não consegui carregar os preços do gás. A API está rodando?');
    }
  }

  Future<void> _buscar() async {
    final texto = _busca.text.trim();
    if (texto.length < 2) return setState(() => _erro = 'Digite pelo menos 2 letras da marca ou do modelo.');
    try {
      final lista = await widget.buscarFogoes(texto);
      if (mounted) {
        setState(() {
          _encontrados = lista;
          _erro = null;
        });
      }
    } on ApiErro catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    }
  }

  Future<void> _calcular() async {
    if (!_bocas.valido || !_forno.valido) {
      return setState(() => _erro = 'Confira o tempo de uso (minutos de 0 a 59, até 24 h por dia).');
    }
    final dias = lerNumero(_dias.text);
    if (dias == null || dias < 0 || dias > 31) return setState(() => _erro = 'Informe os dias de uso no mês (0 a 31).');
    final botijao = lerNumero(_botijao.text);
    if (_usarBotijao && (botijao == null || botijao <= 0)) {
      return setState(() => _erro = 'Informe o preço do botijão de 13 kg (ex.: 120,00).');
    }
    if (!_usarBotijao && _uf == null) return setState(() => _erro = 'Escolha o estado.');
    setState(() {
      _erro = null;
      _calculando = true;
    });
    try {
      final r = await widget.calcular({
        'fogao_id': _fogao?.id,
        'horas_bocas_dia': _bocas.horasDia ?? 0,
        'horas_forno_dia': _forno.horasDia ?? 0,
        'dias_mes': dias,
        'uf': _usarBotijao ? null : _uf,
        'preco_botijao': _usarBotijao ? botijao : null,
      });
      if (mounted) setState(() => _resultado = r);
    } on ApiErro catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _calculando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Gás de cozinha',
      rodape: FilledButton(onPressed: _calculando ? null : _calcular, child: const Text('Calcular o gás')),
      filho: ListView(
        children: [
          const Text(
            'Quanto o fogão gasta de gás (botijão de 13 kg) por mês, com dados do Inmetro e preços da ANP.',
            style: Estilos.secundario,
          ),
          const Titulo('Seu fogão (opcional)'),
          if (_fogao != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.outdoor_grill_outlined, color: Cores.amarelo),
                title: Text(_fogao!.nome),
                subtitle: Text(_fogao!.detalhe, style: Estilos.secundario),
                trailing: TextButton(onPressed: () => setState(() => _fogao = null), child: const Text('Trocar')),
              ),
            )
          else ...[
            TextField(
              controller: _busca,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _buscar(),
              decoration: InputDecoration(
                labelText: 'Marca e/ou modelo do fogão',
                helperText: 'Em branco, usamos os valores medianos dos fogões do Inmetro.',
                suffixIcon: IconButton(icon: const Icon(Icons.search, color: Cores.amarelo), onPressed: _buscar),
              ),
            ),
            if (_encontrados != null && _encontrados!.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: Espaco.p),
                child: Text('Nenhum fogão encontrado; pode calcular sem o modelo.', style: Estilos.secundario),
              ),
            for (final f in _encontrados ?? const <Fogao>[])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(f.nome),
                subtitle: Text(f.detalhe, style: Estilos.secundario),
                trailing: const Icon(Icons.chevron_right, color: Cores.amarelo),
                onTap: () => setState(() {
                  _fogao = f;
                  _encontrados = null;
                }),
              ),
          ],
          const Titulo('Como você usa'),
          CampoTempo(
            controle: _bocas,
            rotulo: 'Bocas acesas por dia (somando todas)',
            ajuda: 'Ex.: duas bocas por 30 min = 1 h. Sugerido: 1 h.',
          ),
          const SizedBox(height: Espaco.m),
          CampoTempo(controle: _forno, rotulo: 'Forno ligado por dia (média)', ajuda: 'Ex.: 1 h duas vezes por semana ≈ 17 min por dia.'),
          const SizedBox(height: Espaco.m),
          TextField(
            controller: _dias,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Dias de uso no mês'),
          ),
          const Titulo('Preço do gás'),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Média do estado'), icon: Icon(Icons.map_outlined)),
              ButtonSegment(value: true, label: Text('Meu botijão'), icon: Icon(Icons.propane_tank_outlined)),
            ],
            selected: {_usarBotijao},
            onSelectionChanged: (s) => setState(() => _usarBotijao = s.first),
          ),
          const SizedBox(height: Espaco.m),
          if (_usarBotijao)
            TextField(
              controller: _botijao,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Preço do botijão de 13 kg (R\$)', hintText: 'Ex.: 120,00'),
            )
          else if (_precos == null && _erro == null)
            const Center(child: CircularProgressIndicator())
          else if (_precos != null)
            DropdownButtonFormField<String>(
              initialValue: _uf,
              isExpanded: true,
              dropdownColor: Cores.superficieAlta,
              iconEnabledColor: Cores.amarelo,
              decoration: const InputDecoration(labelText: 'Estado', helperText: 'Preço médio do GLP (ANP).'),
              items: [
                for (final p in _precos!)
                  DropdownMenuItem(
                    value: p.uf,
                    child: Text('${p.uf} - botijão ${reais(p.precoBotijao)} (média ${p.ano})'),
                  ),
              ],
              onChanged: (uf) => setState(() => _uf = uf),
            ),
          const SizedBox(height: Espaco.m),
          if (_erro != null) MensagemErro(_erro!),
          if (_calculando) const Center(child: CircularProgressIndicator()),
          if (_resultado != null) _DetalhesGas(_resultado!),
        ],
      ),
    );
  }
}

class _DetalhesGas extends StatelessWidget {
  final ResultadoGas r;

  const _DetalhesGas(this.r);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CartaoDestaque(
          titulo: 'Gás por mês',
          valor: r.custoMes,
          formatar: reais,
          rodape: [
            if (r.diasPorBotijao != null) 'um botijão dura cerca de ${r.diasPorBotijao} dias',
            '${reais(r.custoAno)} por ano',
          ].join(' · '),
        ),
        const SizedBox(height: Espaco.p),
        Row(
          children: [
            Expanded(child: CartaoInfo('Consumo', '${numero(r.kgMes)} kg/mês')),
            const SizedBox(width: Espaco.p),
            Expanded(child: CartaoInfo('Botijão 13 kg', reais(r.precoBotijao))),
          ],
        ),
        const Titulo('Como calculamos'),
        Text(r.metodo),
        const Titulo('Fonte do preço'),
        Text(r.origemPreco),
        const SizedBox(height: Espaco.m),
        ListaAvisos(r.avisos),
      ],
    );
  }
}
