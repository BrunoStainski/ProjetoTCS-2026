// Boas-vindas: primeira tela ao abrir o app (e pelo menu, em "Início").
// So a marca (icone grande com o nome ao lado), o botao principal e o cadastro (opcional). Quem se cadastrou ve
// "Olá, <nome>". O botao principal depende de a pessoa ja ter aparelhos (UX: a casa e o centro do app):
// - primeira vez (nenhuma casa com aparelho): "Comece a economizar" -> aba Calcular, etapa 1;
// - ja tem aparelhos (voltou com o login guardado, entrou na conta ou montou a casa): "Ver minha casa" -> aba
//   Minha casa, com o total da conta. Antes ia sempre para o calculo e parecia que a pessoa comecava do zero.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../casa.dart';
import '../conta.dart';
import '../idioma.dart';
import '../navegacao.dart';
import '../tema.dart';
import 'cadastro.dart';
import 'comum.dart';

class WelcomeScreen extends StatelessWidget {
  /// Aberta junto com o app: o voltar do Android fecha o app (em vez de mostrar as abas por baixo).
  final bool onOpen;

  const WelcomeScreen({super.key, this.onOpen = false});

  /// Alguma casa ja tem aparelho: nao e a primeira vez da pessoa.
  static bool get _hasAppliances => homes.list.any((h) => !h.isEmpty);

  void _start(BuildContext context) {
    if (_hasAppliances) {
      goTo(AppTab.home, restart: true);
    } else {
      goTo(AppTab.calculate, restart: true);
    }
    Navigator.pop(context); // as abas ja estao embaixo desta tela
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return PopScope(
      canPop: !onOpen,
      onPopInvokedWithResult: (left, _) {
        if (!left) SystemNavigator.pop();
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.g),
                child: ValueListenableBuilder<Account?>(
                  valueListenable: account,
                  builder: (context, registered, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const IampBrand(size: 120, nameSize: 56),
                      if (registered != null) ...[
                        const SizedBox(height: Spacing.g),
                        Text(
                          tr(
                            'Olá, ${registered.firstName}!',
                            'Hello, ${registered.firstName}!',
                          ),
                          style: t.question,
                          textAlign: TextAlign.center,
                        ),
                      ] else ...[
                        // sem conta, o app funciona igual, mas a pessoa precisa saber que nada fica salvo
                        const SizedBox(height: Spacing.g),
                        Text(
                          tr(
                            'Sem conta, as suas casas não ficam salvas ao fechar o app.',
                            'Without an account, your homes are not saved when you close the app.',
                          ),
                          style: t.secondary,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // acao principal embaixo, na zona do polegar (mesmo padrao do rodape das outras telas)
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: t.border)),
          ),
          child: SafeArea(
            top: false,
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: t.maxWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.m,
                    Spacing.pm,
                    Spacing.m,
                    Spacing.m,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // muda sozinho quando as casas chegam da nuvem (login guardado ou entrar na conta)
                      ListenableBuilder(
                        listenable: homes,
                        builder: (context, _) => FilledButton.icon(
                          onPressed: () => _start(context),
                          icon: Icon(_hasAppliances ? Icons.home : Icons.bolt),
                          label: Text(
                            _hasAppliances ? tr('Ver minha casa', 'See my home') : tr('Comece a economizar', 'Start saving'),
                          ),
                        ),
                      ),
                      const SizedBox(height: Spacing.p),
                      // conta opcional (salva as casas na nuvem): quem nao quiser segue direto pelo botao de cima
                      ValueListenableBuilder<Account?>(
                        valueListenable: account,
                        builder: (context, registered, _) =>
                            OutlinedButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SignUpScreen(),
                                ),
                              ),
                              icon: Icon(
                                registered == null
                                    ? Icons.person_add_alt
                                    : Icons.person_outline,
                              ),
                              label: Text(
                                registered == null
                                    ? tr(
                                        'Entrar ou criar conta',
                                        'Log in or sign up',
                                      )
                                    : tr('Minha conta', 'My account'),
                              ),
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
