// Minhas casas: a pessoa tem uma ou mais casas (ex.: a casa e o apartamento da praia) e escolhe qual abrir.
// Cada casa tem os proprios aparelhos, moradores, perfil e plano. Com conta, tudo fica salvo na nuvem
// (conta.dart); sem conta, as casas ficam so neste aparelho ate fechar o app.

import 'package:flutter/material.dart';

import '../api.dart';
import '../casa.dart';
import '../conta.dart';
import '../idioma.dart';
import '../tema.dart';
import 'cadastro.dart';
import 'comum.dart';

/// Pergunta o nome da casa (nova ou renomear). Devolve null se a pessoa cancelar.
Future<String?> askHomeName(BuildContext context, {String initial = ''}) => showDialog<String>(
  context: context,
  builder: (context) => _NameDialog(initial: initial),
);

class _NameDialog extends StatefulWidget {
  final String initial;

  const _NameDialog({required this.initial});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _ok() {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 80) {
      setState(() => _error = tr('Digite um nome para a casa.', 'Enter a name for the home.'));
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final creating = widget.initial.isEmpty;
    return AlertDialog(
      title: Text(creating ? tr('Nova casa', 'New home') : tr('Renomear casa', 'Rename home')),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _ok(),
        decoration: InputDecoration(
          labelText: tr('Nome da casa', 'Home name'),
          hintText: tr('Ex.: Apartamento da praia', 'E.g.: Beach apartment'),
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancelar', 'Cancel'))),
        FilledButton(onPressed: _ok, child: Text(creating ? tr('Criar', 'Create') : tr('Salvar', 'Save'))),
      ],
    );
  }
}

class HomesScreen extends StatefulWidget {
  const HomesScreen({super.key});

  @override
  State<HomesScreen> createState() => _HomesScreenState();
}

class _HomesScreenState extends State<HomesScreen> {
  String? _error;

  Future<void> _new() async {
    final name = await askHomeName(context);
    if (name == null || !mounted) return;
    homes.add(name); // com conta, conta.dart cria no servidor
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          content: Text(tr('Casa "$name" criada e aberta.', 'Home "$name" created and opened.')),
        ),
      );
  }

  Future<void> _rename(Home h) async {
    final name = await askHomeName(context, initial: h.name);
    if (name != null) h.rename(name);
  }

  Future<void> _delete(Home h) async {
    final n = h.totalAppliances;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Apagar "${h.name}"?', 'Delete "${h.name}"?')),
        content: Text(switch (n) {
          0 => tr('A casa está vazia.', 'The home is empty.'),
          1 => tr(
            'O aparelho dela também sai. Não dá para desfazer.',
            'Its appliance goes too. This cannot be undone.',
          ),
          _ => tr(
            'Os $n aparelhos dela também saem. Não dá para desfazer.',
            'Its $n appliances go too. This cannot be undone.',
          ),
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancelar', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Apagar', 'Delete'))),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await removeHome(h);
      if (mounted) setState(() => _error = null);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _open(Home h) {
    homes.select(h);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([homes, account, syncState]),
      builder: (context, _) => AppPage(
        title: tr('Minhas casas', 'My homes'),
        footer: FilledButton.icon(
          onPressed: _new,
          icon: const Icon(Icons.add_home_outlined),
          label: Text(tr('Nova casa', 'New home')),
        ),
        child: ListView(
          children: [
            QuestionHeader(
              tr('Qual casa você quer ver?', 'Which home do you want to see?'),
              help: tr(
                'Cada casa tem os próprios aparelhos e moradores. Ex.: a sua casa e a casa da praia.',
                'Each home has its own appliances and residents. E.g.: your home and the beach house.',
              ),
            ),
            for (final h in homes.list)
              _HomeCard(
                h,
                onOpen: () => _open(h),
                onRename: () => _rename(h),
                onDelete: homes.list.length > 1 ? () => _delete(h) : null,
              ),
            if (_error != null) ...[const SizedBox(height: Spacing.m), ErrorMessage(_error!)],
            const SizedBox(height: Spacing.m),
            const _WhereSaved(),
          ],
        ),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final Home home;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback? onDelete; // null = ultima casa (nao sai)

  const _HomeCard(this.home, {required this.onOpen, required this.onRename, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final open = identical(home, homes.active);
    final n = home.totalAppliances;
    final summary = n == 0
        ? tr('Vazia', 'Empty')
        : tr(
            '${reais(home.monthlyCost)} por mês · $n ${n == 1 ? 'aparelho' : 'aparelhos'}',
            '${reais(home.monthlyCost)} per month · $n ${n == 1 ? 'appliance' : 'appliances'}',
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OptionCard(
            icon: Icons.home_outlined,
            title: home.name,
            subtitle: open ? '$summary\n${tr('Aberta agora', 'Open now')}' : summary,
            selected: open,
            onTap: onOpen,
          ),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onRename,
                icon: const Icon(Icons.edit_outlined),
                label: Text(tr('Renomear', 'Rename')),
              ),
              if (onDelete != null)
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(tr('Apagar', 'Delete')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Diz onde as casas ficam: na conta (com a situacao da gravacao) ou so neste aparelho.
class _WhereSaved extends StatelessWidget {
  const _WhereSaved();

  @override
  Widget build(BuildContext context) {
    final t = Iamp.de(context);
    final a = account.value;
    if (a == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              'Sem conta, as casas ficam só neste aparelho e somem ao fechar o app.',
              'Without an account, homes stay only on this device and disappear when you close the app.',
            ),
            style: t.secondary,
          ),
          const SizedBox(height: Spacing.p),
          OutlinedButton.icon(
            onPressed: () => openAccount(context),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(tr('Criar conta para salvar', 'Sign up to save')),
          ),
          TextButton(
            onPressed: () => openAccount(context, logIn: true),
            child: Text(tr('Já tenho conta: entrar', 'I have an account: log in')),
          ),
        ],
      );
    }
    final (icon, text) = switch (syncState.value) {
      SyncState.saving => (Icons.cloud_sync_outlined, tr('Salvando na sua conta...', 'Saving to your account...')),
      SyncState.saved => (
        Icons.cloud_done_outlined,
        tr('Salvo na conta ${a.email}.', 'Saved to the account ${a.email}.'),
      ),
      SyncState.failed => (
        Icons.cloud_off_outlined,
        tr(
          'Não consegui salvar agora. Confira a internet.',
          'Could not save right now. Check your internet connection.',
        ),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: syncState.value == SyncState.failed ? t.alert : t.highlight),
            const SizedBox(width: Spacing.pm),
            Expanded(child: Text(text, style: t.secondary)),
          ],
        ),
        if (syncState.value == SyncState.failed)
          TextButton(onPressed: saveNow, child: Text(tr('Tentar de novo', 'Try again'))),
      ],
    );
  }
}

/// Botao do topo de "Minha casa": mostra a casa aberta e leva para a lista de casas.
class HomeSwitcher extends StatelessWidget {
  const HomeSwitcher({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: homes, builder: (context, _) => _button(context));

  Widget _button(BuildContext context) {
    final t = Iamp.de(context);
    final many = homes.list.length > 1;
    return MergeSemantics(
      child: OutlinedButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HomesScreen())),
        child: Row(
          children: [
            Icon(Icons.home_outlined, color: t.highlight),
            const SizedBox(width: Spacing.pm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.p),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(home.name, style: t.strong, overflow: TextOverflow.ellipsis, maxLines: 2),
                    Text(
                      many
                          ? tr('Trocar de casa ou criar outra', 'Switch home or add one')
                          : tr('Criar outra casa', 'Add another home'),
                      style: t.secondary,
                    ),
                  ],
                ),
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
