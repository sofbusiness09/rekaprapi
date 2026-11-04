import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'debt_models.dart';
import 'debt_repository.dart';
import '../common/glass.dart';

/// Lembar tambah/ubah kontak (nama, telepon, alamat, catatan).
/// Mengembalikan kontak yang tersimpan (dengan data terbaru), atau null bila dibatalkan.
Future<Contact?> showContactForm(
  BuildContext context, {
  required DebtRepository repo,
  Contact? existing,
}) {
  return showGlassSheet<Contact>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _ContactForm(repo: repo, existing: existing),
  );
}

class _ContactForm extends StatefulWidget {
  const _ContactForm({required this.repo, required this.existing});

  final DebtRepository repo;
  final Contact? existing;

  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _address =
      TextEditingController(text: widget.existing?.address ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  bool _busy = false;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String? _clean(String s) => s.trim().isEmpty ? null : s.trim();

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast('Isi nama kontak.');
      return;
    }
    setState(() => _busy = true);
    try {
      final String id;
      if (_editing) {
        id = widget.existing!.id;
        await widget.repo.updateContact(id,
            name: name,
            phone: _phone.text,
            address: _address.text,
            note: _note.text);
      } else {
        id = await widget.repo.createContact(
            name: name,
            phone: _phone.text,
            address: _address.text,
            note: _note.text);
      }
      if (!mounted) return;
      Navigator.pop(
        context,
        Contact(id, name, _clean(_phone.text),
            address: _clean(_address.text), note: _clean(_note.text)),
      );
    } on PostgrestException catch (e) {
      _toast(e.message);
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      _toast('Gagal menyimpan: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_editing ? 'Ubah kontak' : 'Kontak baru',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: !_editing,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Nomor telepon / WhatsApp',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Alamat (opsional)',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : Text(_editing ? 'Simpan perubahan' : 'Simpan kontak'),
            ),
          ],
        ),
      ),
    );
  }
}
