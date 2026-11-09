import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_gerenciamento_energetico/api.dart';
import 'package:app_gerenciamento_energetico/casa.dart';
import 'package:app_gerenciamento_energetico/main.dart';
import 'package:app_gerenciamento_energetico/tema.dart';
import 'package:app_gerenciamento_energetico/telas/busca.dart';
import 'package:app_gerenciamento_energetico/telas/comum.dart';
import 'package:app_gerenciamento_energetico/telas/dicas.dart';
import 'package:app_gerenciamento_energetico/telas/estimar.dart';
import 'package:app_gerenciamento_energetico/telas/texto_plano.dart';

Resultado resultado(String categoria, double kwh, double custo, {double tarifa = 0.8}) => Resultado.fromJson({
  'categoria': categoria,
  'marca': 'MARCA',
  'modelo': categoria.toUpperCase(),
  'detalhe': '',
  'distribuidora': 'COPEL-DIS',
  'uf': 'PR',
  'kwh_mes': kwh,
  'metodo': 'teste',
  'tarifa_kwh': tarifa,
  'origem_tarifa': 'teste',
  'custo_mes': custo,
  'custo_ano': custo * 12,
  'avisos': <String>[],
});

Consulta consulta(String categoria, {int id = 1}) =>
    Consulta(Aparelho(id: id, categoria: categoria, marca: 'MARCA', modelo: categoria.toUpperCase()));

void main() {
  setUp(casa.limpar);

  testWidgets('abre na tela de busca com o tema preto e amarelo', (tester) async {
    await tester.pumpWidget(const IampApp());
    expect(find.text('Marca e/ou modelo'), findsOneWidget);
    expect(find.text('iamp'), findsOneWidget);
    final tema = Theme.of(tester.element(find.text('Marca e/ou modelo')));
    expect(tema.scaffoldBackgroundColor, Cores.preto);
    expect(tema.colorScheme.primary, Cores.amarelo);
  });

  testWidgets('minha casa vazia explica como adicionar', (tester) async {
    await tester.pumpWidget(const IampApp());
    await tester.tap(find.byTooltip('Minha casa'));
    await tester.pumpAndSettle();
    expect(find.text('Sua casa ainda está vazia'), findsOneWidget);
  });

  test('formata e le valores', () {
    expect(reais(31.68), 'R\$ 31,68');
    expect(reais(1234.5), 'R\$ 1.234,50');
    expect(reais(-2.5), '-R\$ 2,50');
    expect(numero(41.25), '41,25');
    expect(lerNumero('0,25'), 0.25);
    expect(lerNumero('0.25'), 0.25);
    expect(lerNumero('1.299,90'), 1299.90);
    expect(lerNumero('R\$ 2.499,90'), 2499.90);
    expect(lerNumero('abc'), isNull);
  });

  test('casa soma os aparelhos com a quantidade e ordena pelo custo', () {
    casa.adicionar(consulta('televisor'), resultado('televisor', 10, 8));
    final lampada = casa.adicionar(consulta('lampada_led', id: 2), resultado('lampada_led', 1.5, 1.2));
    casa.adicionar(consulta('chuveiro', id: 3), resultado('chuveiro', 41.25, 31.68));

    casa.mudarQuantidade(lampada, 10);

    expect(casa.totalAparelhos, 12);
    expect(casa.kwhMes, closeTo(10 + 15 + 41.25, 1e-9));
    expect(casa.custoMes, closeTo(8 + 12 + 31.68, 1e-9));
    expect(casa.porCusto.map((i) => i.resultado.categoria), ['chuveiro', 'lampada_led', 'televisor']);
    // o perfil usa o consumo total de cada item (kWh x quantidade)
    expect(casa.itensParaPerfil()[1], {'categoria': 'lampada_led', 'kwh_mes': 15.0});
  });

  test('trocar mantem a quantidade e qualquer mudanca apaga o perfil', () {
    final item = casa.adicionar(consulta('refrigerador'), resultado('refrigerador', 40, 32));
    casa.mudarQuantidade(item, 2);
    casa.guardarPerfil(
      Classificacao.fromJson({
        'perfil': 'Moderado',
        'kwh_total': 80,
        'kwh_por_morador': 40,
        'comparacao_media': {'mediana_kwh_por_morador': 50, 'diferenca_percentual': -20, 'texto': '20% abaixo'},
        'fracoes': {'frac_refrigerador': 1.0},
        'aviso': 'sintetico',
      }),
    );
    expect(casa.perfil, isNotNull);

    casa.trocar(item, consulta('refrigerador', id: 9), resultado('refrigerador', 25, 20));

    expect(casa.perfil, isNull);
    expect(casa.itens.single.quantidade, 2);
    expect(casa.itens.single.consulta.aparelho.id, 9);
    expect(casa.custoMes, 40);
  });

  test('pergunta de uso entende horas opcionais (TV e ar-condicionado)', () {
    final tv = PerguntaDeUso.fromJson({'pergunta': 'horas', 'opcoes': null, 'padrao': null, 'opcional': true});
    expect(tv.pergunta, 'horas');
    expect(tv.opcional, isTrue);
    // respostas antigas da API, sem o campo, continuam funcionando
    expect(PerguntaDeUso.fromJson({'pergunta': 'horas', 'padrao': null}).opcional, isFalse);
  });

  test('consulta manda o uso e a tarifa para a API', () {
    final c = consulta('chuveiro')
      ..horasDia = 0.25
      ..tarifa = EscolhaTarifa.manual(0.9);
    expect(c.paraApi(), {
      'distribuidora_id': null,
      'tarifa_manual': 0.9,
      'horas_dia': 0.25,
      'ciclos_mes': null,
      'velocidade': null,
    });
    // a copia com outro aparelho mantem o uso e a tarifa
    final troca = c.copiar(
      aparelho: const Aparelho(id: 5, categoria: 'chuveiro', marca: 'X', modelo: 'Y'),
    );
    expect(troca.paraApi(), c.paraApi());
    expect(troca.aparelho.id, 5);
  });

  test('resultado aproximado traz a faixa e resultados antigos continuam funcionando', () {
    final base = resultado('refrigerador', 45.75, 35.14);
    expect(base.aproximado, isFalse);
    expect(base.temFaixa, isFalse);
    final r = Resultado.fromJson({
      ...{
        'categoria': 'refrigerador',
        'marca': 'Consul',
        'modelo': 'CRM45',
        'distribuidora': 'COPEL-DIS',
        'uf': 'PR',
        'kwh_mes': 45.75,
        'metodo': 'etiqueta',
        'tarifa_kwh': 0.768,
        'origem_tarifa': 'ANEEL',
        'custo_mes': 35.14,
        'custo_ano': 421.66,
        'avisos': <String>[],
      },
      'aproximado': true,
      'kwh_min': 41.55,
      'kwh_max': 51.92,
      'custo_min_mes': 31.91,
      'custo_max_mes': 39.87,
    });
    expect(r.aproximado, isTrue);
    expect(r.temFaixa, isTrue);
    expect(r.custoMinMes, 31.91);
  });

  test('consulta estimada manda os dados do aparelho e a tarifa para a rota da estimativa', () {
    final c = Consulta(
      const Aparelho(id: 0, categoria: 'refrigerador', marca: 'Consul', modelo: 'CRM45'),
      estimativa: const Estimativa(rotaGeladeira, {'tipo': 'duplex', 'volume_total_l': 407.0, 'ano_compra': 2014}),
    )..tarifa = EscolhaTarifa.manual(0.768);
    expect(c.estimado, isTrue);
    expect(c.portatil, isFalse);
    expect(c.corpoDaEstimativa(), {
      'distribuidora_id': null,
      'tarifa_manual': 0.768,
      'horas_dia': null,
      'ciclos_mes': null,
      'velocidade': null,
      'tipo': 'duplex',
      'volume_total_l': 407.0,
      'ano_compra': 2014,
    });
    expect(c.copiar().estimado, isTrue);
    expect(c.copiar(aparelho: const Aparelho(id: 3, categoria: 'refrigerador', marca: 'X', modelo: 'Y')).estimado,
        isFalse);
  });

  test('total anual da casa usa o valor anual da API (sem diferenca de arredondamento)', () {
    casa.adicionar(
      consulta('refrigerador'),
      Resultado.fromJson({
        'categoria': 'refrigerador',
        'marca': 'Consul',
        'modelo': 'CRM50',
        'distribuidora': 'COPEL-DIS',
        'uf': 'PR',
        'kwh_mes': 32.1,
        'metodo': 'inmetro',
        'tarifa_kwh': 0.76802,
        'origem_tarifa': 'ANEEL',
        'custo_mes': 24.65,
        'custo_ano': 295.84,
        'avisos': <String>[],
      }),
    );
    expect(casa.custoAno, 295.84);
  });

  Future<List<Resistivo>> resistivosDeTeste() async => [
    Resistivo.fromJson({'categoria': 'air_fryer', 'nome': 'Air fryer', 'potencia_w': 1500, 'horas_dia': 0.5, 'dias_mes': 15}),
  ];

  Map<String, dynamic> categoria(String c, String nome, {String? medida, List<String> tipos = const [],
      bool especial = false, String? etiqueta, bool obrigatoria = false, Map<String, dynamic>? uso}) => {
    'categoria': c,
    'nome': nome,
    'especial': especial,
    'medida': medida,
    'tipos': tipos,
    'etiqueta_rotulo': etiqueta,
    'etiqueta_obrigatoria': obrigatoria,
    'uso': uso ?? {'pergunta': null},
  };

  Future<List<CategoriaEstimavel>> categoriasDeTeste() async => [
    for (final j in [
      categoria('refrigerador', 'Geladeira ou freezer', especial: true),
      categoria('maquina_de_lavar', 'Máquina de lavar', medida: 'Capacidade de lavagem (kg)',
          tipos: ['Top Load (automatica)'], etiqueta: 'Consumo da etiqueta (kWh por ciclo)',
          uso: {'pergunta': 'ciclos', 'padrao': 12}),
      categoria('chuveiro', 'Chuveiro elétrico', etiqueta: 'Potência (W)', obrigatoria: true,
          uso: {'pergunta': 'horas', 'padrao': null}),
    ])
      CategoriaEstimavel.fromJson(j),
  ];

  Widget telaEstimar() =>
      MaterialApp(home: TelaEstimar(carregarCategorias: categoriasDeTeste, carregarResistivos: resistivosDeTeste));

  Future<void> escolherAparelho(WidgetTester tester, String nome) async {
    await tester.tap(find.byType(DropdownButtonFormField<CategoriaEstimavel>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(nome).last);
    await tester.pumpAndSettle();
  }

  test('tempo em horas e minutos', () {
    final t = ControleTempo();
    expect(t.vazio, isTrue);
    expect(t.horasDia, isNull);
    t.definir(0.5);
    expect(t.horas.text, '0');
    expect(t.minutos.text, '30');
    expect(t.horasDia, 0.5);
    t.minutos.text = '75';
    expect(t.valido, isFalse);
    t.horas.text = '1';
    t.minutos.text = '15';
    expect(t.horasDia, 1.25);
    expect(duracao(0.25), '15 min');
    expect(duracao(4.5), '4 h 30 min');
    expect(duracao(2), '2 h');
  });

  void telaAlta(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('estimar a geladeira pede a capacidade e o ano antes de continuar', (tester) async {
    telaAlta(tester);
    await tester.pumpWidget(telaEstimar());
    await tester.pumpAndSettle();
    expect(find.text('Eletro pesado'), findsOneWidget);
    expect(find.text('Eletroportáteis'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(find.textContaining('capacidade total em litros'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Capacidade total (litros)'), '407');
    await tester.enterText(find.widgetWithText(TextField, 'Ano de compra'), '1900');
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(find.textContaining('ano de compra entre 1980'), findsOneWidget);
  });

  testWidgets('eletroportateis mostram a potencia tipica e o tempo em horas e minutos', (tester) async {
    telaAlta(tester);
    await tester.pumpWidget(telaEstimar());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eletroportáteis'));
    await tester.pumpAndSettle();
    expect(find.text('Air fryer'), findsOneWidget);
    expect(find.text('Típica: 1500 W'), findsOneWidget);
    expect(find.text('Sugerido: 30 min. Troque pelo seu uso real.'), findsOneWidget);
    expect(find.text('Minutos'), findsOneWidget);
  });

  testWidgets('maquina de lavar pede o tipo e a capacidade, ou o valor da etiqueta', (tester) async {
    telaAlta(tester);
    await tester.pumpWidget(telaEstimar());
    await tester.pumpAndSettle();
    await escolherAparelho(tester, 'Máquina de lavar');
    expect(find.text('Capacidade de lavagem (kg)'), findsOneWidget);
    expect(find.text('Lavagens por mês'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(find.textContaining('ou o valor da etiqueta'), findsWidgets);
  });

  testWidgets('chuveiro exige a potencia', (tester) async {
    telaAlta(tester);
    await tester.pumpWidget(telaEstimar());
    await tester.pumpAndSettle();
    await escolherAparelho(tester, 'Chuveiro elétrico');
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(find.text('Preencha o campo "Potência (W)".'), findsOneWidget);
  });

  testWidgets('chamada da busca abre a tela de estimativa sem preencher a marca', (tester) async {
    telaAlta(tester);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ChamadaEstimar())));
    await tester.tap(find.text('Não achou? Estime o gasto'));
    await tester.pumpAndSettle();
    expect(find.text('Estimar o gasto'), findsOneWidget);
  });

  testWidgets('dicas do eco-coach mostram o texto formatado e as fontes', (tester) async {
    telaAlta(tester);
    final r = resultado('air_fryer', 37.5, 28.8);
    Future<Dicas> falso(Resultado _) async => Dicas.fromJson({
      'dicas': 'A air fryer custa R\$ 28,80 por mês.\n\n## Como gastar menos\n'
          '- **Não abra** a cesta toda hora [1].\n2. Use o tempo certo [2].',
      'fontes': [
        {'n': 1, 'documento': 'Cartilha', 'orgao': 'Cemig', 'url': 'https://cemig.com.br'},
        {'n': 2, 'documento': 'Dicas', 'orgao': 'Inmetro', 'url': 'https://gov.br'},
      ],
      'aviso': 'Dicas geradas por IA.',
    });
    await tester.pumpWidget(MaterialApp(home: TelaDicas(resultado: r, buscarDicas: falso)));
    await tester.pumpAndSettle();
    expect(find.text('COMO GASTAR MENOS'), findsOneWidget);
    expect(find.textContaining('a cesta toda hora [1].', findRichText: true), findsOneWidget);
    expect(find.textContaining('Use o tempo certo [2].', findRichText: true), findsOneWidget);
    expect(find.textContaining('[1] Cemig - Cartilha'), findsOneWidget);
    expect(find.text('Dicas geradas por IA.'), findsOneWidget);
  });

  testWidgets('dicas mostram o erro quando o eco-coach esta fora do ar', (tester) async {
    Future<Dicas> fora(Resultado _) async => throw ApiErro('Eco-Coach indisponivel: GEMINI_API_KEY nao configurada');
    await tester.pumpWidget(MaterialApp(home: TelaDicas(resultado: resultado('air_fryer', 1, 1), buscarDicas: fora)));
    await tester.pumpAndSettle();
    expect(find.textContaining('GEMINI_API_KEY'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  group('Eco-Coach', () {
    test('plano: citacoes [n] em amarelo e **negrito** sem os asteriscos', () {
      const base = TextStyle(fontSize: 16);
      final pedacos = pedacosDoTexto('Desligue o **ar** nas saidas [1] e use o timer [2, 3].', base);
      expect(pedacos.map((p) => p.text).join(), 'Desligue o ar nas saidas [1] e use o timer [2, 3].');
      final citacoes = pedacos.where((p) => p.text!.startsWith('['));
      expect(citacoes.map((p) => p.text), ['[1]', '[2, 3]']);
      expect(citacoes.every((p) => p.style!.color == Cores.amarelo), isTrue);
      expect(pedacos.firstWhere((p) => p.text == 'ar').style!.fontWeight, FontWeight.bold);
    });

    testWidgets('plano: titulos, listas e paragrafos viram widgets', (tester) async {
      const md = '## Ações recomendadas\n\n1. Banho mais curto [1]\n- Geladeira longe do fogão [2]\nTexto final.';
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TextoPlano(md))));
      expect(find.text('AÇÕES RECOMENDADAS'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.byIcon(Icons.bolt), findsOneWidget); // marcador da lista
      expect(find.textContaining('Texto final.', findRichText: true), findsOneWidget);
    });

    test('casa manda o custo de cada item e guarda as trocas sem repetir', () {
      final item = casa.adicionar(consulta('chuveiro'), resultado('chuveiro', 41.25, 31.68));
      casa.mudarQuantidade(item, 2);
      expect(casa.itensParaEcoCoach().single, {'categoria': 'chuveiro', 'kwh_mes': 82.5, 'custo_mes': 63.36});

      const t1 = TrocaAvaliada(aparelho: 'geladeira A', alternativa: 'B', economiaMes: 7, paybackMeses: 300);
      casa.registrarTroca(t1);
      casa.registrarTroca(t1); // a mesma troca de novo nao duplica
      expect(casa.trocas, hasLength(1));
      for (var i = 0; i < 6; i++) {
        casa.registrarTroca(TrocaAvaliada(aparelho: 'tv $i', alternativa: 'x', economiaMes: 1));
      }
      expect(casa.trocas, hasLength(5)); // so as 5 mais recentes
    });

    test('plano guardado some quando a casa muda', () {
      casa.adicionar(consulta('televisor'), resultado('televisor', 10, 8));
      casa.guardarPlano(EcoCoach.fromJson(planoExemplo));
      expect(casa.plano!.fontes.single.pagina, 7);
      casa.mudarMoradores(4);
      expect(casa.plano, isNull);
    });
  });

  group('Busca por marca com varios tipos', () {
    Aparelho ap(int id, String categoria, int total) => Aparelho.fromJson({
      'id': id,
      'categoria': categoria,
      'marca': 'BRASTEMP',
      'modelo': 'M$id',
      'detalhe': '',
      'total_categoria': total,
    });

    Future<void> mostrar(WidgetTester tester, List<Aparelho> lista) => tester.pumpWidget(
      MaterialApp(
        theme: temaIamp(),
        home: Scaffold(body: ResultadosPorTipo(lista, aoEscolher: (_) {})),
      ),
    );

    testWidgets('cada tipo vira uma secao fechada que abre ao tocar', (tester) async {
      await mostrar(tester, [ap(1, 'maquina_de_lavar', 45), ap(2, 'maquina_de_lavar', 45), ap(3, 'refrigerador', 1)]);
      expect(find.text('Máquinas de lavar'), findsOneWidget);
      expect(find.text('45 modelos'), findsOneWidget);
      expect(find.text('Geladeiras'), findsOneWidget);
      expect(find.text('BRASTEMP M3'), findsNothing); // fechada
      await tester.tap(find.text('Geladeiras'));
      await tester.pumpAndSettle();
      expect(find.text('BRASTEMP M3'), findsOneWidget);
      await tester.tap(find.text('Máquinas de lavar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mostrando 2 de 45'), findsOneWidget);
    });

    testWidgets('um tipo so ja vem aberto', (tester) async {
      await mostrar(tester, [ap(1, 'refrigerador', 1)]);
      expect(find.text('BRASTEMP M1'), findsOneWidget);
    });

    testWidgets('trocar o tipo de aparelho refaz a busca', (tester) async {
      final pedidos = <Uri>[];
      // API falsa: /categorias e /aparelhos (filtra pela categoria pedida)
      final api = MockClient((r) async {
        pedidos.add(r.url);
        if (r.url.path == '/categorias') return http.Response(jsonEncode(['maquina_de_lavar', 'refrigerador']), 200);
        final tipo = r.url.queryParameters['categoria'];
        final todos = [
          {'id': 1, 'categoria': 'maquina_de_lavar', 'marca': 'BRASTEMP', 'modelo': 'LAVA', 'total_categoria': 1},
          {'id': 2, 'categoria': 'refrigerador', 'marca': 'BRASTEMP', 'modelo': 'GELA', 'total_categoria': 1},
        ];
        final lista = [
          for (final a in todos)
            if (tipo == null || a['categoria'] == tipo) a,
        ];
        return http.Response(jsonEncode(lista), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(theme: temaIamp(), home: const TelaBusca()));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'brastemp');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(find.text('Máquinas de lavar'), findsOneWidget);
        expect(find.text('Geladeiras'), findsOneWidget);

        await tester.tap(find.text('Todos'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('refrigerador').last);
        await tester.pumpAndSettle();
      }, () => api);
      expect(pedidos.last.queryParameters['categoria'], 'refrigerador'); // buscou sem apertar o botao
      expect(find.text('BRASTEMP GELA'), findsOneWidget); // um tipo so: secao ja aberta
      expect(find.text('Máquinas de lavar'), findsNothing);
    });
  });

  testWidgets('aviso de aparelho adicionado some sozinho depois de 5 s', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: temaIamp(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => avisarAdicionado(ScaffoldMessenger.of(context), Navigator.of(context), 'Foi.'),
              child: const Text('adicionar'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('adicionar'));
    await tester.pumpAndSettle();
    expect(find.text('Foi.'), findsOneWidget);
    expect(find.text('Ver'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Foi.'), findsNothing);
  });
}

const planoExemplo = {
  'perfil': 'Moderado',
  'kwh_total': 10.0,
  'custo_total': 8.0,
  'maiores_consumos': [
    {'categoria': 'televisor', 'nome': 'televisão', 'kwh_mes': 10.0, 'custo_mes': 8.0, 'percentual': 100.0},
  ],
  'plano': 'Desligue a TV da tomada [1].',
  'fontes': [
    {'n': 1, 'documento': 'Cartilha', 'orgao': 'Cemig', 'url': 'https://x', 'secao': 'Sala', 'pagina': 7},
  ],
  'modelo': 'gemini-3.5-flash',
  'aviso': 'Plano gerado por IA.',
};
