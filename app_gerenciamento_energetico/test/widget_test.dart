import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_gerenciamento_energetico/api.dart';
import 'package:app_gerenciamento_energetico/casa.dart';
import 'package:app_gerenciamento_energetico/conta.dart';
import 'package:app_gerenciamento_energetico/idioma.dart';
import 'package:app_gerenciamento_energetico/main.dart';
import 'package:app_gerenciamento_energetico/navegacao.dart';
import 'package:app_gerenciamento_energetico/tema.dart';
import 'package:app_gerenciamento_energetico/telas/busca.dart';
import 'package:app_gerenciamento_energetico/telas/cadastro.dart';
import 'package:app_gerenciamento_energetico/telas/comparar.dart';
import 'package:app_gerenciamento_energetico/telas/comum.dart';
import 'package:app_gerenciamento_energetico/telas/dicas.dart';
import 'package:app_gerenciamento_energetico/telas/distribuidora.dart';
import 'package:app_gerenciamento_energetico/telas/estimar.dart';
import 'package:app_gerenciamento_energetico/telas/minha_casa.dart';
import 'package:app_gerenciamento_energetico/telas/resultado.dart';
import 'package:app_gerenciamento_energetico/telas/texto_plano.dart';
import 'package:app_gerenciamento_energetico/telas/uso.dart';

Map<String, dynamic> resultJson(String category, double kwh, double cost, {double tariff = 0.8}) => {
  'categoria': category,
  'marca': 'MARCA',
  'modelo': category.toUpperCase(),
  'detalhe': '',
  'distribuidora': 'COPEL-DIS',
  'uf': 'PR',
  'kwh_mes': kwh,
  'metodo': 'teste',
  'tarifa_kwh': tariff,
  'origem_tarifa': 'teste',
  'custo_mes': cost,
  'custo_ano': cost * 12,
  'avisos': <String>[],
};

Result result(String category, double kwh, double cost, {double tariff = 0.8}) =>
    Result.fromJson(resultJson(category, kwh, cost, tariff: tariff));

Query query(String category, {int id = 1}) =>
    Query(Appliance(id: id, category: category, brand: 'MARCA', model: category.toUpperCase()));

final _json = {'content-type': 'application/json; charset=utf-8'};

/// API falsa com o caminho completo do calculo de um aparelho do catalogo.
MockClient apiFake({List<Uri>? requests, List<String?>? languages}) => MockClient((r) async {
  requests?.add(r.url);
  languages?.add(r.headers['Accept-Language']);
  final body = switch (r.url.path) {
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
    '/calcular' => resultJson('refrigerador', 41.25, 31.68, tariff: 0.768),
    _ => null,
  };
  return body == null ? http.Response('{"detail": "nao existe"}', 404) : http.Response(jsonEncode(body), 200, headers: _json);
});

void main() {
  setUp(() {
    lightMode.value = false;
    account.value = null;
    home.clear();
    currentTab.value = AppTab.calculate;
    language.value = Language.pt; // o app sempre abre em portugues
  });

  /// Celular de 360dp de largura. `alta`: tela comprida, para ver tudo sem rolar com fonte grande
  /// (o que quebra com fonte 2x e a largura: textos e botoes lado a lado).
  void phoneScreen(WidgetTester tester, {double fontScale = 1, bool tall = false}) {
    tester.view.physicalSize = Size(360 * 3, (tall ? 3000 : 780) * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = fontScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('Boas-vindas e menu', () {
    Finder inMenu(Finder f) => find.descendant(of: find.byType(Drawer), matching: f);
    // a logo e carregada ja no tamanho da tela (cacheWidth), por isso vem dentro de um ResizeImage
    final logo = find.byWidgetPredicate(
      (w) => w is Image && w.image is ResizeImage && (w.image as ResizeImage).imageProvider == const AssetImage(IampBrand.image),
    );

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
    }

    testWidgets('abre nas boas-vindas e "Comece a economizar" leva ao cálculo', (tester) async {
      phoneScreen(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp());
        await tester.pumpAndSettle();
        expect(find.text('Comece a economizar'), findsOneWidget);
        expect(logo, findsOneWidget);
        expect(find.text('Qual aparelho você quer calcular?'), findsNothing);
        // so a marca e o botao: sem frases, e o icone ao lado do nome (nao em cima)
        expect(find.text('Sua conta de luz, sem surpresas'), findsNothing);
        expect(find.textContaining('Inmetro'), findsNothing);
        final icon = tester.getRect(logo);
        final name = tester.getRect(find.text('Iamp'));
        expect(name.left, greaterThan(icon.right));
        expect(name.center.dy, closeTo(icon.center.dy, 2));
        expect(icon.width, greaterThanOrEqualTo(100)); // maior que a logo do menu (48)

        await tester.tap(find.text('Comece a economizar'));
        await tester.pumpAndSettle();
      }, apiFake);
      expect(find.text('Comece a economizar'), findsNothing);
      expect(find.text('Qual aparelho você quer calcular?'), findsOneWidget);
      expect(currentTab.value, AppTab.calculate);
    });

    testWidgets('boas-vindas cabe na tela com a fonte do sistema em 2x', (tester) async {
      phoneScreen(tester, fontScale: 2);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp());
        await tester.pumpAndSettle();
      }, apiFake);
      expect(tester.takeException(), isNull);
      expect(find.text('Comece a economizar'), findsOneWidget);
    });

    testWidgets('menu cabe na tela com a fonte do sistema em 2x (textos quebram a linha)', (tester) async {
      phoneScreen(tester, fontScale: 2);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(showWelcome: false));
        await tester.pumpAndSettle();
        await openMenu(tester);
      }, apiFake);
      expect(tester.takeException(), isNull);
      expect(inMenu(find.text('Calcular um aparelho')), findsOneWidget);
    });

    testWidgets('menu tem a logo com o nome ao lado e leva para Minha casa', (tester) async {
      phoneScreen(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(showWelcome: false));
        await tester.pumpAndSettle();
        await openMenu(tester);
        expect(inMenu(find.byType(IampBrand)), findsOneWidget);
        expect(inMenu(logo), findsOneWidget);
        expect(inMenu(find.text('Iamp')), findsOneWidget);
        for (final item in ['Início', 'Calcular um aparelho', 'Estimar um aparelho', 'Minha casa', 'Economizar']) {
          expect(inMenu(find.text(item)), findsOneWidget);
        }

        await tester.tap(inMenu(find.text('Minha casa')));
        await tester.pumpAndSettle();
      }, apiFake);
      expect(find.byType(Drawer), findsNothing); // fechou
      expect(currentTab.value, AppTab.home);
      expect(find.text('Sua casa ainda está vazia'), findsOneWidget);
    });

    testWidgets('menu: "Estimar um aparelho" abre a estimativa e "Início" volta para as boas-vindas', (tester) async {
      phoneScreen(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(showWelcome: false));
        await tester.pumpAndSettle();
        await openMenu(tester);
        await tester.tap(inMenu(find.text('Estimar um aparelho')));
        await tester.pumpAndSettle();
        expect(find.byType(EstimateScreen), findsOneWidget);
        expect(find.byTooltip('Menu'), findsNothing); // tela de dentro: seta de voltar no lugar do menu

        // a seta de voltar segue o idioma do app (textos do Flutter em portugues: "Voltar", nao "Back")
        await tester.tap(find.byTooltip('Voltar'));
        await tester.pumpAndSettle();
        await openMenu(tester);
        await tester.tap(inMenu(find.text('Início')));
        await tester.pumpAndSettle();
        expect(find.text('Comece a economizar'), findsOneWidget);

        await tester.tap(find.text('Comece a economizar'));
        await tester.pumpAndSettle();
      }, apiFake);
      expect(find.text('Qual aparelho você quer calcular?'), findsOneWidget);
    });
  });

  group('Modo claro', () {
    Finder inMenu(Finder f) => find.descendant(of: find.byType(Drawer), matching: f);

    Future<void> chooseAppearance(WidgetTester tester, String name) async {
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(inMenu(find.text(name)), 120, scrollable: inMenu(find.byType(Scrollable)).first);
      await tester.pumpAndSettle();
      expect(inMenu(find.text('Aparência')), findsOneWidget);
      await tester.tap(inMenu(find.text(name)));
      await tester.pumpAndSettle();
    }

    testWidgets('abre no escuro; o menu troca para o claro e de volta, sem sair da tela', (tester) async {
      phoneScreen(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(showWelcome: false));
        await tester.pumpAndSettle();
        Finder question() => find.text('Qual aparelho você quer calcular?');
        expect(Theme.of(tester.element(question())).scaffoldBackgroundColor, AppColors.black);

        await chooseAppearance(tester, 'Claro');
        expect(lightMode.value, isTrue);
        final light = Theme.of(tester.element(question()));
        expect(light.brightness, Brightness.light);
        expect(light.scaffoldBackgroundColor, Palette.light.background);
        expect(light.colorScheme.primary, AppColors.yellow); // botoes continuam amarelos
        expect(Iamp.de(tester.element(question())).highlight, Palette.light.accent);

        await chooseAppearance(tester, 'Escuro');
        expect(lightMode.value, isFalse);
        expect(Theme.of(tester.element(question())).scaffoldBackgroundColor, AppColors.black);
      }, apiFake);
    });

    testWidgets('modo claro tem contraste de texto suficiente (AA) nas telas principais', (tester) async {
      phoneScreen(tester);
      final handle = tester.ensureSemantics();
      lightMode.value = true;
      home.add(query('refrigerador'), result('refrigerador', 40, 32));
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp());
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(textContrastGuideline)); // boas-vindas
        await tester.tap(find.text('Comece a economizar'));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(textContrastGuideline)); // etapa 1
        await tester.tap(find.text('Minha casa'));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(textContrastGuideline)); // minha casa com 1 aparelho
        await tester.tap(find.byTooltip('Menu'));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(textContrastGuideline)); // menu
      }, apiFake);
      handle.dispose();
    });
  });

  group('Transição entre as etapas', () {
    test('todas as plataformas usam a mesma transição, nos dois modos', () {
      for (final light in [false, true]) {
        final builders = iampTheme(light: light).pageTransitionsTheme.builders;
        for (final platform in TargetPlatform.values) {
          expect(builders[platform], isA<StepTransition>());
        }
      }
    });

    testWidgets('a tela nova entra enquanto a anterior ainda aparece, e a barra avança até a etapa', (tester) async {
      phoneScreen(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(showWelcome: false));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Geladeira ou freezer'));
        await tester.pump(); // comeca a transicao
        await tester.pump(const Duration(milliseconds: 100));
        // no meio da transicao as duas etapas estao na tela
        expect(find.text('Etapa 1 de 6'), findsOneWidget);
        expect(find.text('Etapa 2 de 6'), findsOneWidget);
        final bars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
        expect(bars.any((b) => b.value! > 1 / 6 && b.value! < 2 / 6), isTrue); // barra a caminho de 2/6
        await tester.pumpAndSettle();
        expect(find.text('Etapa 1 de 6'), findsNothing);
        final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
        expect(bar.value, closeTo(2 / 6, 0.001));
      }, apiFake);
    });

    testWidgets('com "remover animações" do sistema a tela troca direto', (tester) async {
      phoneScreen(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(showWelcome: false));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Geladeira ou freezer'));
        await tester.pumpAndSettle();
      }, apiFake);
      expect(find.text('Etapa 2 de 6'), findsOneWidget);
      expect(find.byType(SlideTransition).evaluate().where((e) {
        final w = e.widget as SlideTransition;
        return w.position.value != Offset.zero;
      }), isEmpty);
    });
  });

  group('Cadastro', () {
    testWidgets('pelas boas-vindas: valida, cria, cumprimenta pelo nome e apaga', (tester) async {
      phoneScreen(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp());
        await tester.pumpAndSettle();
        expect(find.text('Comece a economizar'), findsOneWidget); // continua dando para usar sem cadastro
        await tester.tap(find.text('Criar cadastro'));
        await tester.pumpAndSettle();
        expect(find.byType(SignUpScreen), findsOneWidget);
        expect(find.textContaining('ficam só neste aparelho'), findsOneWidget); // aviso antes de preencher

        // nome vazio e e-mail errado: nao cria
        await tester.enterText(find.byType(TextField).last, 'maria@');
        await tester.tap(find.widgetWithText(FilledButton, 'Criar cadastro'));
        await tester.pumpAndSettle();
        expect(find.text('Digite o seu nome.'), findsOneWidget);
        expect(find.textContaining('Digite um e-mail válido'), findsOneWidget);
        expect(account.value, isNull);

        await tester.enterText(find.byType(TextField).first, 'Maria Silva');
        await tester.enterText(find.byType(TextField).last, 'maria@exemplo.com');
        await tester.tap(find.widgetWithText(FilledButton, 'Criar cadastro'));
        await tester.pumpAndSettle();
        expect(account.value!.email, 'maria@exemplo.com');
        expect(find.byType(SignUpScreen), findsNothing);
        expect(find.text('Olá, Maria!'), findsOneWidget);
        expect(find.text('Cadastro criado.'), findsOneWidget);

        // o botao vira "Meu cadastro", com os dados preenchidos e a opcao de apagar
        await tester.tap(find.text('Meu cadastro'));
        await tester.pumpAndSettle();
        expect(find.text('Maria Silva'), findsOneWidget);
        await tester.tap(find.text('Apagar meu cadastro'));
        await tester.pumpAndSettle();
      }, apiFake);
      expect(account.value, isNull);
      expect(find.textContaining('Olá'), findsNothing);
      expect(find.text('Criar cadastro'), findsOneWidget);
    });

    testWidgets('o cadastro não faz nenhuma chamada para a API', (tester) async {
      phoneScreen(tester);
      final requests = <Uri>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(theme: iampTheme(), home: const SignUpScreen()));
        await tester.enterText(find.byType(TextField).first, 'João');
        await tester.enterText(find.byType(TextField).last, 'joao@exemplo.com');
        await tester.tap(find.widgetWithText(FilledButton, 'Criar cadastro'));
        await tester.pump();
      }, () => apiFake(requests: requests));
      expect(account.value!.firstName, 'João');
      expect(requests, isEmpty);
    });

    testWidgets('cadastro e boas-vindas cabem na tela com a fonte do sistema em 2x', (tester) async {
      phoneScreen(tester, fontScale: 2);
      account.value = const Account('Maria Aparecida', 'maria@exemplo.com');
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Meu cadastro'));
        await tester.pumpAndSettle();
      }, apiFake);
      expect(tester.takeException(), isNull);
      expect(find.text('Apagar meu cadastro'), findsOneWidget);
    });

    test('formato do e-mail', () {
      expect(validEmail(' maria@exemplo.com '), isTrue);
      for (final wrong in ['', 'maria', 'maria@', '@exemplo.com', 'maria@exemplo', 'ma ria@exemplo.com']) {
        expect(validEmail(wrong), isFalse, reason: wrong);
      }
    });
  });

  group('Idioma', () {
    Finder inMenu(Finder f) => find.descendant(of: find.byType(Drawer), matching: f);

    /// Rola o menu ate o item aparecer (aparencia e idioma ficam no fim da lista).
    Future<void> showInMenu(WidgetTester tester, String text) async {
      await tester.scrollUntilVisible(inMenu(find.text(text)), 120, scrollable: inMenu(find.byType(Scrollable)).first);
      await tester.pumpAndSettle();
    }

    Future<void> chooseLanguage(WidgetTester tester, String name) async {
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await showInMenu(tester, name);
      expect(inMenu(find.text('Idioma · Language')), findsOneWidget);
      await tester.tap(inMenu(find.text(name)));
      await tester.pumpAndSettle();
    }

    testWidgets('abre em português e o menu troca o app inteiro para o inglês e de volta', (tester) async {
      phoneScreen(tester);
      final languages = <String?>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp());
        await tester.pumpAndSettle();
        expect(find.text('Comece a economizar'), findsOneWidget);
        await tester.tap(find.text('Comece a economizar'));
        await tester.pumpAndSettle();
        expect(find.text('Qual aparelho você quer calcular?'), findsOneWidget);
        expect(languages, everyElement('pt-BR')); // a API responde em portugues

        await chooseLanguage(tester, 'English');
        expect(language.value, Language.en);
        expect(find.byType(Drawer), findsNothing); // o menu fecha
        expect(find.text('Which appliance do you want to calculate?'), findsOneWidget);
        expect(find.text('Step 1 of 6'), findsOneWidget);
        expect(find.text('Fridge or freezer'), findsOneWidget);
        for (final tab in ['Calculate', 'My home', 'Save']) {
          expect(find.text(tab), findsWidgets);
        }
        expect(find.text('Qual aparelho você quer calcular?'), findsNothing);

        // o pedido seguinte vai para a API em ingles e a seta de voltar e do Flutter em ingles
        languages.clear();
        await tester.tap(find.text('Fridge or freezer'));
        await tester.pumpAndSettle();
        expect(find.text('What is the brand and model?'), findsOneWidget);
        expect(languages, isNotEmpty);
        expect(languages, everyElement('en'));
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();

        await chooseLanguage(tester, 'Português');
        expect(find.text('Qual aparelho você quer calcular?'), findsOneWidget);
        expect(find.text('Etapa 1 de 6'), findsOneWidget);
      }, () => apiFake(languages: languages));
      expect(language.value, Language.pt);
    });

    testWidgets('o idioma escolhido aparece marcado (não só pela cor)', (tester) async {
      phoneScreen(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(showWelcome: false));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Menu'));
        await tester.pumpAndSettle();
        await showInMenu(tester, 'English');
      }, apiFake);
      expect(
        tester.getSemantics(inMenu(find.text('Português'))),
        isSemantics(isSelected: true, isInMutuallyExclusiveGroup: true, isButton: true),
      );
      expect(tester.getSemantics(inMenu(find.text('English'))), isSemantics(isSelected: false));
      // o sinal de "certo" fica no idioma escolhido
      final chosen = find.ancestor(of: find.text('Português'), matching: find.byType(ListTile));
      expect(find.descendant(of: chosen, matching: find.byIcon(Icons.check_circle)), findsOneWidget);
      final other = find.ancestor(of: find.text('English'), matching: find.byType(ListTile));
      expect(find.descendant(of: other, matching: find.byIcon(Icons.check_circle)), findsNothing);
    });

    testWidgets('trocar o idioma volta as abas para o começo e mantém a casa', (tester) async {
      phoneScreen(tester);
      home.add(query('chuveiro'), result('chuveiro', 41.25, 31.68));
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(showWelcome: false));
        await tester.pumpAndSettle();
        // Calcular fica no meio do fluxo (etapa 2), com respostas da API em portugues
        await tester.tap(find.text('Geladeira ou freezer'));
        await tester.pumpAndSettle();
        expect(find.text('Qual é a marca e o modelo?'), findsOneWidget);
        await tester.tap(find.text('Minha casa').last);
        await tester.pumpAndSettle();

        await chooseLanguage(tester, 'English');
        expect(find.text('My home'), findsWidgets);
        expect(find.text('R\$ 31.68 per month'), findsWidgets); // valores no formato americano, em reais
        await tester.tap(find.text('Calculate').last);
        await tester.pumpAndSettle();
      }, apiFake);
      expect(find.text('Which appliance do you want to calculate?'), findsOneWidget);
      expect(home.totalAppliances, 1);
    });

    testWidgets('com o app em inglês a tela continua sem estouro com fonte 2x', (tester) async {
      phoneScreen(tester, fontScale: 2, tall: true);
      language.value = Language.en;
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(showWelcome: false));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Menu'));
        await tester.pumpAndSettle();
      }, apiFake);
      expect(tester.takeException(), isNull);
      expect(find.text('English'), findsOneWidget);
    });

    test('reais, números e números digitados seguem o idioma', () {
      expect(reais(1234.5), 'R\$ 1.234,50');
      expect(number(41.25), '41,25');
      language.value = Language.en;
      expect(reais(1234.5), 'R\$ 1,234.50');
      expect(reais(0.76789, homes: 4), 'R\$ 0.7679');
      expect(number(41.25), '41.25');
      expect(readNumber('2,499.90'), 2499.9);
      expect(readNumber('1,299'), 1299);
      expect(readNumber('0.85'), 0.85);
      // quem digita do jeito brasileiro continua certo
      expect(readNumber('0,85'), 0.85);
      expect(readNumber('2.499,90'), 2499.9);
      expect(readNumber('R\$ 1,299.90'), 1299.9);
    });

    test('tarifa da conta de luz segue o idioma mesmo escolhida antes da troca', () {
      final tariff = TariffChoice.manual(0.85);
      expect(tariff.description, 'Tarifa da conta de luz');
      language.value = Language.en;
      expect(tariff.description, 'Rate from your electricity bill');
    });
  });

  group('App', () {
    testWidgets('abre em Calcular com o nome Iamp, as 3 abas e o tema preto e amarelo', (tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(showWelcome: false));
        await tester.pumpAndSettle();
      }, apiFake);
      expect(find.text('Iamp'), findsOneWidget);
      expect(find.text('iamp'), findsNothing);
      expect(find.text('Qual aparelho você quer calcular?'), findsOneWidget);
      expect(find.text('Etapa 1 de 6'), findsOneWidget);
      for (final tab in ['Calcular', 'Minha casa', 'Economizar']) {
        expect(find.text(tab), findsWidgets);
      }
      expect(find.text('Geladeira ou freezer'), findsOneWidget);
      expect(find.textContaining('Gás'), findsNothing);
      final theme = Theme.of(tester.element(find.text('Qual aparelho você quer calcular?')));
      expect(theme.scaffoldBackgroundColor, AppColors.black);
      expect(theme.colorScheme.primary, AppColors.yellow);
      expect(theme.extension<Iamp>(), isNotNull);
    });

    testWidgets('aba Minha casa vazia explica como adicionar', (tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(showWelcome: false));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Minha casa'));
        await tester.pumpAndSettle();
      }, apiFake);
      expect(find.text('Sua casa ainda está vazia'), findsOneWidget);
      expect(find.text('Calcular um aparelho'), findsOneWidget);
    });

    testWidgets('aba Economizar sem aparelhos pede para calcular antes (nao chama a IA)', (tester) async {
      final requests = <Uri>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(showWelcome: false));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Economizar'));
        await tester.pumpAndSettle();
      }, () => apiFake(requests: requests));
      expect(find.text('Primeiro, calcule seus aparelhos'), findsOneWidget);
      expect(requests.where((u) => u.path == '/eco-coach'), isEmpty);
    });

    testWidgets('calculo completo: tipo, modelo, estado, distribuidora, resultado e casa', (tester) async {
      phoneScreen(tester);
      final requests = <Uri>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(showWelcome: false));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Geladeira ou freezer'));
        await tester.pumpAndSettle();
        expect(find.text('Etapa 2 de 6'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'brastemp');
        await tester.tap(find.text('Buscar'));
        await tester.pumpAndSettle();
        expect(requests.last.queryParameters['categoria'], 'refrigerador');
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
      }, () => apiFake(requests: requests));
      expect(currentTab.value, AppTab.home);
      expect(find.text('O que mais pesa na conta'), findsOneWidget);
      expect(find.text('R\$ 31,68 por mês'), findsWidgets);
    });

    testWidgets('a mesma tarifa de antes aparece como primeira opcao', (tester) async {
      home.rememberTariff(TariffChoice.manual(0.9));
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(theme: iampTheme(), home: StateScreen(query: query('refrigerador', id: 2))));
        await tester.pumpAndSettle();
      }, apiFake);
      expect(find.text('Usar a mesma conta de luz de antes?'), findsOneWidget);
      expect(find.text('Sim, usar Tarifa da conta de luz'), findsOneWidget);
      expect(find.text('Prefiro digitar a tarifa da minha conta'), findsOneWidget);
    });
  });

  group('Acessibilidade', () {
    Future<void> fullHome(WidgetTester tester) async {
      home.add(query('chuveiro'), result('chuveiro', 41.25, 31.68));
      home.add(query('refrigerador', id: 2), result('refrigerador', 32.1, 24.65));
      await tester.pumpWidget(MaterialApp(theme: iampTheme(), home: const MyHomeScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('fonte 2x nao quebra a tela inicial nem a busca', (tester) async {
      phoneScreen(tester, fontScale: 2, tall: true);
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(showWelcome: false));
        await tester.pumpAndSettle();
        expect(find.text('Qual aparelho você quer calcular?'), findsOneWidget);
        await tester.tap(find.text('Geladeira ou freezer'));
        await tester.pumpAndSettle();
        expect(find.text('Qual é a marca e o modelo?'), findsOneWidget);
      }, apiFake);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fonte 2x nao quebra Minha casa, o resultado e o tempo de retorno', (tester) async {
      phoneScreen(tester, fontScale: 2, tall: true);
      await fullHome(tester);
      expect(find.text('Quantidade'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        MaterialApp(
          theme: iampTheme(),
          home: Scaffold(
            body: ListView(
              children: [
                ResultDetails(result('refrigerador', 41.25, 31.68)),
                PaybackCard(
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
      phoneScreen(tester, fontScale: 2, tall: true);
      await tester.pumpWidget(
        MaterialApp(
          theme: iampTheme(),
          home: EstimateScreen(loadCategories: testCategories, loadResistive: testResistive),
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
      phoneScreen(tester);
      final semantics = tester.ensureSemantics();
      await fullHome(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expect(find.bySemanticsLabel(RegExp('Remover MARCA CHUVEIRO da casa')), findsOneWidget);
      expect(find.byTooltip('Aumentar a quantidade de MARCA CHUVEIRO'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('tela inicial: toque de 48dp, botoes com nome, contraste AA', (tester) async {
      phoneScreen(tester);
      final semantics = tester.ensureSemantics();
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(showWelcome: false));
        await tester.pumpAndSettle();
      }, apiFake);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    });

    testWidgets('valor que conta ate o numero e lido so com o valor final', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: iampTheme(),
          home: Scaffold(body: HighlightCard(title: 'Gasto por mês', value: 31.68, format: reais)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100)); // no meio da animacao
      expect(find.bySemanticsLabel(RegExp(r'R\$ 31,68')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('remover um aparelho pode ser desfeito', (tester) async {
      tallScreen(tester);
      await fullHome(tester);
      await tester.tap(find.text('Remover').first);
      await tester.pumpAndSettle();
      expect(home.items, hasLength(1));
      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      expect(home.items, hasLength(2));
      expect(home.byCost.first.result.category, 'chuveiro');
    });
  });

  test('formata e le valores', () {
    expect(reais(31.68), 'R\$ 31,68');
    expect(reais(1234.5), 'R\$ 1.234,50');
    expect(reais(-2.5), '-R\$ 2,50');
    expect(number(41.25), '41,25');
    expect(readNumber('0,25'), 0.25);
    expect(readNumber('0.25'), 0.25);
    expect(readNumber('1.299,90'), 1299.90);
    expect(readNumber('R\$ 2.499,90'), 2499.90);
    expect(readNumber('abc'), isNull);
  });

  test('casa soma os aparelhos com a quantidade e ordena pelo custo', () {
    home.add(query('televisor'), result('televisor', 10, 8));
    final lamp = home.add(query('lampada_led', id: 2), result('lampada_led', 1.5, 1.2));
    home.add(query('chuveiro', id: 3), result('chuveiro', 41.25, 31.68));

    home.changeQuantity(lamp, 10);

    expect(home.totalAppliances, 12);
    expect(home.monthlyKwh, closeTo(10 + 15 + 41.25, 1e-9));
    expect(home.monthlyCost, closeTo(8 + 12 + 31.68, 1e-9));
    expect(home.byCost.map((i) => i.result.category), ['chuveiro', 'lampada_led', 'televisor']);
    // o perfil usa o consumo total de cada item (kWh x quantidade)
    expect(home.itemsForProfile()[1], {'categoria': 'lampada_led', 'kwh_mes': 15.0});
  });

  test('remover devolve a posicao e reinserir coloca o item no mesmo lugar', () {
    home.add(query('televisor'), result('televisor', 10, 8));
    final middle = home.add(query('chuveiro', id: 2), result('chuveiro', 41.25, 31.68));
    home.add(query('lampada_led', id: 3), result('lampada_led', 1.5, 1.2));
    final position = home.remove(middle);
    expect(position, 1);
    home.reinsert(middle, position);
    home.reinsert(middle, position); // de novo nao duplica
    expect(home.items.map((i) => i.result.category), ['televisor', 'chuveiro', 'lampada_led']);
  });

  test('trocar mantem a quantidade e qualquer mudanca apaga o perfil', () {
    final item = home.add(query('refrigerador'), result('refrigerador', 40, 32));
    home.changeQuantity(item, 2);
    home.storeProfile(
      Classification.fromJson({
        'perfil': 'Moderado',
        'kwh_total': 80,
        'kwh_por_morador': 40,
        'comparacao_media': {'mediana_kwh_por_morador': 50, 'diferenca_percentual': -20, 'texto': '20% abaixo'},
        'fracoes': {'frac_refrigerador': 1.0},
        'aviso': 'sintetico',
      }),
    );
    expect(home.profile, isNotNull);

    home.replace(item, query('refrigerador', id: 9), result('refrigerador', 25, 20));

    expect(home.profile, isNull);
    expect(home.items.single.quantity, 2);
    expect(home.items.single.query.appliance.id, 9);
    expect(home.monthlyCost, 40);
  });

  test('pergunta de uso entende horas opcionais (TV e ar-condicionado)', () {
    final tv = UsageQuestion.fromJson({'pergunta': 'horas', 'opcoes': null, 'padrao': null, 'opcional': true});
    expect(tv.question, 'horas');
    expect(tv.optional, isTrue);
    // respostas antigas da API, sem o campo, continuam funcionando
    expect(UsageQuestion.fromJson({'pergunta': 'horas', 'padrao': null}).optional, isFalse);
  });

  test('consulta manda o uso e a tarifa para a API', () {
    final c = query('chuveiro')
      ..dailyHours = 0.25
      ..tariff = TariffChoice.manual(0.9);
    expect(c.toApi(), {
      'distribuidora_id': null,
      'tarifa_manual': 0.9,
      'horas_dia': 0.25,
      'ciclos_mes': null,
      'velocidade': null,
    });
    // a copia com outro aparelho mantem o uso e a tarifa
    final replacement = c.copy(
      appliance: const Appliance(id: 5, category: 'chuveiro', brand: 'X', model: 'Y'),
    );
    expect(replacement.toApi(), c.toApi());
    expect(replacement.appliance.id, 5);
  });

  test('resultado aproximado traz a faixa e resultados antigos continuam funcionando', () {
    final base = result('refrigerador', 45.75, 35.14);
    expect(base.approximate, isFalse);
    expect(base.hasRange, isFalse);
    final r = Result.fromJson({
      ...resultJson('refrigerador', 45.75, 35.14, tariff: 0.768),
      'aproximado': true,
      'kwh_min': 41.55,
      'kwh_max': 51.92,
      'custo_min_mes': 31.91,
      'custo_max_mes': 39.87,
    });
    expect(r.approximate, isTrue);
    expect(r.hasRange, isTrue);
    expect(r.monthlyMinCost, 31.91);
  });

  test('consulta estimada manda os dados do aparelho e a tarifa para a rota da estimativa', () {
    final c = Query(
      const Appliance(id: 0, category: 'refrigerador', brand: 'Consul', model: 'CRM45'),
      estimation: const Estimate(fridgeRoute, {'tipo': 'duplex', 'volume_total_l': 407.0, 'ano_compra': 2014}),
    )..tariff = TariffChoice.manual(0.768);
    expect(c.estimated, isTrue);
    expect(c.smallAppliance, isFalse);
    expect(c.estimateBody(), {
      'distribuidora_id': null,
      'tarifa_manual': 0.768,
      'horas_dia': null,
      'ciclos_mes': null,
      'velocidade': null,
      'tipo': 'duplex',
      'volume_total_l': 407.0,
      'ano_compra': 2014,
    });
    expect(c.copy().estimated, isTrue);
    expect(c.copy(appliance: const Appliance(id: 3, category: 'refrigerador', brand: 'X', model: 'Y')).estimated,
        isFalse);
  });

  test('total anual da casa usa o valor anual da API (sem diferenca de arredondamento)', () {
    home.add(
      query('refrigerador'),
      Result.fromJson({...resultJson('refrigerador', 32.1, 24.65, tariff: 0.76802), 'custo_ano': 295.84}),
    );
    expect(home.yearlyCost, 295.84);
  });

  test('tempo em horas e minutos', () {
    final t = TimeControl();
    expect(t.isEmpty, isTrue);
    expect(t.dailyHours, isNull);
    t.define(0.5);
    expect(t.hours.text, '0');
    expect(t.minutes.text, '30');
    expect(t.dailyHours, 0.5);
    t.minutes.text = '75';
    expect(t.valid, isFalse);
    t.hours.text = '1';
    t.minutes.text = '15';
    expect(t.dailyHours, 1.25);
    t.clear();
    expect(t.isEmpty, isTrue);
    expect(duration(0.25), '15 min');
    expect(duration(4.5), '4 h 30 min');
    expect(duration(2), '2 h');
  });

  group('Estimativa, uma pergunta por tela', () {
    Widget estimateScreen() => MaterialApp(
      theme: iampTheme(),
      home: EstimateScreen(loadCategories: testCategories, loadResistive: testResistive),
    );

    Future<void> tap(WidgetTester tester, String text) async {
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    testWidgets('geladeira: tipo, gelo, capacidade, freezer e ano, cada um na sua tela', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(estimateScreen());
      await tester.pumpAndSettle();
      expect(find.text('Que tipo de aparelho é?'), findsOneWidget);
      await tap(tester, 'Eletrodoméstico grande');
      await tap(tester, 'Geladeira ou freezer');
      await tap(tester, 'Geladeira duplex (2 portas)');
      expect(find.text('Ela forma gelo nas paredes?'), findsOneWidget);
      await tap(tester, 'Não forma gelo (frost-free)');

      await tap(tester, 'Continuar');
      expect(find.textContaining('capacidade total em litros'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '407');
      await tap(tester, 'Continuar');
      await tap(tester, 'Não sei'); // litros do freezer
      expect(find.text('Em que ano você comprou?'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1900');
      await tap(tester, 'Continuar');
      expect(find.textContaining('ano de compra entre 1980'), findsOneWidget);
    });

    testWidgets('voltar volta uma pergunta e guarda a resposta', (tester) async {
      tallScreen(tester);
      // como no app: a estimativa e aberta por cima de outra tela
      await tester.pumpWidget(
        MaterialApp(
          theme: iampTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EstimateScreen(loadCategories: testCategories, loadResistive: testResistive),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tap(tester, 'abrir');
      await tap(tester, 'Eletrodoméstico grande');
      await tap(tester, 'Geladeira ou freezer');
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
      tallScreen(tester);
      await tester.pumpWidget(estimateScreen());
      await tester.pumpAndSettle();
      await tap(tester, 'Eletroportátil');
      expect(find.text('Típica: 1500 W'), findsOneWidget);
      await tap(tester, 'Air fryer');
      expect(find.text('Não sei, usar a típica (1500 W)'), findsOneWidget);
      await tap(tester, 'Não sei, usar a típica (1500 W)');
      expect(find.text('Sugerido: 30 min. Troque pelo seu uso real.'), findsOneWidget);
      expect(find.text('Minutos'), findsOneWidget);
    });

    testWidgets('maquina de lavar sem numero pergunta o tipo pelo nome conhecido e o tamanho', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(estimateScreen());
      await tester.pumpAndSettle();
      await tap(tester, 'Eletrodoméstico grande');
      await tap(tester, 'Máquina de lavar');
      expect(find.text('Top Load (automatica)'), findsNothing);
      expect(find.text('Tampa em cima.'), findsOneWidget);
      await tap(tester, 'Automática que abre por cima');
      expect(find.text('Qual é o tamanho?'), findsOneWidget);
      await tap(tester, 'Outro tamanho');
      await tap(tester, 'Continuar');
      expect(find.textContaining('Se não souber, volte e escolha um dos tamanhos'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap(tester, '8 kg');
      expect(find.text('Você consegue ver algum destes no aparelho?'), findsOneWidget);
      expect(find.text('Etiqueta amarela do Inmetro'), findsOneWidget);
      await tap(tester, 'Não consigo ver nenhum');
      expect(find.text('Quantas vezes por mês você lava roupa?'), findsOneWidget);
    });

    testWidgets('televisao antiga usa a potencia escrita nela e as horas viram obrigatorias', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(estimateScreen());
      await tester.pumpAndSettle();
      await tap(tester, 'Eletrodoméstico grande');
      await tap(tester, 'Televisor');
      await tap(tester, '32 polegadas');
      await tap(tester, 'Potência escrita no aparelho');
      expect(find.text('Qual é a potência?'), findsOneWidget);
      await tap(tester, 'Continuar');
      expect(find.text('Digite o número em W, como está escrito. Ex.: 120.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '2000');
      await tap(tester, 'Continuar');
      expect(find.text('Digite o número em W, como está escrito. Ex.: 120.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '120');
      await tap(tester, 'Continuar');
      expect(find.text('Quanto tempo por dia ele fica ligado?'), findsOneWidget);
      expect(find.text('Não sei, usar o valor do Inmetro'), findsNothing);
      await tap(tester, 'Continuar');
      expect(find.text('Digite o tempo de uso por dia.'), findsOneWidget);
    });

    testWidgets('ventilador pergunta a velocidade e as horas; com a potencia, so as horas', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(estimateScreen());
      await tester.pumpAndSettle();
      await tap(tester, 'Eletrodoméstico grande');
      await tap(tester, 'Ventilador de teto');
      await tap(tester, 'Não consigo ver nenhum');
      expect(find.text('Qual é o tamanho?'), findsNothing);
      await tap(tester, 'Média');
      expect(find.text('Quanto tempo por dia ele fica ligado?'), findsOneWidget);
      expect(find.text('Não sei, usar o valor do Inmetro'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap(tester, 'Potência escrita no aparelho');
      await tester.enterText(find.byType(TextField), '130');
      await tap(tester, 'Continuar');
      expect(find.text('Em qual velocidade você costuma usar?'), findsNothing);
      expect(find.text('Quanto tempo por dia ele fica ligado?'), findsOneWidget);
    });

    testWidgets('chuveiro vai direto para a potencia', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(estimateScreen());
      await tester.pumpAndSettle();
      await tap(tester, 'Eletrodoméstico grande');
      await tap(tester, 'Chuveiro elétrico');
      expect(find.text('Qual é a potência?'), findsOneWidget);
      expect(find.text('Não consigo ver nenhum'), findsNothing);
      await tap(tester, 'Continuar');
      expect(find.text('Digite o número em W, como está escrito. Ex.: 5500.'), findsOneWidget);
    });

    testWidgets('ventilador do catalogo pergunta a velocidade e depois as horas', (tester) async {
      tallScreen(tester);
      final c = query('ventilador_de_mesa', id: 3);
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(theme: iampTheme(), home: UsageScreen(query: c)));
        await tester.pumpAndSettle();
        await tap(tester, 'Média');
        expect(find.text('Quanto tempo por dia ele fica ligado?'), findsOneWidget);
        await tap(tester, 'Continuar');
        expect(find.textContaining('Informe quanto tempo por dia'), findsOneWidget);
        await tester.enterText(find.widgetWithText(TextField, 'Horas'), '8');
        await tap(tester, 'Continuar');
      }, apiFake);
      expect(c.speed, 'media');
      expect(c.dailyHours, 8);
    });

    testWidgets('chamada da busca abre a estimativa', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(MaterialApp(theme: iampTheme(), home: const Scaffold(body: EstimateCallToAction())));
      await tester.tap(find.text('Não achou? Estime o gasto'));
      await tester.pumpAndSettle();
      expect(find.text('Estimar o gasto'), findsOneWidget);
    });
  });

  testWidgets('dicas do eco-coach mostram o texto formatado e as fontes', (tester) async {
    tallScreen(tester);
    final r = result('air_fryer', 37.5, 28.8);
    Future<Tips> fake(Result _) async => Tips.fromJson({
      'dicas': 'A air fryer custa R\$ 28,80 por mês.\n\n## Como evitar desperdício\n'
          '- **Não abra** a cesta toda hora [1].\n2. Use o tempo certo [2].',
      'fontes': [
        {'n': 1, 'documento': 'Cartilha', 'orgao': 'Cemig', 'url': 'https://cemig.com.br'},
        {'n': 2, 'documento': 'Dicas', 'orgao': 'Inmetro', 'url': 'https://gov.br'},
      ],
      'aviso': 'Dicas geradas por IA.',
    });
    await tester.pumpWidget(MaterialApp(theme: iampTheme(), home: TipScreen(result: r, searchTips: fake)));
    await tester.pumpAndSettle();
    expect(find.text('Como evitar desperdício'), findsOneWidget);
    expect(find.textContaining('a cesta toda hora [1].', findRichText: true), findsOneWidget);
    expect(find.textContaining('Use o tempo certo [2].', findRichText: true), findsOneWidget);
    expect(find.text('Cemig · Cartilha'), findsOneWidget);
    expect(find.text('Dicas geradas por IA.'), findsOneWidget);
  });

  testWidgets('dicas mostram o erro quando o eco-coach esta fora do ar', (tester) async {
    Future<Tips> outside(Result _) async => throw ApiError('Eco-Coach indisponivel: GEMINI_API_KEY nao configurada');
    await tester.pumpWidget(
      MaterialApp(theme: iampTheme(), home: TipScreen(result: result('air_fryer', 1, 1), searchTips: outside)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('GEMINI_API_KEY'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  group('Eco-Coach', () {
    test('plano: citacoes [n] em amarelo e **negrito** sem os asteriscos', () {
      const base = TextStyle(fontSize: 18);
      final pieces = textPieces('Desligue o **ar** nas saidas [1] e use o timer [2, 3].', base);
      expect(pieces.map((p) => p.text).join(), 'Desligue o ar nas saidas [1] e use o timer [2, 3].');
      final citations = pieces.where((p) => p.text!.startsWith('['));
      expect(citations.map((p) => p.text), ['[1]', '[2, 3]']);
      expect(citations.every((p) => p.style!.color == AppColors.yellow), isTrue);
      expect(citations.every((p) => p.style!.fontSize == 18), isTrue); // citacao do mesmo tamanho do texto
      expect(pieces.firstWhere((p) => p.text == 'ar').style!.fontWeight, FontWeight.bold);
    });

    testWidgets('plano: titulos, listas e paragrafos viram widgets', (tester) async {
      const md = '## Ações recomendadas\n\n1. Banho mais curto [1]\n- Geladeira longe do fogão [2]\nTexto final.';
      await tester.pumpWidget(MaterialApp(theme: iampTheme(), home: const Scaffold(body: PlanText(md))));
      expect(find.text('Ações recomendadas'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.byIcon(Icons.bolt), findsOneWidget); // marcador da lista
      expect(find.textContaining('Texto final.', findRichText: true), findsOneWidget);
    });

    test('casa manda o custo de cada item e guarda as trocas sem repetir', () {
      final item = home.add(query('chuveiro'), result('chuveiro', 41.25, 31.68));
      home.changeQuantity(item, 2);
      expect(home.itemsForEcoCoach().single, {'categoria': 'chuveiro', 'kwh_mes': 82.5, 'custo_mes': 63.36});

      const t1 = EvaluatedSwap(appliance: 'geladeira A', alternative: 'B', monthlySavings: 7, paybackMonths: 300);
      home.registerSwap(t1);
      home.registerSwap(t1); // a mesma troca de novo nao duplica
      expect(home.swaps, hasLength(1));
      for (var i = 0; i < 6; i++) {
        home.registerSwap(EvaluatedSwap(appliance: 'tv $i', alternative: 'x', monthlySavings: 1));
      }
      expect(home.swaps, hasLength(5)); // so as 5 mais recentes
    });

    test('plano guardado some quando a casa muda', () {
      home.add(query('televisor'), result('televisor', 10, 8));
      home.storePlan(EcoCoach.fromJson(examplePlan));
      expect(home.plan!.sources.single.page, 7);
      home.changeResidents(4);
      expect(home.plan, isNull);
    });

    testWidgets('aba Economizar so pede o plano quando a pessoa toca no botao', (tester) async {
      home.add(query('televisor'), result('televisor', 10, 8));
      var requests = 0;
      final api = MockClient((r) async {
        if (r.url.path == '/eco-coach') requests++;
        if (r.url.path == '/categorias') return http.Response('[]', 200, headers: _json);
        return http.Response(jsonEncode(examplePlan), 200, headers: _json);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const IampApp(showWelcome: false));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Economizar'));
        await tester.pumpAndSettle();
        expect(requests, 0);
        await tester.tap(find.text('Montar meu plano'));
        await tester.pumpAndSettle();
      }, () => api);
      expect(requests, 1);
      expect(find.text('Seu plano de economia'), findsOneWidget);
      expect(find.text('Montar outro plano'), findsOneWidget);
    });
  });

  group('Busca por marca com varios tipos', () {
    Appliance ap(int id, String category, int total) => Appliance.fromJson({
      'id': id,
      'categoria': category,
      'marca': 'BRASTEMP',
      'modelo': 'M$id',
      'detalhe': '',
      'total_categoria': total,
    });

    Future<void> display(WidgetTester tester, List<Appliance> itemList) => tester.pumpWidget(
      MaterialApp(
        theme: iampTheme(),
        home: Scaffold(body: SingleChildScrollView(child: ResultsPerType(itemList, onChoose: (_) {}))),
      ),
    );

    testWidgets('cada tipo vira uma secao fechada que abre ao tocar', (tester) async {
      tallScreen(tester);
      await display(tester, [ap(1, 'maquina_de_lavar', 45), ap(2, 'maquina_de_lavar', 45), ap(3, 'refrigerador', 1)]);
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
      await display(tester, [ap(1, 'refrigerador', 1)]);
      expect(find.text('BRASTEMP M1'), findsOneWidget);
    });

    testWidgets('procurar pela marca, sem tipo, busca em todos os tipos', (tester) async {
      tallScreen(tester);
      final requests = <Uri>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(theme: iampTheme(), home: const ModelScreen()));
        await tester.enterText(find.byType(TextField), 'brastemp');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
      }, () => apiFake(requests: requests));
      expect(requests.last.queryParameters.containsKey('categoria'), isFalse);
      expect(find.text('2 aparelhos encontrados'), findsOneWidget);
      expect(find.text('Máquinas de lavar'), findsOneWidget);
      expect(find.text('Geladeiras'), findsOneWidget);
    });
  });

  group('Lista de marcas (etapa 2)', () {
    Future<void> openFridge(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(theme: iampTheme(), home: const ModelScreen(category: 'refrigerador')));
      await tester.pumpAndSettle();
    }

    testWidgets('mostra todas as marcas do tipo e abre os modelos ao tocar na marca', (tester) async {
      tallScreen(tester);
      final requests = <Uri>[];
      await http.runWithClient(() async {
        await openFridge(tester);
        expect(find.text('Ou escolha a marca'), findsOneWidget);
        expect(find.text('2 marcas'), findsOneWidget);
        expect(find.text('BRASTEMP'), findsOneWidget);
        expect(find.text('60 modelos'), findsOneWidget);
        expect(requests.where((u) => u.path == '/modelos'), isEmpty); // so carrega ao abrir

        await tester.tap(find.text('BRASTEMP'));
        await tester.pumpAndSettle();
        expect(requests.last.queryParameters, {'categoria': 'refrigerador', 'marca': 'BRASTEMP', 'limite': '50'});
        await tester.tap(find.text('GELA'));
        await tester.pumpAndSettle();
      }, () => apiFake(requests: requests));
      // segue o calculo normal (geladeira nao pergunta o uso: vai direto para o estado)
      expect(find.text('Em qual estado você mora?'), findsOneWidget);
    });

    testWidgets('marca com mais modelos que o limite avisa para digitar o modelo', (tester) async {
      tester.view.physicalSize = const Size(800, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await http.runWithClient(() async {
        await openFridge(tester);
        await tester.tap(find.text('CONSUL'));
        await tester.pumpAndSettle();
      }, apiFake);
      expect(find.text('CRM1'), findsOneWidget);
      expect(find.textContaining('Mostrando 50 de 60'), findsOneWidget);
    });

    testWidgets('digitar filtra as marcas e "Buscar" continua procurando pelo modelo', (tester) async {
      tallScreen(tester);
      final requests = <Uri>[];
      await http.runWithClient(() async {
        await openFridge(tester);
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
      }, () => apiFake(requests: requests));
      expect(requests.last.path, '/aparelhos');
      expect(find.text('1 aparelho encontrado'), findsOneWidget);
      expect(find.text('Ou escolha a marca'), findsNothing); // o resultado da busca substitui a lista
    });

    testWidgets('sem tipo escolhido nao mostra lista de marcas', (tester) async {
      tallScreen(tester);
      final requests = <Uri>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(theme: iampTheme(), home: const ModelScreen()));
        await tester.pumpAndSettle();
      }, () => apiFake(requests: requests));
      expect(find.text('Ou escolha a marca'), findsNothing);
      expect(requests.where((u) => u.path == '/marcas'), isEmpty);
    });
  });

  testWidgets('carregando por mais de 8 s explica que o servidor esta acordando', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: iampTheme(), home: const Scaffold(body: Loading())));
    expect(find.text('Carregando...'), findsOneWidget);
    expect(find.textContaining('acordando'), findsNothing);
    await tester.pump(Loading.waitBeforeHint + const Duration(milliseconds: 100));
    expect(find.textContaining('O servidor estava em repouso e está acordando'), findsOneWidget);
  });

  testWidgets('aviso de aparelho adicionado some sozinho depois de 5 s', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: iampTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => notifyAdded(ScaffoldMessenger.of(context), 'Foi.'),
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

Future<List<Resistive>> testResistive() async => [
  Resistive.fromJson({'categoria': 'air_fryer', 'nome': 'Air fryer', 'potencia_w': 1500, 'horas_dia': 0.5, 'dias_mes': 15}),
];

Map<String, dynamic> _shape(String field, String unit, String example, double maximum) => {
  'campo': field,
  'nome': field == 'potencia_w' ? 'Potência escrita no aparelho' : 'Etiqueta amarela do Inmetro',
  'rotulo': field == 'potencia_w' ? 'Potência' : 'Consumo de energia',
  'unidade': unit,
  'onde': 'Escrito no aparelho.',
  'dica': null,
  'exemplo': example,
  'maximo': maximum,
};

Map<String, dynamic> _category(
  String c,
  String name, {
  String? measure,
  String? unit,
  List<Map<String, dynamic>> sizes = const [],
  List<Map<String, dynamic>> types = const [],
  bool special = false,
  List<Map<String, dynamic>> shapes = const [],
  bool isRequired = false,
  Map<String, dynamic>? usage,
}) => {
  'categoria': c,
  'nome': name,
  'especial': special,
  'medida': measure,
  'unidade_medida': unit,
  'tamanhos': sizes,
  'tipos': types,
  'formas': shapes,
  'valor_obrigatorio': isRequired,
  'uso': usage ?? {'pergunta': null},
};

Future<List<EstimableCategory>> testCategories() async => [
  for (final j in [
    _category('refrigerador', 'Geladeira ou freezer', special: true),
    _category(
      'maquina_de_lavar',
      'Máquina de lavar',
      measure: 'Capacidade de lavagem (kg)',
      unit: 'kg',
      sizes: [
        {'valor': 8, 'nome': '8 kg'},
      ],
      types: [
        {'valor': 'Top Load (automatica)', 'nome': 'Automática que abre por cima', 'descricao': 'Tampa em cima.'},
      ],
      shapes: [_shape('kwh_ciclo', 'kWh/ciclo', 'Ex.: 0,25', 5)],
      usage: {'pergunta': 'ciclos', 'padrao': 12},
    ),
    _category(
      'televisor',
      'Televisor',
      measure: 'Tamanho da tela (polegadas)',
      unit: 'polegadas',
      sizes: [
        {'valor': 32, 'nome': '32 polegadas'},
      ],
      shapes: [_shape('potencia_w', 'W', 'Ex.: 120', 1500), _shape('kwh_mes', 'kWh/mês', 'Ex.: 9,9', 300)],
      usage: {'pergunta': 'horas', 'padrao': null, 'opcional': true},
    ),
    _category(
      'ventilador_de_teto',
      'Ventilador de teto',
      shapes: [_shape('potencia_w', 'W', 'Ex.: 130', 500)],
      usage: {
        'pergunta': 'velocidade',
        'opcoes': ['baixa', 'media', 'alta'],
        'padrao': 'media',
        'perguntar_horas': true,
      },
    ),
    _category(
      'chuveiro',
      'Chuveiro elétrico',
      isRequired: true,
      shapes: [_shape('potencia_w', 'W', 'Ex.: 5500', 12000)],
      usage: {'pergunta': 'horas', 'padrao': null},
    ),
  ])
    EstimableCategory.fromJson(j),
];

const examplePlan = {
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
