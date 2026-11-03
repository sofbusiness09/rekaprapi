import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cash/cash_models.dart';
import '../common/dialogs.dart';
import 'settings_repository.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, required this.repo});

  final SettingsRepository repo;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  late Future<List<Category>> _future = widget.repo.categories();

  void _reload() {
    if (mounted)
      setState(() {
        _future = widget.repo.categories();
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

  Future<void> _add() async {
    final type = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Jenis kategori'),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'in'),
              child: const Text('Kas masuk')),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'out'),
              child: const Text('Kas keluar')),
        ],
      ),
    );
    if (type == null || !mounted) return;
    final name = await askText(context, title: 'Kategori baru', label: 'Nama');
    if (name == null || name.isEmpty) return;
    await _run(() => widget.repo.addCategory(name, type));
  }

  Future<void> _rename(Category c) async {
    final name = await askText(context,
        title: 'Ubah nama kategori', label: 'Nama', initial: c.name);
    if (name == null || name.isEmpty || name == c.name) return;
    await _run(() => widget.repo.renameCategory(c.id, name));
  }

  Future<void> _delete(Category c) async {
    if (await confirmDialog(context,
        title: 'Hapus kategori?', body: c.name, okLabel: 'Hapus')) {
      await _run(() => widget.repo.deleteCategory(c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kategori')),
      body: FutureBuilder<List<Category>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError)
            return Center(child: Text('Gagal memuat: ${snap.error}'));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final all = snap.data!;
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              for (final section in const <(String, String)>[
                ('in', 'Kas masuk'),
                ('out', 'Kas keluar'),
              ]) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(section.$2,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                for (final c in all.where((c) => c.type == section.$1))
                  ListTile(
                    title: Text(c.name),
                    leading: c.isSystem ? const Icon(Icons.lock_outline) : null,
                    subtitle: c.isSystem
                        ? const Text('Dipakai otomatis oleh utang piutang')
                        : null,
                    trailing: c.isSystem
                        ? null
                        : PopupMenuButton<String>(
                            onSelected: (v) =>
                                v == 'rename' ? _rename(c) : _delete(c),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'rename', child: Text('Ubah nama')),
                              PopupMenuItem(
                                  value: 'delete', child: Text('Hapus')),
                            ],
                          ),
                  ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Kategori'),
      ),
    );
  }
}
