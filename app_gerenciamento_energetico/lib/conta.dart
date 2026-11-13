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

/// Por que a ultima gravacao falhou (mensagem da API; null = sem internet ou nada a dizer).
final syncError = ValueNotifier<String?>(null);

/// A sessao terminou com mudancas ainda nao salvas: as casas continuam no celular e a tela pede para entrar
/// de novo (entrando na mesma conta, a versao do celular e a que fica).
final sessionEnded = ValueNotifier<bool>(false);

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

/// E-mail da conta dona das casas que estao na memoria (null = casas montadas sem conta).
String? _owner;

/// Restauracao do login ao abrir o app: entrar na mao espera ela terminar (senao as duas juntam as casas).
Future<void>? _restoring;

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
  sessionEnded.value = false;
  unawaited(_keepToken(Api.token!));
  if (!_listening) {
    homes.addListener(_scheduleSave);
    _listening = true;
  }
}

/// Abre o app: com login guardado no celular, confere o token na API e traz as casas da nuvem.
/// Token vencido ou conta apagada: apaga o token. Sem internet: fica sem conta agora e tenta ao abrir de novo.
Future<void> restoreSession() => _restoring = _restore();

Future<void> _restore() async {
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
    final previousOwner = _owner;
    _start({'token': token, 'conta': data});
    await _mergeCloudHomes(previousOwner);
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
  await _restoring;
  _start(await Api.signUp(name.trim(), email.trim(), password));
  for (final h in homes.list) {
    h.cloudId = null;
  }
  _owner = account.value!.email;
  await saveNow();
}

/// Entra na conta: traz as casas da nuvem e junta as que a pessoa montou antes de entrar (sem perder nada).
Future<void> logIn(String email, String password) async {
  await _restoring;
  final previousOwner = _owner;
  _start(await Api.logIn(email.trim(), password));
  try {
    await _mergeCloudHomes(previousOwner);
  } catch (_) {
    // entrou, mas nao trouxe as casas (internet caiu no meio): sai da conta sem apagar as casas do celular
    _endSession();
    rethrow;
  }
}

/// Traz as casas da nuvem e junta as do celular (sem perder nada):
/// - casa montada sem conta: vai para a conta como casa nova;
/// - casa da mesma conta que ficou no celular (a sessao venceu com mudanca nao salva): a versao do celular vence;
/// - casa de outra conta (outra pessoa usou este celular): fica fora, os dados eram da outra conta.
Future<void> _mergeCloudHomes(String? previousOwner) async {
  final cloud = [for (final j in await Api.savedHomes()) Home.fromCloud(j)];
  for (final h in cloud) {
    _savedVersion[h] = h.version;
  }
  final sameOwner = previousOwner != null && previousOwner == account.value?.email;
  final local = <Home>[];
  for (final h in homes.list) {
    if (h.cloudId == null) {
      if (!h.isEmpty) local.add(h);
      continue;
    }
    final i = cloud.indexWhere((c) => c.cloudId == h.cloudId);
    if (sameOwner && i >= 0) cloud[i] = h; // _savedVersion dela continua o da ultima gravacao: manda o que mudou
  }
  _owner = account.value?.email;
  final open = [...cloud, ...local].contains(home) ? home : null;
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

/// Corrige nome e/ou e-mail no servidor. Trocar o e-mail pede a senha atual (403 se errada).
Future<void> updateAccount({String? name, String? email, String? currentPassword}) async {
  account.value = Account.fromJson(
    await Api.updateAccount(name: name?.trim(), email: email?.trim(), currentPassword: currentPassword),
  );
  _owner = account.value!.email;
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

/// Volta o estado da conta ao de um app recem-aberto (os testes chamam no setUp).
@visibleForTesting
void resetAccountState() {
  _timer?.cancel();
  _owner = null;
  _restoring = null;
  sessionEnded.value = false;
  syncError.value = null;
  syncState.value = SyncState.saved;
}

/// Sai da conta e volta para uma casa vazia (sair ou apagar a conta: os dados eram da conta).
void _endLocal() {
  _endSession();
  _owner = null;
  sessionEnded.value = false;
  homes.reset();
}

/// Sai da conta e deixa as casas do celular como estao.
void _endSession() {
  _timer?.cancel();
  unawaited(_forgetToken());
  Api.token = null;
  account.value = null;
  syncState.value = SyncState.saved;
  syncError.value = null;
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
      if (h.cloudId == null) {
        final id = (await Api.createHome(h.name, h.residents))['id'] as int;
        if (!homes.list.contains(h)) {
          await Api.deleteHome(id); // a pessoa apagou a casa enquanto ela era criada: nao deixa sobrar na nuvem
          continue;
        }
        h.cloudId = id;
      }
      await Api.saveHome(h.cloudId!, h.toCloud());
      _savedVersion[h] = version;
    }
    syncState.value = SyncState.saved;
    syncError.value = null;
  } on SessionExpired {
    // sessao vencida ou conta apagada em outro aparelho: sai da conta, mas as casas (com a mudanca que nao foi
    // salva) ficam no celular; entrando de novo na mesma conta, elas vao para a nuvem
    _endSession();
    sessionEnded.value = true;
  } on ApiError catch (e) {
    // tenta de novo na proxima mudanca (ou no "Tentar de novo"); a mensagem diz o motivo (ex.: limite de casas)
    syncError.value = e is ConnectionProblem ? null : e.message;
    syncState.value = SyncState.failed;
  } finally {
    _saving = false;
  }
  // mudou alguma coisa enquanto gravava: grava de novo
  if (account.value != null && syncState.value == SyncState.saved && homes.list.any(_pending)) {
    _scheduleSave();
  }
}
