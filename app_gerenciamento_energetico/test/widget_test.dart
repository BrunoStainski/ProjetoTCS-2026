import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_gerenciamento_energetico/api.dart';
import 'package:app_gerenciamento_energetico/casa.dart';
import 'package:app_gerenciamento_energetico/main.dart';
import 'package:app_gerenciamento_energetico/tema.dart';

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
}
