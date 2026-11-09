import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_gerenciamento_energetico/api.dart';
import 'package:app_gerenciamento_energetico/casa.dart';
import 'package:app_gerenciamento_energetico/main.dart';
import 'package:app_gerenciamento_energetico/tema.dart';
import 'package:app_gerenciamento_energetico/telas/busca.dart';
import 'package:app_gerenciamento_energetico/telas/comum.dart';
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
