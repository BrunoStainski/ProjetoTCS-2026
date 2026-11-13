// Conta: criar (nome, e-mail, senha e o aceite do Termo de Consentimento, telas/termo.dart) ou entrar (e-mail e senha).
// Opcional: o app inteiro funciona sem conta ("Continuar sem cadastro" avisa que nada fica salvo). Com conta, as
// casas ficam salvas na nuvem e o login fica guardado no celular (conta.dart).
// Quem ja entrou ve os dados, corrige o nome/e-mail, sai da conta ou apaga a conta (com confirmacao).

import 'package:flutter/material.dart';

import '../api.dart';
import '../conta.dart';
import '../idioma.dart';
import '../tema.dart';
import 'comum.dart';
import 'termo.dart';

/// Resumo do Termo de Consentimento, mostrado junto do aceite (o termo inteiro abre em ConsentTermScreen).
String privacyNotice() => tr(
  'O Iamp guarda no servidor: seu nome, seu e-mail, a senha protegida (embaralhada, ninguém consegue ler) '
      'e as suas casas com os aparelhos calculados. Serve só para você ver as suas casas em qualquer celular.\n\n'
      'Não pedimos endereço nem a conta de luz, não vendemos e não compartilhamos os seus dados. O assistente de '
      'IA (Gemini, do Google) recebe só os números de consumo, nunca o seu nome ou e-mail. O servidor fica nos '
      'Estados Unidos (Render e Neon).\n\n'
      'Você pode corrigir os dados ou apagar a conta, com tudo o que ela guarda, quando quiser, em "Minha conta". '
      'O acesso fica guardado neste celular por até 30 dias. Projeto acadêmico do bootcamp TCS 2026.',
  'Iamp stores on its server: your name, your email, your protected password (scrambled, nobody can read it) '
      'and your homes with the calculated appliances. It is only used so you can see your homes on any phone.\n\n'
      'We do not ask for your address or electricity bill, and we do not sell or share your data. The AI '
      'assistant (Google Gemini) receives only consumption numbers, never your name or email. The server is in '
      'the United States (Render and Neon).\n\n'
      'You can correct your data or delete your account, with everything it stores, at any time in "My account". '
      'Access stays saved on this phone for up to 30 days. Academic project of the TCS 2026 bootcamp.',
);

class SignUpScreen extends StatefulWidget {
  /// true = abre em "Entrar" (quem ja tem conta).
  final bool logIn;

  const SignUpScreen({super.key, this.logIn = false});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  late bool _logIn = widget.logIn;
  late final _name = TextEditingController(text: account.value?.name ?? '');
  late final _email = TextEditingController(text: account.value?.email ?? '');
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _accepted = false;
  bool _busy = false;
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _acceptError;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _done(String text) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(persist: false, content: Text(text)));
  }

  /// Valida o que da para validar aqui; o resto (e-mail repetido, senha errada) vem da API.
  bool _valid({required bool registered}) {
    final creating = !registered && !_logIn;
    setState(() {
      _nameError = (creating || registered) && _name.text.trim().length < 2
          ? tr('Digite o seu nome.', 'Enter your name.')
          : null;
      _emailError = validEmail(_email.text)
          ? null
          : tr('Digite um e-mail válido, como nome@exemplo.com.', 'Enter a valid email, like name@example.com.');
      _passwordError = registered
          ? null
          : _logIn
          ? (_password.text.isEmpty ? tr('Digite a sua senha.', 'Enter your password.') : null)
          : (_password.text.length < minPassword
                ? tr(
                    'A senha precisa ter pelo menos $minPassword letras ou números.',
                    'The password needs at least $minPassword letters or numbers.',
                  )
                : null);
      _acceptError = creating && !_accepted
          ? tr('Para criar a conta, aceite o Termo de Consentimento.', 'To create an account, accept the Consent Term.')
          : null;
      _error = null;
    });
    return _nameError == null && _emailError == null && _passwordError == null && _acceptError == null;
  }

  Future<void> _run(Future<void> Function() action, String doneText) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _done(doneText);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit() {
    final registered = account.value != null;
    if (_busy || !_valid(registered: registered)) return;
    if (registered) {
      final a = account.value!;
      _run(
        () => updateAccount(
          name: _name.text.trim() == a.name ? null : _name.text,
          email: _email.text.trim().toLowerCase() == a.email ? null : _email.text,
        ),
        tr('Dados atualizados.', 'Details updated.'),
      );
    } else if (_logIn) {
      _run(() => logIn(_email.text, _password.text), tr('Você entrou na sua conta.', 'You are logged in.'));
    } else {
      _run(
        () => signUp(_name.text, _email.text, _password.text),
        tr('Conta criada. Suas casas ficam salvas.', 'Account created. Your homes are saved.'),
      );
    }
  }

  /// Segue sem conta, depois de avisar que as casas nao ficam salvas.
  Future<void> _continueWithout() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Continuar sem cadastro?', 'Continue without an account?')),
        content: Text(withoutAccountNotice()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Voltar', 'Go back'))),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Continuar sem cadastro', 'Continue without an account')),
          ),
        ],
      ),
    );
    if (sure == true && mounted) Navigator.pop(context);
  }

  Future<void> _logOut() async {
    setState(() => _busy = true);
    await logOut();
    if (!mounted) return;
    _done(
      tr(
        'Você saiu da conta. Suas casas continuam salvas nela.',
        'You logged out. Your homes stay saved in your account.',
      ),
    );
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Apagar a conta?', 'Delete your account?')),
        content: Text(
          tr(
            'Vamos apagar do servidor o seu nome, o seu e-mail e todas as suas casas. Não dá para desfazer.',
            'We will delete your name, your email and all your homes from the server. This cannot be undone.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancelar', 'Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Apagar tudo', 'Delete everything')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    _run(deleteAccount, tr('Conta apagada, com todas as casas.', 'Account deleted, with all homes.'));
  }

  @override
  Widget build(BuildContext context) {
    final registered = account.value != null;
    final creating = !registered && !_logIn;
    return AppPage(
      title: registered
          ? tr('Minha conta', 'My account')
          : (_logIn ? tr('Entrar', 'Log in') : tr('Criar conta', 'Sign up')),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(
              registered ? tr('Salvar', 'Save') : (_logIn ? tr('Entrar', 'Log in') : tr('Criar conta', 'Sign up')),
            ),
          ),
          if (registered) ...[
            const SizedBox(height: Spacing.p),
            OutlinedButton.icon(
              onPressed: _busy ? null : _logOut,
              icon: const Icon(Icons.logout),
              label: Text(tr('Sair da conta', 'Log out')),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              label: Text(tr('Apagar minha conta', 'Delete my account')),
            ),
          ] else
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _logIn = !_logIn;
                      _error = null;
                    }),
              child: Text(
                _logIn
                    ? tr('Não tenho conta: criar uma', "I don't have an account: sign up")
                    : tr('Já tenho conta: entrar', 'I have an account: log in'),
              ),
            ),
        ],
      ),
      child: AutofillGroup(
        child: ListView(
          children: [
            QuestionHeader(
              registered
                  ? tr('Seus dados', 'Your details')
                  : (_logIn
                        ? tr('Entre na sua conta', 'Log in to your account')
                        : tr('Como podemos chamar você?', 'What should we call you?')),
              help: registered
                  ? tr('Suas casas estão salvas nesta conta.', 'Your homes are saved in this account.')
                  : tr(
                      'A conta é opcional. Com ela, suas casas ficam salvas e aparecem em qualquer celular.',
                      'An account is optional. With it, your homes are saved and show up on any phone.',
                    ),
            ),
            if (!registered) ...[
              _WithoutAccount(onTap: _busy ? null : _continueWithout),
              const SizedBox(height: Spacing.g),
            ],
            if (creating || registered) ...[
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: InputDecoration(labelText: tr('Nome', 'Name'), errorText: _nameError),
              ),
              const SizedBox(height: Spacing.m),
            ],
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: registered ? TextInputAction.done : TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              onSubmitted: registered ? (_) => _submit() : null,
              decoration: InputDecoration(
                labelText: tr('E-mail', 'Email'),
                hintText: tr('nome@exemplo.com', 'name@example.com'),
                errorText: _emailError,
              ),
            ),
            if (!registered) ...[
              const SizedBox(height: Spacing.m),
              TextField(
                controller: _password,
                obscureText: !_showPassword,
                textInputAction: TextInputAction.done,
                autofillHints: [_logIn ? AutofillHints.password : AutofillHints.newPassword],
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: tr('Senha', 'Password'),
                  helperText: creating
                      ? tr('Pelo menos $minPassword letras ou números.', 'At least $minPassword letters or numbers.')
                      : null,
                  errorText: _passwordError,
                  suffixIcon: IconButton(
                    tooltip: _showPassword
                        ? tr('Esconder a senha', 'Hide password')
                        : tr('Mostrar a senha', 'Show password'),
                    icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
            ],
            if (creating) ...[
              const SizedBox(height: Spacing.g),
              _PrivacyNotice(
                accepted: _accepted,
                error: _acceptError,
                onChanged: (v) => setState(() {
                  _accepted = v;
                  _acceptError = null;
                }),
              ),
            ],
            if (registered) ...[
              const SizedBox(height: Spacing.g),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => openConsentTerm(context),
                  icon: const Icon(Icons.description_outlined),
                  label: Text(tr('Ler o Termo de Consentimento', 'Read the Consent Term')),
                ),
              ),
            ],
            if (_busy) ...[const SizedBox(height: Spacing.g), const Center(child: CircularProgressIndicator())],
            if (_error != null) ...[const SizedBox(height: Spacing.g), ErrorMessage(_error!)],
          ],
        ),
      ),
    );
  }
}

/// Termo de Consentimento antes de criar a conta: resumo, botao para o termo completo e o aceite (nao vem marcado).
class _PrivacyNotice extends StatelessWidget {
  final bool accepted;
  final String? error;
  final ValueChanged<bool> onChanged;

  const _PrivacyNotice({required this.accepted, required this.error, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    // Material (e nao Container com cor): o toque no CheckboxListTile precisa aparecer no cartao
    return Material(
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius),
        side: BorderSide(color: error == null ? t.border : t.alert),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, color: t.highlight),
                const SizedBox(width: Spacing.pm),
                Expanded(child: Text(tr('Termo de Consentimento', 'Consent Term'), style: t.strong)),
              ],
            ),
            const SizedBox(height: Spacing.p),
            Text(privacyNotice(), style: t.secondary),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openConsentTerm(context),
                icon: const Icon(Icons.description_outlined),
                label: Text(tr('Ler o termo completo', 'Read the full term')),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: accepted,
              onChanged: (v) => onChanged(v ?? false),
              title: Text(tr('Li e concordo com o Termo de Consentimento', 'I have read and agree to the Consent Term')),
            ),
            if (error != null) Text(error!, style: t.secondary.copyWith(color: t.alert)),
          ],
        ),
      ),
    );
  }
}

/// Atalho para as telas: abre a conta (entrar/criar ou "Minha conta").
void openAccount(BuildContext context, {bool logIn = false}) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => SignUpScreen(logIn: logIn)));

void openConsentTerm(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ConsentTermScreen()));

/// O que acontece sem conta (no "Continuar sem cadastro" e nas boas-vindas).
String withoutAccountNotice() => tr(
  'Sem cadastro, as suas casas e os seus cálculos ficam só neste celular e não são salvos: eles são apagados '
      'quando você fecha o app. Você pode criar a conta depois, a qualquer momento, e levar a casa junto.',
  'Without an account, your homes and calculations stay only on this phone and are not saved: they are erased '
      'when you close the app. You can create an account later, at any time, and take the home with you.',
);

/// Atalho para quem nao quer conta: avisa que nada fica salvo e segue para o app.
class _WithoutAccount extends StatelessWidget {
  final VoidCallback? onTap;

  const _WithoutAccount({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return Material(
      color: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radius), side: BorderSide(color: t.border)),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: t.highlight),
                const SizedBox(width: Spacing.pm),
                Expanded(
                  child: Text(
                    tr(
                      'Prefere não criar conta? Dá para usar o Iamp sem cadastro, mas nada fica salvo.',
                      'Rather not create an account? You can use Iamp without one, but nothing is saved.',
                    ),
                    style: t.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.p),
            OutlinedButton(onPressed: onTap, child: Text(tr('Continuar sem cadastro', 'Continue without an account'))),
          ],
        ),
      ),
    );
  }
}
