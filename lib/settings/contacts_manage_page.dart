import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../business/business.dart';
import '../common/dialogs.dart';
import '../common/widgets.dart';
import '../debts/contact_form.dart';
import '../debts/debt_models.dart';
import '../debts/debt_repository.dart';

/// Pengaturan > Kontak Pelanggan: daftar semua kontak untuk diubah (nama, nomor
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
      _toast(existing == null ? 'Kontak ditambahkan.' : 'Kontak diperbarui.');
    }
  }

  Future<void> _delete(Contact c) async {
    final ok = await confirmDialog(context,
        title: 'Hapus kontak?',
        body:
            '${c.name} akan dihapus dari daftar. Riwayat transaksi lamanya tetap tersimpan.',
        okLabel: 'Hapus');
    if (!ok) return;
    try {
      await widget.repo.deleteContact(c.id);
      widget.changes.value++;
      _toast('Kontak dihapus.');
    } on PostgrestException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Gagal: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Kontak Pelanggan')),
      body: FutureBuilder<List<Contact>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Gagal memuat: ${snap.error}'));
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
                    hintText: 'Cari nama, nomor telepon, atau alamat',
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
                  child: Text('${all.length} kontak',
                      style:
                          theme.textTheme.labelMedium?.copyWith(color: muted)),
                ),
                if (all.isEmpty)
                  EmptyState(
                    icon: Icons.people_alt_rounded,
                    title: 'Belum ada kontak',
                    subtitle:
                        'Tambahkan pelanggan dan pemasok Anda beserta nomor teleponnya.',
                    actionLabel: 'Tambah kontak',
                    onAction: _edit,
                  )
                else if (items.isEmpty)
                  const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Tidak ada yang cocok',
                    subtitle: 'Ubah kata pencarian.',
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
                              Text(c.phone ?? 'Belum ada nomor telepon',
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
                          const PopupMenuItem(
                              value: 'edit', child: Text('Ubah')),
                          if (widget.business.canManage)
                            const PopupMenuItem(
                                value: 'delete', child: Text('Hapus')),
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
        label: const Text('Kontak baru'),
      ),
    );
  }
}
