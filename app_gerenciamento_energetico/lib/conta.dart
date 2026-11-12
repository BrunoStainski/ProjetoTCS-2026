// Cadastro da pessoa (nome e e-mail). Fica so na memoria do aparelho, como a "Minha casa":
// nao e enviado para a API nem gravado no banco, e some ao fechar o app.
// Por que nao vai para o banco: nome e e-mail sao dados pessoais (LGPD). Para guardar no servidor
// o projeto precisa antes de consentimento registrado, aviso de privacidade, senha com hash,
// HTTPS e um jeito de a pessoa ver e apagar os dados (ver "Cadastro e LGPD" no CLAUDE.md).

import 'package:flutter/foundation.dart';

class Account {
  final String name;
  final String email;

  const Account(this.name, this.email);

  /// Primeiro nome, para a saudacao ("Olá, Maria").
  String get firstName => name.trim().split(RegExp(r'\s+')).first;
}

/// Cadastro atual (null = a pessoa esta usando o app sem cadastro, o que continua valendo).
final account = ValueNotifier<Account?>(null);

final _emailFormat = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool validEmail(String text) => _emailFormat.hasMatch(text.trim());
