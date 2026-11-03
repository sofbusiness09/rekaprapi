import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../business/business.dart';
import '../common/dialogs.dart';
import '../common/format.dart';
import 'settings_repository.dart';

class MembersPage extends StatefulWidget {
  const MembersPage({super.key, required this.business, required this.repo});

  final Business business;
  final SettingsRepository repo;

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _Loaded {
  _Loaded(this.members, this.invites);
  final List<Member> members;
  final List<PendingInvite> invites;
}

class _MembersPageState extends State<MembersPage> {
  late Future<_Loaded> _future = _load();

  String get _uid => Supabase.instance.client.auth.currentUser!.id;

  Future<_Loaded> _load() async {
    final members = await widget.repo.members();
    final invites = widget.business.canManage
        ? await widget.repo.pendingInvites()
        : <PendingInvite>[];
    return _Loaded(members, invites);
  }

  void _reload() {
    if (mounted)
      setState(() {
        _future = _load();
      });
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      _reload();
    } on PostgrestException catch (e) {
      _toast(e.message);
    }
  }

  /// Cermin aturan di database; yang berlaku tetap aturan database.
  bool _canAct(Member m) {
    if (!widget.business.canManage || m.userId == _uid || m.role == 'owner') {
      return false;
    }
    return !(widget.business.role == 'admin' && m.role == 'admin');
  }

  Future<void> _invite() async {
    final result = await showDialog<(String, String)>(
        context: context, builder: (_) => const _InviteDialog());
    if (result == null) return;
    try {
      final code = await widget.repo.invite(result.$1, result.$2);
      _reload();
      if (!mounted) return;
      await _showCode(result.$1, code);
    } on PostgrestException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _showCode(String email, String code) {
    final text = 'Anda diundang ke "${widget.business.name}" di RekapRapi.\n'
        'Masuk dengan email $email lalu terima undangan, '
        'atau pilih "Gabung dengan kode" dan masukkan: $code\n'
        '(berlaku 7 hari)';
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Undangan dibuat'),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bagikan pesan ini kepada yang diundang:'),
              const SizedBox(height: 12),
              SelectableText(text),
            ]),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (mounted) _toast('Disalin.');
            },
            child: const Text('Salin pesan'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Selesai')),
        ],
      ),
    );
  }

  Future<void> _removeMember(Member m) async {
    if (await confirmDialog(context,
        title: 'Keluarkan anggota?',
        body:
            '${m.name} tidak akan bisa mengakses usaha ini lagi. Transaksi yang pernah ia catat tetap ada.',
        okLabel: 'Keluarkan')) {
      await _run(() => widget.repo.removeMember(m.userId));
    }
  }

  Future<void> _transfer(Member m) async {
    if (await confirmDialog(context,
        title: 'Alihkan kepemilikan?',
        body:
            '${m.name} menjadi Pemilik dan peran Anda menjadi Admin. Ini tidak bisa dibatalkan oleh Anda sendiri.',
        okLabel: 'Alihkan')) {
      await _run(() => widget.repo.transferOwnership(m.userId));
      if (mounted) {
        _toast(
            'Kepemilikan dialihkan. Buka ulang usaha untuk memperbarui tampilan.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anggota')),
      body: FutureBuilder<_Loaded>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError)
            return Center(child: Text('Gagal memuat: ${snap.error}'));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final d = snap.data!;
          final isOwner = widget.business.role == 'owner';
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final m in d.members)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(m.userId == _uid ? '${m.name} (Anda)' : m.name),
                    subtitle: Text([
                      roleLabel[m.role]!,
                      if (m.email != null) m.email!
                    ].join(' · ')),
                    trailing: _canAct(m)
                        ? PopupMenuButton<String>(
                            onSelected: (v) {
                              switch (v) {
                                case 'admin':
                                  _run(() => widget.repo
                                      .changeRole(m.userId, 'admin'));
                                case 'staff':
                                  _run(() => widget.repo
                                      .changeRole(m.userId, 'staff'));
                                case 'remove':
                                  _removeMember(m);
                                case 'transfer':
                                  _transfer(m);
                              }
                            },
                            itemBuilder: (_) => [
                              if (m.role == 'staff')
                                const PopupMenuItem(
                                    value: 'admin',
                                    child: Text('Jadikan Admin')),
                              if (m.role == 'admin' && isOwner)
                                const PopupMenuItem(
                                    value: 'staff',
                                    child: Text('Jadikan Staf')),
                              if (isOwner)
                                const PopupMenuItem(
                                    value: 'transfer',
                                    child: Text('Alihkan kepemilikan')),
                              const PopupMenuItem(
                                  value: 'remove', child: Text('Keluarkan')),
                            ],
                          )
                        : null,
                  ),
                if (d.invites.isNotEmpty) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text('Undangan tertunda',
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  for (final i in d.invites)
                    ListTile(
                      leading:
                          const CircleAvatar(child: Icon(Icons.mail_outline)),
                      title: Text(i.email),
                      subtitle: Text(
                          '${roleLabel[i.role]} · kode ${i.code} · sampai ${dateId(i.expiresAt)}'),
                      trailing: Wrap(children: [
                        IconButton(
                          tooltip: 'Salin kode',
                          icon: const Icon(Icons.copy),
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: i.code));
                            if (mounted) _toast('Kode disalin.');
                          },
                        ),
                        IconButton(
                          tooltip: 'Batalkan',
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              _run(() => widget.repo.cancelInvite(i.id)),
                        ),
                      ]),
                    ),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: widget.business.canManage
          ? FloatingActionButton.extended(
              onPressed: _invite,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Undang'),
            )
          : null,
    );
  }
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog();

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _email = TextEditingController();
  String _role = 'staff';

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Undang anggota'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _role,
          decoration: const InputDecoration(labelText: 'Peran'),
          items: const [
            DropdownMenuItem(value: 'staff', child: Text('Staf')),
            DropdownMenuItem(value: 'admin', child: Text('Admin')),
          ],
          onChanged: (v) => setState(() => _role = v ?? 'staff'),
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            final e = _email.text.trim();
            if (e.contains('@')) Navigator.pop(context, (e, _role));
          },
          child: const Text('Buat undangan'),
        ),
      ],
    );
  }
}
