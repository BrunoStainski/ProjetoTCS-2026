// Conta na nuvem: cadastro com senha, entrar, sair, corrigir e apagar (rotas /contas, /login, /conta).
// Com a conta aberta, as casas (casa.dart) sao gravadas no servidor a cada mudanca e voltam em qualquer
// celular. Sem conta, o app funciona igual, com as casas so na memoria.
// LGPD: o cadastro so e criado com o aviso de privacidade aceito (o servidor grava a data), a senha vira
// hash no servidor, a pessoa pode corrigir os dados e apagar tudo. O token fica so na memoria: fechar o
// app sai da conta (o celular nao guarda nada).

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'casa.dart';

class Account {
  final String name;
  final String email;

  const Account(this.name, this.email);

  Account.fromJson(Map<String, dynamic> j) : name = j['nome'], email = j['email'];

  /// Primeiro nome, para a saudacao ("Olá, Maria").
  String get firstName => name.trim().split(RegExp(r'\s+')).first;
}

/// Conta aberta (null = a pessoa esta usando o app sem conta, o que continua valendo).
final account = ValueNotifier<Account?>(null);

enum SyncState { saving, saved, failed }

/// Situacao da gravacao das casas na nuvem (a tela de casas mostra "Salvo" ou "Não consegui salvar").
final syncState = ValueNotifier<SyncState>(SyncState.saved);

final _emailFormat = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool validEmail(String text) => _emailFormat.hasMatch(text.trim());

const minPassword = 8;

/// Espera um pouco depois da ultima mudanca antes de gravar (tocar varias vezes no "+" faz uma gravacao so).
const saveDelay = Duration(milliseconds: 600);

/// Versao de cada casa que ja esta no servidor.
final _savedVersion = Expando<int>();
Timer? _timer;
bool _saving = false;
bool _listening = false;

void _start(Map<String, dynamic> session) {
  Api.token = session['token'];
  account.value = Account.fromJson(session['conta']);
  if (!_listening) {
    homes.addListener(_scheduleSave);
    _listening = true;
  }
}

/// Cria a conta e leva para ela as casas que a pessoa ja montou no app.
Future<void> signUp(String name, String email, String password) async {
  _start(await Api.signUp(name.trim(), email.trim(), password));
  for (final h in homes.list) {
    h.cloudId = null;
  }
  await saveNow();
}

/// Entra na conta: traz as casas da nuvem e junta as que a pessoa montou antes de entrar (sem perder nada).
Future<void> logIn(String email, String password) async {
  final session = await Api.logIn(email.trim(), password);
  _start(session);
  final List<Home> cloud;
  try {
    cloud = [for (final j in await Api.savedHomes()) Home.fromCloud(j)];
  } catch (_) {
    // entrou, mas nao trouxe as casas (internet caiu no meio): sai da conta sem apagar as casas do celular
    _endSession();
    rethrow;
  }
  for (final h in cloud) {
    _savedVersion[h] = h.version;
  }
  final local = [
    for (final h in homes.list)
      if (!h.isEmpty) h..cloudId = null,
  ];
  final open = local.contains(home) ? home : null;
  final all = [...cloud, ...local];
  homes.replaceAll(all.isEmpty ? [Home()] : all, open: open);
  await saveNow();
}

/// Sai da conta neste aparelho. As casas continuam na nuvem; o app volta para uma casa vazia.
Future<void> logOut() async {
  _timer?.cancel();
  try {
    await Api.logOut();
  } catch (_) {} // sem internet: o token some daqui de qualquer jeito
  _endLocal();
}

/// Corrige nome e/ou e-mail no servidor.
Future<void> updateAccount({String? name, String? email}) async {
  account.value = Account.fromJson(await Api.updateAccount(name: name?.trim(), email: email?.trim()));
}

/// Apaga a conta e tudo o que ela guarda no servidor (casas e aparelhos). Nao tem volta.
Future<void> deleteAccount() async {
  _timer?.cancel();
  await Api.deleteAccount();
  _endLocal();
}

/// Apaga uma casa (da nuvem tambem, se a pessoa estiver na conta).
Future<void> removeHome(Home h) async {
  final id = h.cloudId;
  if (account.value != null && id != null) await Api.deleteHome(id);
  homes.remove(h);
}

/// Sai da conta e volta para uma casa vazia (sair, apagar a conta, sessao vencida).
void _endLocal() {
  _endSession();
  homes.reset();
}

/// Sai da conta e deixa as casas do celular como estao.
void _endSession() {
  _timer?.cancel();
  Api.token = null;
  account.value = null;
  syncState.value = SyncState.saved;
}

bool _pending(Home h) => h.cloudId == null || _savedVersion[h] != h.version;

void _scheduleSave() {
  if (account.value == null || !homes.list.any(_pending)) return;
  _timer?.cancel();
  _timer = Timer(saveDelay, saveNow);
}

/// Grava agora tudo o que mudou: cria no servidor as casas novas e manda a casa inteira das que mudaram.
Future<void> saveNow() async {
  _timer?.cancel();
  if (account.value == null || _saving) return;
  _saving = true;
  syncState.value = SyncState.saving;
  try {
    for (final h in homes.list.where(_pending).toList()) {
      final version = h.version;
      h.cloudId ??= (await Api.createHome(h.name, h.residents))['id'] as int;
      await Api.saveHome(h.cloudId!, h.toCloud());
      _savedVersion[h] = version;
    }
    syncState.value = SyncState.saved;
  } on SessionExpired {
    _endLocal(); // conta apagada em outro aparelho ou sessao vencida
  } on ApiError {
    syncState.value = SyncState.failed; // tenta de novo na proxima mudanca (ou no "Tentar de novo")
  } finally {
    _saving = false;
  }
  // mudou alguma coisa enquanto gravava: grava de novo
  if (account.value != null && syncState.value == SyncState.saved && homes.list.any(_pending)) _scheduleSave();
}
