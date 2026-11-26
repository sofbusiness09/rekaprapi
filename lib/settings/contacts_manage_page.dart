import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../business/business.dart';
import '../common/dialogs.dart';
import '../common/widgets.dart';
import '../debts/contact_form.dart';
import '../debts/debt_models.dart';
import '../debts/debt_repository.dart';
import 'package:rekap_rapi/l10n/l10n.dart';

/// Pengaturan > Kontak Pelanggan (Pembukuan Pribadi: Kontak): daftar semua kontak untuk diubah (nama, nomor
/// telepon, alamat, catatan), ditambah, atau dihapus. Semua anggota boleh mengubah;
/// menghapus hanya untuk Pemilik/Admin dan hanya bila utang piutangnya lunas.
class ContactsManagePage extends StatefulWidget {
  const ContactsManagePage({
    super.key,
    required this.business,
    required this.repo,
    required this.changes,
  });

  final Business business;
  final DebtRepository repo;

  /// Dinaikkan setelah kontak berubah agar tab lain ikut memuat ulang.
  final ValueNotifier<int> changes;

  @override
  State<ContactsManagePage> createState() => _ContactsManagePageState();
}

class _ContactsManagePageState extends State<ContactsManagePage> {
  late Future<List<Contact>> _future = widget.repo.contacts();
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.changes.addListener(_reload);
  }

  @override
  void dispose() {
    widget.changes.removeListener(_reload);
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _future = widget.repo.contacts();
      });
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _edit([Contact? existing]) async {
    final saved =
        await showContactForm(context, repo: widget.repo, existing: existing);
    if (saved != null) {
      widget.changes.value++;
      _toast(existing == null
          ? tr('Kontak ditambahkan.')
          : tr('Kontak diperbarui.'));
    }
  }

  Future<void> _delete(Contact c) async {
    final ok = await confirmDialog(context,
        title: tr('Hapus kontak?'),
        body: tr(
            '{0} akan dihapus dari daftar. Riwayat transaksi lamanya tetap tersimpan.',
            [c.name]),
        okLabel: tr('Hapus'));
    if (!ok) return;
    try {
      await widget.repo.deleteContact(c.id);
      widget.changes.value++;
      _toast(tr('Kontak dihapus.'));
    } on PostgrestException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast(tr('Gagal: {0}', [e]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.business.isPersonal
              ? tr('Kontak')
              : tr('Kontak Pelanggan'))),
      body: FutureBuilder<List<Contact>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(tr('Gagal memuat: {0}', [snap.error])));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data!;
          final q = _search.text.trim().toLowerCase();
          final items = [
            for (final c in all)
              if (q.isEmpty ||
                  c.name.toLowerCase().contains(q) ||
                  (c.phone ?? '').toLowerCase().contains(q) ||
                  (c.address ?? '').toLowerCase().contains(q))
                c,
          ];

          return ContentWidth(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
              children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: tr('Cari nama, nomor telepon, atau alamat'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(_search.clear)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                  child: Text(tr('{0} kontak', [all.length]),
                      style:
                          theme.textTheme.labelMedium?.copyWith(color: muted)),
                ),
                if (all.isEmpty)
                  EmptyState(
                    icon: Icons.people_alt_rounded,
                    title: tr('Belum ada kontak'),
                    actionLabel: tr('Tambah kontak'),
                    onAction: _edit,
                  )
                else if (items.isEmpty)
                  EmptyState(
                    icon: Icons.search_off_rounded,
                    title: tr('Tidak ada yang cocok'),
                    subtitle: tr('Ubah kata pencarian.'),
                  ),
                for (final c in items) ...[
                  SoftCard(
                    padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                    onTap: () => _edit(c),
                    child: Row(children: [
                      InitialAvatar(c.name),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              Text(c.phone ?? tr('Belum ada nomor telepon'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: muted)),
                              if (c.address != null)
                                Text(c.address!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: muted)),
                            ]),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (v) => v == 'edit' ? _edit(c) : _delete(c),
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'edit', child: Text(tr('Ubah'))),
                          if (widget.business.canManage)
                            PopupMenuItem(
                                value: 'delete', child: Text(tr('Hapus'))),
                        ],
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(tr('Kontak baru')),
      ),
    );
  }
}
