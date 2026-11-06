import 'package:flutter_test/flutter_test.dart';

import 'package:app_gerenciamento_energetico/api.dart';
import 'package:app_gerenciamento_energetico/main.dart';

void main() {
  testWidgets('abre na tela de busca', (tester) async {
    await tester.pumpWidget(const IampApp());
    expect(find.text('Marca e/ou modelo'), findsOneWidget);
  });

  test('formata valores em reais', () {
    expect(reais(31.68), 'R\$ 31,68');
    expect(reais(1234.5), 'R\$ 1.234,50');
    expect(numero(41.25), '41,25');
    expect(lerNumero('0,25'), 0.25);
  });
}
