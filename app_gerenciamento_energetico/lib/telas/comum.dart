import 'package:flutter/material.dart';

import '../api.dart';

/// O que o usuario ja escolheu ao longo das telas.
class Consulta {
  final Aparelho aparelho;
  double? horasDia;
  double? ciclosMes;
  String? velocidade;

  Consulta(this.aparelho);
}

/// Largura maxima do conteudo, para o app ficar bom no navegador e no Windows.
class Pagina extends StatelessWidget {
  final String titulo;
  final Widget filho;
  final int passo;

  const Pagina({super.key, required this.titulo, required this.filho, required this.passo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(titulo),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: passo / 4),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(padding: const EdgeInsets.all(16), child: filho),
        ),
      ),
    );
  }
}

class MensagemErro extends StatelessWidget {
  final String mensagem;
  final VoidCallback? tentarDeNovo;

  const MensagemErro(this.mensagem, {super.key, this.tentarDeNovo});

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Card(
      color: cores.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(mensagem, style: TextStyle(color: cores.onErrorContainer)),
            if (tentarDeNovo != null)
              TextButton(onPressed: tentarDeNovo, child: const Text('Tentar de novo')),
          ],
        ),
      ),
    );
  }
}
