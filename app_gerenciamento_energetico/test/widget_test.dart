import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_gerenciamento_energetico/api.dart';
import 'package:app_gerenciamento_energetico/casa.dart';
import 'package:app_gerenciamento_energetico/main.dart';
import 'package:app_gerenciamento_energetico/navegacao.dart';
import 'package:app_gerenciamento_energetico/tema.dart';
import 'package:app_gerenciamento_energetico/telas/busca.dart';
import 'package:app_gerenciamento_energetico/telas/comparar.dart';
import 'package:app_gerenciamento_energetico/telas/comum.dart';
import 'package:app_gerenciamento_energetico/telas/dicas.dart';
import 'package:app_gerenciamento_energetico/telas/distribuidora.dart';
import 'package:app_gerenciamento_energetico/telas/estimar.dart';
import 'package:app_gerenciamento_energetico/telas/minha_casa.dart';
import 'package:app_gerenciamento_energetico/telas/resultado.dart';
import 'package:app_gerenciamento_energetico/telas/texto_plano.dart';
import 'package:app_gerenciamento_energetico/telas/uso.dart';

Map<String, dynamic> resultadoJson(String categoria, double kwh, double custo, {double tarifa = 0.8}) => {
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
};

Resultado resultado(String categoria, double kwh, double custo, {double tarifa = 0.8}) =>
    Resultado.fromJson(resultadoJson(categoria, kwh, custo, tarifa: tarifa));

Consulta consulta(String categoria, {int id = 1}) =>
    Consulta(Aparelho(id: id, categoria: categoria, marca: 'MARCA', modelo: categoria.toUpperCase()));

final _json = {'content-type': 'application/json; charset=utf-8'};

/// API falsa com o caminho completo do calculo de um aparelho do catalogo.
MockClient apiFalsa({List<Uri>? pedidos}) => MockClient((r) async {
  pedidos?.add(r.url);
  final corpo = switch (r.url.path) {
    '/categorias' => ['refrigerador', 'chuveiro', 'televisor'],
    '/aparelhos' => [
      for (final a in [
        {'id': 1, 'categoria': 'maquina_de_lavar', 'marca': 'BRASTEMP', 'modelo': 'LAVA', 'total_categoria': 1},
        {'id': 2, 'categoria': 'refrigerador', 'marca': 'BRASTEMP', 'modelo': 'GELA', 'total_categoria': 1},
      ])
        if (r.url.queryParameters['categoria'] == null || a['categoria'] == r.url.queryParameters['categoria']) a,
    ],
    '/marcas' => [
      {'marca': 'BRASTEMP', 'modelos': 1},
      {'marca': 'CONSUL', 'modelos': 60},
    ],
    '/modelos' => r.url.queryParameters['marca'] == 'CONSUL'
        ? [
            for (var i = 1; i <= 50; i++)
              {'id': 100 + i, 'categoria': 'refrigerador', 'marca': 'CONSUL', 'modelo': 'CRM$i', 'total_categoria': 60},
          ]
        : [
            {'id': 2, 'categoria': 'refrigerador', 'marca': 'BRASTEMP', 'modelo': 'GELA', 'total_categoria': 1},
          ],
    '/aparelhos/2/uso' => {'pergunta': null},
    '/aparelhos/3/uso' => {
      'pergunta': 'velocidade',
      'opcoes': ['baixa', 'media', 'alta'],
      'padrao': 'media',
      'perguntar_horas': true,
    },
    '/ufs' => ['PR', 'SP'],
    '/distribuidoras' => [
      {'id': 7, 'nome': 'COPEL-DIS', 'uf': 'PR', 'tarifa_kwh': 0.768},
    ],
    '/calcular' => resultadoJson('refrigerador', 41.25, 31.68, tarifa: 0.768),
    _ => null,
  };
  return corpo == null ? http.Response('{"detail": "nao existe"}', 404) : http.Response(jsonEncode(corpo), 200, headers: _json);
});

void main() {
  setUp(() {
    casa.limpar();
    abaAtual.value = Aba.calcular;
  });

  /// Celular de 360dp de largura. `alta`: tela comprida, para ver tudo sem rolar com fonte grande
  /// (o que quebra com fonte 2x e a largura: textos e botoes lado a lado).
  void telaDeCelular(WidgetTester tester, {double fonte = 1, bool alta = false}) {
    tester.view.physicalSize = Size(360 * 3, (alta ? 3000 : 780) * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = fonte;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  void telaAlta(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('Boas-vindas e menu', () {
    Finder noMenu(Finder f) => find.descendant(of: find.byType(Drawer), matching: f);
    // a logo e carregada ja no tamanho da tela (cacheWidth), por isso vem dentro de um ResizeImage
    final logo = find.byWidgetPredicate(
      (w) => w is Image && w.image is ResizeImage && (w.image as ResizeImage).imageProvider == const AssetImage(MarcaIamp.imagem),
    );

    Future<void> abrirMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
    }

    testWidgets('abre nas boas-vindas e "Comece a economizar" leva ao cálculo', (tester) async {
      telaDeCelular(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp());
        await tester.pumpAndSettle();
        expect(find.text('Comece a economizar'), findsOneWidget);
        expect(logo, findsOneWidget);
        expect(find.text('Qual aparelho você quer calcular?'), findsNothing);
        // so a marca e o botao: sem frases, e o icone ao lado do nome (nao em cima)
        expect(find.text('Sua conta de luz, sem surpresas'), findsNothing);
        expect(find.textContaining('Inmetro'), findsNothing);
        final icone = tester.getRect(logo);
        final nome = tester.getRect(find.text('Iamp'));
        expect(nome.left, greaterThan(icone.right));
        expect(nome.center.dy, closeTo(icone.center.dy, 2));
        expect(icone.width, greaterThanOrEqualTo(100)); // maior que a logo do menu (48)

        await tester.tap(find.text('Comece a economizar'));
        await tester.pumpAndSettle();
      }, apiFalsa);
      expect(find.text('Comece a economizar'), findsNothing);
      expect(find.text('Qual aparelho você quer calcular?'), findsOneWidget);
      expect(abaAtual.value, Aba.calcular);
    });

    testWidgets('boas-vindas cabe na tela com a fonte do sistema em 2x', (tester) async {
      telaDeCelular(tester, fonte: 2);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp());
        await tester.pumpAndSettle();
      }, apiFalsa);
      expect(tester.takeException(), isNull);
      expect(find.text('Comece a economizar'), findsOneWidget);
    });

    testWidgets('menu cabe na tela com a fonte do sistema em 2x (textos quebram a linha)', (tester) async {
      telaDeCelular(tester, fonte: 2);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(boasVindas: false));
        await tester.pumpAndSettle();
        await abrirMenu(tester);
      }, apiFalsa);
      expect(tester.takeException(), isNull);
      expect(noMenu(find.text('Calcular um aparelho')), findsOneWidget);
    });

    testWidgets('menu tem a logo com o nome ao lado e leva para Minha casa', (tester) async {
      telaDeCelular(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(boasVindas: false));
        await tester.pumpAndSettle();
        await abrirMenu(tester);
        expect(noMenu(find.byType(MarcaIamp)), findsOneWidget);
        expect(noMenu(logo), findsOneWidget);
        expect(noMenu(find.text('Iamp')), findsOneWidget);
        for (final item in ['Início', 'Calcular um aparelho', 'Estimar um aparelho', 'Minha casa', 'Economizar']) {
          expect(noMenu(find.text(item)), findsOneWidget);
        }

        await tester.tap(noMenu(find.text('Minha casa')));
        await tester.pumpAndSettle();
      }, apiFalsa);
      expect(find.byType(Drawer), findsNothing); // fechou
      expect(abaAtual.value, Aba.casa);
      expect(find.text('Sua casa ainda está vazia'), findsOneWidget);
    });

    testWidgets('menu: "Estimar um aparelho" abre a estimativa e "Início" volta para as boas-vindas', (tester) async {
      telaDeCelular(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(boasVindas: false));
        await tester.pumpAndSettle();
        await abrirMenu(tester);
        await tester.tap(noMenu(find.text('Estimar um aparelho')));
        await tester.pumpAndSettle();
        expect(find.byType(TelaEstimar), findsOneWidget);
        expect(find.byTooltip('Menu'), findsNothing); // tela de dentro: seta de voltar no lugar do menu

        await tester.pageBack();
        await tester.pumpAndSettle();
        await abrirMenu(tester);
        await tester.tap(noMenu(find.text('Início')));
        await tester.pumpAndSettle();
        expect(find.text('Comece a economizar'), findsOneWidget);

        await tester.tap(find.text('Comece a economizar'));
        await tester.pumpAndSettle();
      }, apiFalsa);
      expect(find.text('Qual aparelho você quer calcular?'), findsOneWidget);
    });
  });

  group('App', () {
    testWidgets('abre em Calcular com o nome Iamp, as 3 abas e o tema preto e amarelo', (tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(boasVindas: false));
        await tester.pumpAndSettle();
      }, apiFalsa);
      expect(find.text('Iamp'), findsOneWidget);
      expect(find.text('iamp'), findsNothing);
      expect(find.text('Qual aparelho você quer calcular?'), findsOneWidget);
      expect(find.text('Etapa 1 de 6'), findsOneWidget);
      for (final aba in ['Calcular', 'Minha casa', 'Economizar']) {
        expect(find.text(aba), findsWidgets);
      }
      expect(find.text('Geladeira ou freezer'), findsOneWidget);
      expect(find.textContaining('Gás'), findsNothing);
      final tema = Theme.of(tester.element(find.text('Qual aparelho você quer calcular?')));
      expect(tema.scaffoldBackgroundColor, Cores.preto);
      expect(tema.colorScheme.primary, Cores.amarelo);
      expect(tema.extension<Iamp>(), isNotNull);
    });

    testWidgets('aba Minha casa vazia explica como adicionar', (tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(boasVindas: false));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Minha casa'));
        await tester.pumpAndSettle();
      }, apiFalsa);
      expect(find.text('Sua casa ainda está vazia'), findsOneWidget);
      expect(find.text('Calcular um aparelho'), findsOneWidget);
    });

    testWidgets('aba Economizar sem aparelhos pede para calcular antes (nao chama a IA)', (tester) async {
      final pedidos = <Uri>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(boasVindas: false));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Economizar'));
        await tester.pumpAndSettle();
      }, () => apiFalsa(pedidos: pedidos));
      expect(find.text('Primeiro, calcule seus aparelhos'), findsOneWidget);
      expect(pedidos.where((u) => u.path == '/eco-coach'), isEmpty);
    });

    testWidgets('calculo completo: tipo, modelo, estado, distribuidora, resultado e casa', (tester) async {
      telaDeCelular(tester);
      final pedidos = <Uri>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(boasVindas: false));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Geladeira ou freezer'));
        await tester.pumpAndSettle();
        expect(find.text('Etapa 2 de 6'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'brastemp');
        await tester.tap(find.text('Buscar'));
        await tester.pumpAndSettle();
        expect(pedidos.last.queryParameters['categoria'], 'refrigerador');
        expect(find.text('BRASTEMP GELA'), findsOneWidget); // um tipo so: secao ja aberta
        expect(find.text('Máquinas de lavar'), findsNothing);

        await tester.tap(find.text('BRASTEMP GELA'));
        await tester.pumpAndSettle();
        expect(find.text('Em qual estado você mora?'), findsOneWidget);
        await tester.tap(find.text('Paraná'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('COPEL-DIS'));
        await tester.pumpAndSettle();

        expect(find.text('Etapa 6 de 6'), findsOneWidget);
        expect(find.text('R\$ 31,68'), findsOneWidget);
        await tester.tap(find.text('Adicionar à minha casa'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Está na sua casa: ver o total'));
        await tester.pumpAndSettle();
      }, () => apiFalsa(pedidos: pedidos));
      expect(abaAtual.value, Aba.casa);
      expect(find.text('O que mais pesa na conta'), findsOneWidget);
      expect(find.text('R\$ 31,68 por mês'), findsWidgets);
    });

    testWidgets('a mesma tarifa de antes aparece como primeira opcao', (tester) async {
      casa.lembrarTarifa(EscolhaTarifa.manual(0.9));
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(theme: temaIamp(), home: TelaEstado(consulta: consulta('refrigerador', id: 2))));
        await tester.pumpAndSettle();
      }, apiFalsa);
      expect(find.text('Usar a mesma conta de luz de antes?'), findsOneWidget);
      expect(find.text('Sim, usar Tarifa da conta de luz'), findsOneWidget);
      expect(find.text('Prefiro digitar a tarifa da minha conta'), findsOneWidget);
    });
  });

  group('Acessibilidade', () {
    Future<void> casaCheia(WidgetTester tester) async {
      casa.adicionar(consulta('chuveiro'), resultado('chuveiro', 41.25, 31.68));
      casa.adicionar(consulta('refrigerador', id: 2), resultado('refrigerador', 32.1, 24.65));
      await tester.pumpWidget(MaterialApp(theme: temaIamp(), home: const TelaMinhaCasa()));
      await tester.pumpAndSettle();
    }

    testWidgets('fonte 2x nao quebra a tela inicial nem a busca', (tester) async {
      telaDeCelular(tester, fonte: 2, alta: true);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(boasVindas: false));
        await tester.pumpAndSettle();
        expect(find.text('Qual aparelho você quer calcular?'), findsOneWidget);
        await tester.tap(find.text('Geladeira ou freezer'));
        await tester.pumpAndSettle();
        expect(find.text('Qual é a marca e o modelo?'), findsOneWidget);
      }, apiFalsa);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fonte 2x nao quebra Minha casa, o resultado e o tempo de retorno', (tester) async {
      telaDeCelular(tester, fonte: 2, alta: true);
      await casaCheia(tester);
      expect(find.text('Quantidade'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        MaterialApp(
          theme: temaIamp(),
          home: Scaffold(
            body: ListView(
              children: [
                DetalhesDoResultado(resultado('refrigerador', 41.25, 31.68)),
                CartaoPayback(
                  Payback.fromJson({'preco_novo': 2499.9, 'meses': 80, 'anos': 6.7, 'texto': 'Se paga em 80 meses.'}),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Demora para se pagar'), findsOneWidget); // a cor vem com o texto
      expect(tester.takeException(), isNull);
    });

    testWidgets('fonte 2x nao quebra as perguntas da estimativa', (tester) async {
      telaDeCelular(tester, fonte: 2, alta: true);
      await tester.pumpWidget(
        MaterialApp(
          theme: temaIamp(),
          home: TelaEstimar(carregarCategorias: categoriasDeTeste, carregarResistivos: resistivosDeTeste),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eletroportátil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Air fryer'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Não sei, usar a típica'));
      await tester.pumpAndSettle();
      expect(find.text('Minutos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Minha casa: toque de 48dp, botoes com nome, contraste AA', (tester) async {
      telaDeCelular(tester);
      final semantica = tester.ensureSemantics();
      await casaCheia(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expect(find.bySemanticsLabel(RegExp('Remover MARCA CHUVEIRO da casa')), findsOneWidget);
      expect(find.byTooltip('Aumentar a quantidade de MARCA CHUVEIRO'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('tela inicial: toque de 48dp, botoes com nome, contraste AA', (tester) async {
      telaDeCelular(tester);
      final semantica = tester.ensureSemantics();
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(boasVindas: false));
        await tester.pumpAndSettle();
      }, apiFalsa);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('valor que conta ate o numero e lido so com o valor final', (tester) async {
      final semantica = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: temaIamp(),
          home: Scaffold(body: CartaoDestaque(titulo: 'Gasto por mês', valor: 31.68, formatar: reais)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100)); // no meio da animacao
      expect(find.bySemanticsLabel(RegExp(r'R\$ 31,68')), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('remover um aparelho pode ser desfeito', (tester) async {
      telaAlta(tester);
      await casaCheia(tester);
      await tester.tap(find.text('Remover').first);
      await tester.pumpAndSettle();
      expect(casa.itens, hasLength(1));
      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      expect(casa.itens, hasLength(2));
      expect(casa.porCusto.first.resultado.categoria, 'chuveiro');
    });
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

  test('remover devolve a posicao e reinserir coloca o item no mesmo lugar', () {
    casa.adicionar(consulta('televisor'), resultado('televisor', 10, 8));
    final meio = casa.adicionar(consulta('chuveiro', id: 2), resultado('chuveiro', 41.25, 31.68));
    casa.adicionar(consulta('lampada_led', id: 3), resultado('lampada_led', 1.5, 1.2));
    final posicao = casa.remover(meio);
    expect(posicao, 1);
    casa.reinserir(meio, posicao);
    casa.reinserir(meio, posicao); // de novo nao duplica
    expect(casa.itens.map((i) => i.resultado.categoria), ['televisor', 'chuveiro', 'lampada_led']);
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
      ...resultadoJson('refrigerador', 45.75, 35.14, tarifa: 0.768),
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
      Resultado.fromJson({...resultadoJson('refrigerador', 32.1, 24.65, tarifa: 0.76802), 'custo_ano': 295.84}),
    );
    expect(casa.custoAno, 295.84);
  });

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
    t.limpar();
    expect(t.vazio, isTrue);
    expect(duracao(0.25), '15 min');
    expect(duracao(4.5), '4 h 30 min');
    expect(duracao(2), '2 h');
  });

  group('Estimativa, uma pergunta por tela', () {
    Widget telaEstimar() => MaterialApp(
      theme: temaIamp(),
      home: TelaEstimar(carregarCategorias: categoriasDeTeste, carregarResistivos: resistivosDeTeste),
    );

    Future<void> tocar(WidgetTester tester, String texto) async {
      await tester.tap(find.text(texto));
      await tester.pumpAndSettle();
    }

    testWidgets('geladeira: tipo, gelo, capacidade, freezer e ano, cada um na sua tela', (tester) async {
      telaAlta(tester);
      await tester.pumpWidget(telaEstimar());
      await tester.pumpAndSettle();
      expect(find.text('Que tipo de aparelho é?'), findsOneWidget);
      await tocar(tester, 'Eletrodoméstico grande');
      await tocar(tester, 'Geladeira ou freezer');
      await tocar(tester, 'Geladeira duplex (2 portas)');
      expect(find.text('Ela forma gelo nas paredes?'), findsOneWidget);
      await tocar(tester, 'Não forma gelo (frost-free)');

      await tocar(tester, 'Continuar');
      expect(find.textContaining('capacidade total em litros'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '407');
      await tocar(tester, 'Continuar');
      await tocar(tester, 'Não sei'); // litros do freezer
      expect(find.text('Em que ano você comprou?'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1900');
      await tocar(tester, 'Continuar');
      expect(find.textContaining('ano de compra entre 1980'), findsOneWidget);
    });

    testWidgets('voltar volta uma pergunta e guarda a resposta', (tester) async {
      telaAlta(tester);
      // como no app: a estimativa e aberta por cima de outra tela
      await tester.pumpWidget(
        MaterialApp(
          theme: temaIamp(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TelaEstimar(carregarCategorias: categoriasDeTeste, carregarResistivos: resistivosDeTeste),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tocar(tester, 'abrir');
      await tocar(tester, 'Eletrodoméstico grande');
      await tocar(tester, 'Geladeira ou freezer');
      expect(find.text('Qual é o tipo?'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Qual é o aparelho?'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget); // a geladeira continua marcada
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack(); // na primeira pergunta, voltar sai da estimativa
      await tester.pumpAndSettle();
      expect(find.text('abrir'), findsOneWidget);
    });

    testWidgets('eletroportateis mostram a potencia tipica e o tempo em horas e minutos', (tester) async {
      telaAlta(tester);
      await tester.pumpWidget(telaEstimar());
      await tester.pumpAndSettle();
      await tocar(tester, 'Eletroportátil');
      expect(find.text('Típica: 1500 W'), findsOneWidget);
      await tocar(tester, 'Air fryer');
      expect(find.text('Não sei, usar a típica (1500 W)'), findsOneWidget);
      await tocar(tester, 'Não sei, usar a típica (1500 W)');
      expect(find.text('Sugerido: 30 min. Troque pelo seu uso real.'), findsOneWidget);
      expect(find.text('Minutos'), findsOneWidget);
    });

    testWidgets('maquina de lavar sem numero pergunta o tipo pelo nome conhecido e o tamanho', (tester) async {
      telaAlta(tester);
      await tester.pumpWidget(telaEstimar());
      await tester.pumpAndSettle();
      await tocar(tester, 'Eletrodoméstico grande');
      await tocar(tester, 'Máquina de lavar');
      expect(find.text('Top Load (automatica)'), findsNothing);
      expect(find.text('Tampa em cima.'), findsOneWidget);
      await tocar(tester, 'Automática que abre por cima');
      expect(find.text('Qual é o tamanho?'), findsOneWidget);
      await tocar(tester, 'Outro tamanho');
      await tocar(tester, 'Continuar');
      expect(find.textContaining('Se não souber, volte e escolha um dos tamanhos'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tocar(tester, '8 kg');
      expect(find.text('Você consegue ver algum destes no aparelho?'), findsOneWidget);
      expect(find.text('Etiqueta amarela do Inmetro'), findsOneWidget);
      await tocar(tester, 'Não consigo ver nenhum');
      expect(find.text('Quantas vezes por mês você lava roupa?'), findsOneWidget);
    });

    testWidgets('televisao antiga usa a potencia escrita nela e as horas viram obrigatorias', (tester) async {
      telaAlta(tester);
      await tester.pumpWidget(telaEstimar());
      await tester.pumpAndSettle();
      await tocar(tester, 'Eletrodoméstico grande');
      await tocar(tester, 'Televisor');
      await tocar(tester, '32 polegadas');
      await tocar(tester, 'Potência escrita no aparelho');
      expect(find.text('Qual é a potência?'), findsOneWidget);
      await tocar(tester, 'Continuar');
      expect(find.text('Digite o número em W, como está escrito. Ex.: 120.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '2000');
      await tocar(tester, 'Continuar');
      expect(find.text('Digite o número em W, como está escrito. Ex.: 120.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '120');
      await tocar(tester, 'Continuar');
      expect(find.text('Quanto tempo por dia ele fica ligado?'), findsOneWidget);
      expect(find.text('Não sei, usar o valor do Inmetro'), findsNothing);
      await tocar(tester, 'Continuar');
      expect(find.text('Digite o tempo de uso por dia.'), findsOneWidget);
    });

    testWidgets('ventilador pergunta a velocidade e as horas; com a potencia, so as horas', (tester) async {
      telaAlta(tester);
      await tester.pumpWidget(telaEstimar());
      await tester.pumpAndSettle();
      await tocar(tester, 'Eletrodoméstico grande');
      await tocar(tester, 'Ventilador de teto');
      await tocar(tester, 'Não consigo ver nenhum');
      expect(find.text('Qual é o tamanho?'), findsNothing);
      await tocar(tester, 'Média');
      expect(find.text('Quanto tempo por dia ele fica ligado?'), findsOneWidget);
      expect(find.text('Não sei, usar o valor do Inmetro'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tocar(tester, 'Potência escrita no aparelho');
      await tester.enterText(find.byType(TextField), '130');
      await tocar(tester, 'Continuar');
      expect(find.text('Em qual velocidade você costuma usar?'), findsNothing);
      expect(find.text('Quanto tempo por dia ele fica ligado?'), findsOneWidget);
    });

    testWidgets('chuveiro vai direto para a potencia', (tester) async {
      telaAlta(tester);
      await tester.pumpWidget(telaEstimar());
      await tester.pumpAndSettle();
      await tocar(tester, 'Eletrodoméstico grande');
      await tocar(tester, 'Chuveiro elétrico');
      expect(find.text('Qual é a potência?'), findsOneWidget);
      expect(find.text('Não consigo ver nenhum'), findsNothing);
      await tocar(tester, 'Continuar');
      expect(find.text('Digite o número em W, como está escrito. Ex.: 5500.'), findsOneWidget);
    });

    testWidgets('ventilador do catalogo pergunta a velocidade e depois as horas', (tester) async {
      telaAlta(tester);
      final c = consulta('ventilador_de_mesa', id: 3);
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(theme: temaIamp(), home: TelaUso(consulta: c)));
        await tester.pumpAndSettle();
        await tocar(tester, 'Média');
        expect(find.text('Quanto tempo por dia ele fica ligado?'), findsOneWidget);
        await tocar(tester, 'Continuar');
        expect(find.textContaining('Informe quanto tempo por dia'), findsOneWidget);
        await tester.enterText(find.widgetWithText(TextField, 'Horas'), '8');
        await tocar(tester, 'Continuar');
      }, apiFalsa);
      expect(c.velocidade, 'media');
      expect(c.horasDia, 8);
    });

    testWidgets('chamada da busca abre a estimativa', (tester) async {
      telaAlta(tester);
      await tester.pumpWidget(MaterialApp(theme: temaIamp(), home: const Scaffold(body: ChamadaEstimar())));
      await tester.tap(find.text('Não achou? Estime o gasto'));
      await tester.pumpAndSettle();
      expect(find.text('Estimar o gasto'), findsOneWidget);
    });
  });

  testWidgets('dicas do eco-coach mostram o texto formatado e as fontes', (tester) async {
    telaAlta(tester);
    final r = resultado('air_fryer', 37.5, 28.8);
    Future<Dicas> falso(Resultado _) async => Dicas.fromJson({
      'dicas': 'A air fryer custa R\$ 28,80 por mês.\n\n## Como evitar desperdício\n'
          '- **Não abra** a cesta toda hora [1].\n2. Use o tempo certo [2].',
      'fontes': [
        {'n': 1, 'documento': 'Cartilha', 'orgao': 'Cemig', 'url': 'https://cemig.com.br'},
        {'n': 2, 'documento': 'Dicas', 'orgao': 'Inmetro', 'url': 'https://gov.br'},
      ],
      'aviso': 'Dicas geradas por IA.',
    });
    await tester.pumpWidget(MaterialApp(theme: temaIamp(), home: TelaDicas(resultado: r, buscarDicas: falso)));
    await tester.pumpAndSettle();
    expect(find.text('Como evitar desperdício'), findsOneWidget);
    expect(find.textContaining('a cesta toda hora [1].', findRichText: true), findsOneWidget);
    expect(find.textContaining('Use o tempo certo [2].', findRichText: true), findsOneWidget);
    expect(find.text('Cemig · Cartilha'), findsOneWidget);
    expect(find.text('Dicas geradas por IA.'), findsOneWidget);
  });

  testWidgets('dicas mostram o erro quando o eco-coach esta fora do ar', (tester) async {
    Future<Dicas> fora(Resultado _) async => throw ApiErro('Eco-Coach indisponivel: GEMINI_API_KEY nao configurada');
    await tester.pumpWidget(
      MaterialApp(theme: temaIamp(), home: TelaDicas(resultado: resultado('air_fryer', 1, 1), buscarDicas: fora)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('GEMINI_API_KEY'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  group('Eco-Coach', () {
    test('plano: citacoes [n] em amarelo e **negrito** sem os asteriscos', () {
      const base = TextStyle(fontSize: 18);
      final pedacos = pedacosDoTexto('Desligue o **ar** nas saidas [1] e use o timer [2, 3].', base);
      expect(pedacos.map((p) => p.text).join(), 'Desligue o ar nas saidas [1] e use o timer [2, 3].');
      final citacoes = pedacos.where((p) => p.text!.startsWith('['));
      expect(citacoes.map((p) => p.text), ['[1]', '[2, 3]']);
      expect(citacoes.every((p) => p.style!.color == Cores.amarelo), isTrue);
      expect(citacoes.every((p) => p.style!.fontSize == 18), isTrue); // citacao do mesmo tamanho do texto
      expect(pedacos.firstWhere((p) => p.text == 'ar').style!.fontWeight, FontWeight.bold);
    });

    testWidgets('plano: titulos, listas e paragrafos viram widgets', (tester) async {
      const md = '## Ações recomendadas\n\n1. Banho mais curto [1]\n- Geladeira longe do fogão [2]\nTexto final.';
      await tester.pumpWidget(MaterialApp(theme: temaIamp(), home: const Scaffold(body: TextoPlano(md))));
      expect(find.text('Ações recomendadas'), findsOneWidget);
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

    testWidgets('aba Economizar so pede o plano quando a pessoa toca no botao', (tester) async {
      casa.adicionar(consulta('televisor'), resultado('televisor', 10, 8));
      var pedidos = 0;
      final api = MockClient((r) async {
        if (r.url.path == '/eco-coach') pedidos++;
        if (r.url.path == '/categorias') return http.Response('[]', 200, headers: _json);
        return http.Response(jsonEncode(planoExemplo), 200, headers: _json);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(boasVindas: false));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Economizar'));
        await tester.pumpAndSettle();
        expect(pedidos, 0);
        await tester.tap(find.text('Montar meu plano'));
        await tester.pumpAndSettle();
      }, () => api);
      expect(pedidos, 1);
      expect(find.text('Seu plano de economia'), findsOneWidget);
      expect(find.text('Montar outro plano'), findsOneWidget);
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
        home: Scaffold(body: SingleChildScrollView(child: ResultadosPorTipo(lista, aoEscolher: (_) {}))),
      ),
    );

    testWidgets('cada tipo vira uma secao fechada que abre ao tocar', (tester) async {
      telaAlta(tester);
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

    testWidgets('procurar pela marca, sem tipo, busca em todos os tipos', (tester) async {
      telaAlta(tester);
      final pedidos = <Uri>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(theme: temaIamp(), home: const TelaModelo()));
        await tester.enterText(find.byType(TextField), 'brastemp');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
      }, () => apiFalsa(pedidos: pedidos));
      expect(pedidos.last.queryParameters.containsKey('categoria'), isFalse);
      expect(find.text('2 aparelhos encontrados'), findsOneWidget);
      expect(find.text('Máquinas de lavar'), findsOneWidget);
      expect(find.text('Geladeiras'), findsOneWidget);
    });
  });

  group('Lista de marcas (etapa 2)', () {
    Future<void> abrirGeladeira(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(theme: temaIamp(), home: const TelaModelo(categoria: 'refrigerador')));
      await tester.pumpAndSettle();
    }

    testWidgets('mostra todas as marcas do tipo e abre os modelos ao tocar na marca', (tester) async {
      telaAlta(tester);
      final pedidos = <Uri>[];
      await http.runWithClient(() async {
        await abrirGeladeira(tester);
        expect(find.text('Ou escolha a marca'), findsOneWidget);
        expect(find.text('2 marcas'), findsOneWidget);
        expect(find.text('BRASTEMP'), findsOneWidget);
        expect(find.text('60 modelos'), findsOneWidget);
        expect(pedidos.where((u) => u.path == '/modelos'), isEmpty); // so carrega ao abrir

        await tester.tap(find.text('BRASTEMP'));
        await tester.pumpAndSettle();
        expect(pedidos.last.queryParameters, {'categoria': 'refrigerador', 'marca': 'BRASTEMP', 'limite': '50'});
        await tester.tap(find.text('GELA'));
        await tester.pumpAndSettle();
      }, () => apiFalsa(pedidos: pedidos));
      // segue o calculo normal (geladeira nao pergunta o uso: vai direto para o estado)
      expect(find.text('Em qual estado você mora?'), findsOneWidget);
    });

    testWidgets('marca com mais modelos que o limite avisa para digitar o modelo', (tester) async {
      tester.view.physicalSize = const Size(800, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await http.runWithClient(() async {
        await abrirGeladeira(tester);
        await tester.tap(find.text('CONSUL'));
        await tester.pumpAndSettle();
      }, apiFalsa);
      expect(find.text('CRM1'), findsOneWidget);
      expect(find.textContaining('Mostrando 50 de 60'), findsOneWidget);
    });

    testWidgets('digitar filtra as marcas e "Buscar" continua procurando pelo modelo', (tester) async {
      telaAlta(tester);
      final pedidos = <Uri>[];
      await http.runWithClient(() async {
        await abrirGeladeira(tester);
        await tester.enterText(find.byType(TextField), 'cons');
        await tester.pump();
        expect(find.text('1 marca'), findsOneWidget);
        expect(find.text('CONSUL'), findsOneWidget);
        expect(find.text('BRASTEMP'), findsNothing);

        await tester.enterText(find.byType(TextField), 'xyz');
        await tester.pump();
        expect(find.textContaining('Nenhuma marca com "xyz"'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'brastemp');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
      }, () => apiFalsa(pedidos: pedidos));
      expect(pedidos.last.path, '/aparelhos');
      expect(find.text('1 aparelho encontrado'), findsOneWidget);
      expect(find.text('Ou escolha a marca'), findsNothing); // o resultado da busca substitui a lista
    });

    testWidgets('sem tipo escolhido nao mostra lista de marcas', (tester) async {
      telaAlta(tester);
      final pedidos = <Uri>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(theme: temaIamp(), home: const TelaModelo()));
        await tester.pumpAndSettle();
      }, () => apiFalsa(pedidos: pedidos));
      expect(find.text('Ou escolha a marca'), findsNothing);
      expect(pedidos.where((u) => u.path == '/marcas'), isEmpty);
    });
  });

  testWidgets('aviso de aparelho adicionado some sozinho depois de 5 s', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: temaIamp(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => avisarAdicionado(ScaffoldMessenger.of(context), 'Foi.'),
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

Future<List<Resistivo>> resistivosDeTeste() async => [
  Resistivo.fromJson({'categoria': 'air_fryer', 'nome': 'Air fryer', 'potencia_w': 1500, 'horas_dia': 0.5, 'dias_mes': 15}),
];

Map<String, dynamic> _forma(String campo, String unidade, String exemplo, double maximo) => {
  'campo': campo,
  'nome': campo == 'potencia_w' ? 'Potência escrita no aparelho' : 'Etiqueta amarela do Inmetro',
  'rotulo': campo == 'potencia_w' ? 'Potência' : 'Consumo de energia',
  'unidade': unidade,
  'onde': 'Escrito no aparelho.',
  'dica': null,
  'exemplo': exemplo,
  'maximo': maximo,
};

Map<String, dynamic> _categoria(
  String c,
  String nome, {
  String? medida,
  String? unidade,
  List<Map<String, dynamic>> tamanhos = const [],
  List<Map<String, dynamic>> tipos = const [],
  bool especial = false,
  List<Map<String, dynamic>> formas = const [],
  bool obrigatorio = false,
  Map<String, dynamic>? uso,
}) => {
  'categoria': c,
  'nome': nome,
  'especial': especial,
  'medida': medida,
  'unidade_medida': unidade,
  'tamanhos': tamanhos,
  'tipos': tipos,
  'formas': formas,
  'valor_obrigatorio': obrigatorio,
  'uso': uso ?? {'pergunta': null},
};

Future<List<CategoriaEstimavel>> categoriasDeTeste() async => [
  for (final j in [
    _categoria('refrigerador', 'Geladeira ou freezer', especial: true),
    _categoria(
      'maquina_de_lavar',
      'Máquina de lavar',
      medida: 'Capacidade de lavagem (kg)',
      unidade: 'kg',
      tamanhos: [
        {'valor': 8, 'nome': '8 kg'},
      ],
      tipos: [
        {'valor': 'Top Load (automatica)', 'nome': 'Automática que abre por cima', 'descricao': 'Tampa em cima.'},
      ],
      formas: [_forma('kwh_ciclo', 'kWh/ciclo', 'Ex.: 0,25', 5)],
      uso: {'pergunta': 'ciclos', 'padrao': 12},
    ),
    _categoria(
      'televisor',
      'Televisor',
      medida: 'Tamanho da tela (polegadas)',
      unidade: 'polegadas',
      tamanhos: [
        {'valor': 32, 'nome': '32 polegadas'},
      ],
      formas: [_forma('potencia_w', 'W', 'Ex.: 120', 1500), _forma('kwh_mes', 'kWh/mês', 'Ex.: 9,9', 300)],
      uso: {'pergunta': 'horas', 'padrao': null, 'opcional': true},
    ),
    _categoria(
      'ventilador_de_teto',
      'Ventilador de teto',
      formas: [_forma('potencia_w', 'W', 'Ex.: 130', 500)],
      uso: {
        'pergunta': 'velocidade',
        'opcoes': ['baixa', 'media', 'alta'],
        'padrao': 'media',
        'perguntar_horas': true,
      },
    ),
    _categoria(
      'chuveiro',
      'Chuveiro elétrico',
      obrigatorio: true,
      formas: [_forma('potencia_w', 'W', 'Ex.: 5500', 12000)],
      uso: {'pergunta': 'horas', 'padrao': null},
    ),
  ])
    CategoriaEstimavel.fromJson(j),
];

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
