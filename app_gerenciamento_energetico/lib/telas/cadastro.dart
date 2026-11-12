// Cadastro: nome e e-mail, so o minimo. Opcional: o app inteiro funciona sem ele.
// Os dados ficam so neste aparelho (conta.dart) e a tela diz isso antes de a pessoa preencher.
// Quem ja se cadastrou pode corrigir os dados ou apagar o cadastro aqui mesmo.

import 'package:flutter/material.dart';

import '../conta.dart';
import '../idioma.dart';
import '../tema.dart';
import 'comum.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  late final _name = TextEditingController(text: account.value?.name ?? '');
  late final _email = TextEditingController(text: account.value?.email ?? '');
  String? _nameError;
  String? _emailError;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final email = _email.text.trim();
    setState(() {
      _nameError = name.length < 2 ? tr('Digite o seu nome.', 'Enter your name.') : null;
      _emailError = validEmail(email)
          ? null
          : tr('Digite um e-mail válido, como nome@exemplo.com.', 'Enter a valid email, like name@example.com.');
    });
    if (_nameError != null || _emailError != null) return;
    final isNew = account.value == null;
    account.value = Account(name, email);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          content: Text(isNew ? tr('Cadastro criado.', 'Account created.') : tr('Cadastro atualizado.', 'Account updated.')),
        ),
      );
  }

  void _delete() {
    account.value = null;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(persist: false, content: Text(tr('Cadastro apagado.', 'Account deleted.'))));
  }

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final registered = account.value != null;
    return AppPage(
      title: registered ? tr('Meu cadastro', 'My account') : tr('Criar cadastro', 'Sign up'),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: _save,
            child: Text(registered ? tr('Salvar', 'Save') : tr('Criar cadastro', 'Sign up')),
          ),
          if (registered) ...[
            const SizedBox(height: Spacing.p),
            TextButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              label: Text(tr('Apagar meu cadastro', 'Delete my account')),
            ),
          ],
        ],
      ),
      child: ListView(
        children: [
          QuestionHeader(
            tr('Como podemos chamar você?', 'What should we call you?'),
            help: tr(
              'O cadastro é opcional: você pode usar o Iamp sem ele.',
              'Signing up is optional: you can use Iamp without it.',
            ),
          ),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            decoration: InputDecoration(labelText: tr('Nome', 'Name'), errorText: _nameError),
          ),
          const SizedBox(height: Spacing.m),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: tr('E-mail', 'Email'),
              hintText: tr('nome@exemplo.com', 'name@example.com'),
              errorText: _emailError,
            ),
          ),
          const SizedBox(height: Spacing.g),
          // aviso de privacidade antes de preencher: onde os dados ficam e por quanto tempo
          Container(
            padding: const EdgeInsets.all(Spacing.m),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.radius),
              border: Border.all(color: t.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, color: t.highlight),
                const SizedBox(width: Spacing.pm),
                Expanded(
                  child: Text(
                    tr(
                      'Seu nome e seu e-mail ficam só neste aparelho. Eles não são enviados para a internet '
                          'e são apagados quando você fecha o app.',
                      'Your name and email stay only on this device. They are not sent over the internet '
                          'and are deleted when you close the app.',
                    ),
                    style: t.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
