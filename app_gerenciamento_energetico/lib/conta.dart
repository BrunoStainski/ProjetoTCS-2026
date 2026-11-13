// Conta na nuvem: cadastro com senha, entrar, sair, corrigir e apagar (rotas /contas, /login, /conta).
// Com a conta aberta, as casas (casa.dart) sao gravadas no servidor a cada mudanca e voltam em qualquer
// celular. Sem conta, o app funciona igual, com as casas so na memoria.
// LGPD: o cadastro so e criado com o Termo de Consentimento aceito (o servidor grava a data e a versao), a senha
// vira hash no servidor, a pessoa pode corrigir os dados e apagar tudo.
// Login guardado: o token fica cifrado no celular (flutter_secure_storage, Android Keystore; o manifest desliga o
// backup automatico, que quebrava a chave ao restaurar) por ate 30 dias. Ao abrir o app, restoreSession() confere
// o token na API e traz as casas. Sair, apagar a conta ou sessao vencida apagam o token do celular.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';
import 'casa.dart';

class Account {
  final String name;
  final String email;

  const Account(this.name, this.email);

  Account.fromJson(Map<String, dynamic> j)
    : name = j['nome'],
      email = j['email'];

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

const _tokenKey = 'iamp_token';
const _storage = FlutterSecureStorage();

/// Guarda o token no celular (cifrado). Se o armazenamento falhar, segue so na memoria (entra de novo ao reabrir).
Future<void> _keepToken(String token) async {
  try {
    await _storage.write(key: _tokenKey, value: token);
  } catch (_) {}
}

Future<void> _forgetToken() async {
  try {
    await _storage.delete(key: _tokenKey);
  } catch (_) {}
}

void _start(Map<String, dynamic> session) {
  Api.token = session['token'];
  account.value = Account.fromJson(session['conta']);
  unawaited(_keepToken(Api.token!));
  if (!_listening) {
    homes.addListener(_scheduleSave);
    _listening = true;
  }
}

/// Abre o app: com login guardado no celular, confere o token na API e traz as casas da nuvem.
/// Token vencido ou conta apagada: apaga o token. Sem internet: fica sem conta agora e tenta ao abrir de novo.
Future<void> restoreSession() async {
  final String? token;
  try {
    token = await _storage.read(key: _tokenKey);
  } catch (_) {
    await _forgetToken(); // dado que nao abre mais (ex.: backup antigo): pede para entrar de novo
    return;
  }
  if (token == null || account.value != null) return;
  Api.token = token;
  try {
    final data = await Api.myAccount();
    _start({'token': token, 'conta': data});
    await _mergeCloudHomes();
  } on SessionExpired {
    _endSession();
  } catch (_) {
    // sem internet ou servidor acordando: fica sem conta agora; o token continua guardado para a proxima vez
    _timer?.cancel();
    Api.token = null;
    account.value = null;
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
  _start(await Api.logIn(email.trim(), password));
  try {
    await _mergeCloudHomes();
  } catch (_) {
    // entrou, mas nao trouxe as casas (internet caiu no meio): sai da conta sem apagar as casas do celular
    _endSession();
    rethrow;
  }
}

/// Traz as casas da nuvem e junta as que a pessoa montou no celular antes de entrar (sem perder nada).
Future<void> _mergeCloudHomes() async {
  final cloud = [for (final j in await Api.savedHomes()) Home.fromCloud(j)];
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
  account.value = Account.fromJson(
    await Api.updateAccount(name: name?.trim(), email: email?.trim()),
  );
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
  unawaited(_forgetToken());
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
    syncState.value = SyncState
        .failed; // tenta de novo na proxima mudanca (ou no "Tentar de novo")
  } finally {
    _saving = false;
  }
  // mudou alguma coisa enquanto gravava: grava de novo
  if (account.value != null && syncState.value == SyncState.saved && homes.list.any(_pending)) {
    _scheduleSave();
  }
}
