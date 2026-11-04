import 'package:flutter/material.dart';

import '../common/widgets.dart';
import 'debt_models.dart';
import 'debt_repository.dart';

const _newContact = '__new__';

/// Menyimpan pilihan kontak, atau isian kontak baru, untuk formulir yang
/// mewajibkan siapa yang berutang. Panggil [dispose] saat formulir ditutup.
class ContactPickerController {
  String? selected;
  final name = TextEditingController();
  final phone = TextEditingController();

  bool get isNew => selected == _newContact;

  void selectNew() => selected = _newContact;

  void dispose() {
    name.dispose();
    phone.dispose();
  }

  /// Pesan galat bila isian belum lengkap; null bila valid.
  String? validate() {
    if (selected == null) return 'Pilih kontak, atau tambah kontak baru.';
    if (isNew && name.text.trim().isEmpty) return 'Isi nama kontak baru.';
    return null;
  }

  /// Mengembalikan id kontak; membuat kontak baru bila perlu.
  Future<String> resolve(DebtRepository repo) async =>
      isNew ? repo.addContact(name.text, phone.text) : selected!;
}

/// Pilihan kontak dengan **pencarian** (nama atau nomor telepon) dan opsi
/// "Tambah kontak baru" yang menampilkan isian nama dan HP.
class ContactPicker extends StatelessWidget {
  const ContactPicker({
    super.key,
    required this.controller,
    required this.contacts,
    required this.label,
    required this.onChanged,
  });

  final ContactPickerController controller;
  final List<Contact> contacts;
  final String label;

  /// Dipanggil setelah pilihan berubah, agar induk membangun ulang tampilan.
  final VoidCallback onChanged;

  Contact? get _selectedContact {
    for (final c in contacts) {
      if (c.id == controller.selected) return c;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    final result = await showModalBottomSheet<(String, String?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _SearchSheet(
          contacts: contacts, selectedId: controller.selected, title: label),
    );
    if (result == null) return;
    controller.selected = result.$1;
    // Mengetik nama di pencarian lalu memilih "Tambah" mengisi nama kontak baru.
    if (result.$1 == _newContact && result.$2 != null) {
      controller.name.text = result.$2!;
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picked = _selectedContact;
    final hasValue = controller.isNew || picked != null;
    final text = controller.isNew
        ? 'Kontak baru'
        : (picked?.name ?? 'Pilih atau cari kontak');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(context),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.person_outline_rounded),
            suffixIcon: const Icon(Icons.search_rounded),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: hasValue
                ? null
                : theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
      if (controller.isNew) ...[
        const SizedBox(height: 12),
        TextField(
          controller: controller.name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nama kontak',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller.phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'No. HP (opsional)',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
      ],
    ]);
  }
}

/// Lembar pencarian kontak. Mengembalikan (id, namaBaru) atau null bila ditutup.
class _SearchSheet extends StatefulWidget {
  const _SearchSheet(
      {required this.contacts, required this.selectedId, required this.title});

  final List<Contact> contacts;
  final String? selectedId;
  final String title;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final q = _query.text.trim().toLowerCase();
    final matches = [
      for (final c in widget.contacts)
        if (q.isEmpty ||
            c.name.toLowerCase().contains(q) ||
            (c.phone ?? '').toLowerCase().contains(q))
          c,
    ];
    final height = MediaQuery.sizeOf(context).height;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TextField(
              controller: _query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Cari nama atau nomor telepon',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_query.clear)),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              children: [
                if (widget.contacts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        'Belum ada kontak. Tambahkan kontak baru di bawah.',
                        textAlign: TextAlign.center,
                        style:
                            theme.textTheme.bodyMedium?.copyWith(color: muted)),
                  )
                else if (matches.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Tidak ada kontak yang cocok.',
                        textAlign: TextAlign.center,
                        style:
                            theme.textTheme.bodyMedium?.copyWith(color: muted)),
                  ),
                for (final c in matches)
                  ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    selected: c.id == widget.selectedId,
                    leading: InitialAvatar(c.name, size: 42),
                    title: Text(c.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: c.phone == null ? null : Text(c.phone!),
                    trailing: c.id == widget.selectedId
                        ? const Icon(Icons.check_circle_rounded)
                        : null,
                    onTap: () => Navigator.pop(context, (c.id, null)),
                  ),
              ],
            ),
          ),
          // Tambah kontak hanya bila orangnya belum ada di daftar di atas.
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                leading: const IconBadge(Icons.person_add_alt_1_rounded,
                    color: Colors.green, size: 42),
                title: Text(
                  q.isEmpty
                      ? 'Tambah kontak baru'
                      : 'Tambah "${_query.text.trim()}" sebagai kontak baru',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () => Navigator.pop(context,
                    (_newContact, q.isEmpty ? null : _query.text.trim())),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
