// Termo de Consentimento do cadastro (LGPD). Aberto pelo cadastro (antes de aceitar) e por "Minha conta".
// Segue o que a LGPD pede para o consentimento valer (art. 8 e 9): quem trata os dados, quais dados, para que,
// com quem sao compartilhados, onde ficam (transferencia internacional com consentimento especifico, art. 33),
// por quanto tempo, como exercer os direitos (art. 18) e como revogar. O aceite nao vem marcado.
// Mudou o texto? Troque tambem contas.PRIVACY_VERSION no servidor (a conta guarda a versao aceita).

import 'package:flutter/material.dart';

import '../idioma.dart';
import '../tema.dart';
import 'comum.dart';

/// (titulo, texto) de cada parte do termo, no idioma do app.
List<(String, String)> consentTerm() => [
  (
    tr('1. Quem cuida dos seus dados', '1. Who looks after your data'),
    tr(
      'A equipe do projeto Iamp, um projeto acadêmico do bootcamp TCS 2026, é a responsável pelos dados deste '
          'cadastro (controladora, nos termos da LGPD, Lei 13.709/2018).',
      'The Iamp project team, an academic project of the TCS 2026 bootcamp, is responsible for the data in this '
          'account (the controller, under Brazil\'s LGPD, Law 13,709/2018).',
    ),
  ),
  (
    tr('2. Quais dados guardamos', '2. What data we keep'),
    tr(
      'Seu nome, seu e-mail, a sua senha protegida (guardamos só um código embaralhado; ninguém consegue ler a '
          'senha), as casas que você salvar (nome, número de moradores, aparelhos, distribuidora ou tarifa e os '
          'valores calculados) e a data em que você aceitou este termo. Não pedimos endereço, CPF, telefone, '
          'conta de luz nem localização.',
      'Your name, your email, your protected password (we keep only a scrambled code; nobody can read the '
          'password), the homes you save (name, number of residents, appliances, utility or rate and the '
          'calculated values) and the date you accepted this term. We do not ask for your address, ID number, '
          'phone, electricity bill or location.',
    ),
  ),
  (
    tr('3. Para que usamos', '3. What we use it for'),
    tr(
      'Só para criar e proteger a sua conta, guardar as suas casas para você ver em qualquer celular e manter '
          'você conectado neste aparelho. Não usamos para propaganda, não vendemos e não passamos os seus dados '
          'para ninguém.',
      'Only to create and protect your account, keep your homes so you can see them on any phone and keep you '
          'signed in on this device. We do not use it for advertising, and we do not sell or share your data.',
    ),
  ),
  (
    tr('4. Quem mais recebe dados', '4. Who else receives data'),
    tr(
      'O servidor do Iamp roda no Render e o banco de dados fica no Neon: os dois só guardam e processam os '
          'dados para o app funcionar. O assistente de IA (Gemini, do Google) recebe só os números de consumo e o '
          'tipo de cada aparelho, nunca o seu nome ou e-mail.',
      'The Iamp server runs on Render and the database is on Neon: both only store and process the data so the '
          'app works. The AI assistant (Google Gemini) receives only consumption numbers and the type of each '
          'appliance, never your name or email.',
    ),
  ),
  (
    tr('5. Dados fora do Brasil', '5. Data outside Brazil'),
    tr(
      'Os servidores do Render e do Neon ficam nos Estados Unidos (Ohio). Ao aceitar este termo, você concorda, '
          'de forma específica, com a transferência dos seus dados para lá (LGPD, art. 33).',
      'The Render and Neon servers are in the United States (Ohio). By accepting this term, you specifically '
          'agree to the transfer of your data there (LGPD, art. 33).',
    ),
  ),
  (
    tr('6. Por quanto tempo', '6. For how long'),
    tr(
      'Até você apagar a conta. O acesso fica guardado neste celular, protegido, por até 30 dias ou até você '
          'tocar em "Sair da conta".',
      'Until you delete the account. Access stays saved on this phone, protected, for up to 30 days or until you '
          'tap "Log out".',
    ),
  ),
  (
    tr('7. Seus direitos', '7. Your rights'),
    tr(
      'Em "Minha conta" você vê e corrige os seus dados e apaga a conta quando quiser. Apagar a conta tira o seu '
          'consentimento e apaga do servidor tudo o que ela guarda, inclusive as casas. Você também pode pedir '
          'informações sobre os seus dados à equipe do projeto.',
      'In "My account" you can see and correct your data and delete the account at any time. Deleting the '
          'account withdraws your consent and erases everything it stores from the server, including the homes. '
          'You can also ask the project team about your data.',
    ),
  ),
  (
    tr('8. Segurança', '8. Security'),
    tr(
      'A senha é guardada só como código embaralhado, a conexão com o servidor é protegida (HTTPS) e o acesso '
          'guardado no celular fica cifrado. Nenhum sistema é totalmente seguro, mas cuidamos para que só você '
          'acesse a sua conta.',
      'The password is stored only as a scrambled code, the connection to the server is protected (HTTPS) and '
          'the access saved on the phone is encrypted. No system is completely secure, but we make sure only you '
          'can access your account.',
    ),
  ),
  (
    tr(
      '9. Sem cadastro também funciona',
      '9. It also works without an account',
    ),
    tr(
      'O cadastro é opcional. Sem ele, nada é guardado no servidor: as suas casas ficam só neste celular e são '
          'apagadas quando você fecha o app.',
      'An account is optional. Without it, nothing is stored on the server: your homes stay only on this phone '
          'and are erased when you close the app.',
    ),
  ),
  (
    tr('10. Limitação do projeto', '10. Project limitation'),
    tr(
      'Por ser um projeto acadêmico, ainda não há recuperação de senha por e-mail.',
      'As an academic project, there is no password recovery by email yet.',
    ),
  ),
];

class ConsentTermScreen extends StatelessWidget {
  const ConsentTermScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    return AppPage(
      title: tr('Termo de Consentimento', 'Consent Term'),
      child: ListView(
        children: [
          QuestionHeader(
            tr(
              'Como o Iamp cuida dos seus dados',
              'How Iamp looks after your data',
            ),
            help: tr(
              'Leia antes de criar a conta. Você só cria a conta se concordar.',
              'Read before creating the account. You only create it if you agree.',
            ),
          ),
          for (final (title, text) in consentTerm()) ...[
            Semantics(header: true, child: Text(title, style: t.strong)),
            const SizedBox(height: Spacing.p),
            Text(text, style: t.body),
            const SizedBox(height: Spacing.g),
          ],
        ],
      ),
    );
  }
}
