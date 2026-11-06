import 'package:flutter/material.dart';

import '../business/business.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../theme/app_theme.dart';
import 'contact_form.dart';
import 'contact_page.dart';
import 'debt_models.dart';
import 'debt_repository.dart';

enum _Filter { all, receivable, payable, settled }

/// Urutan daftar: bawaannya yang terbaru (catatan utang terakhir) di atas.
enum _Sort {
  newest('Terbaru'),
  oldest('Terlama'),
  largest('Terbesar'),
  smallest('Terkecil');

  const _Sort(this.label);
  final String label;
}

/// Tab Kontak: semua orang yang bertransaksi dengan usaha, lengkap dengan saldo
/// bersih masing-masing (piutang dan utang digabung menjadi satu).
class ContactsPage extends StatefulWidget {
  const ContactsPage({
    super.key,
    required this.business,
    required this.repo,
    required this.changes,
  });

  final Business business;
  final DebtRepository repo;

  /// Dinaikkan saat ada perubahan data (realtime / setelah menyimpan).
  final ValueNotifier<int> changes;

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _Loaded {
  _Loaded(this.contacts, this.debts);
  final List<Contact> contacts;
  final List<Debt> debts;
}

/// Ringkasan satu kontak: saldo bersih dari semua catatannya.
class _Row {
  _Row(this.contact, this.debts);

  final Contact contact;
  final List<Debt> debts;

  int get receivable =>
      debts.where((d) => d.isReceivable).fold(0, (s, d) => s + d.remaining);
  int get payable =>
      debts.where((d) => !d.isReceivable).fold(0, (s, d) => s + d.remaining);

  /// Positif = kontak berutang kepada Anda; negatif = Anda berutang kepadanya.
  int get net => receivable - payable;
  bool get settled => net == 0 && receivable == 0 && payable == 0;

  DateTime? get nextDue {
    final dues = [
      for (final d in debts)
        if (!d.settled && d.dueDate != null) d.dueDate!,
    ]..sort();
    return dues.isEmpty ? null : dues.first;
  }

  bool get overdue => debts.any((d) => d.overdue);

  /// Waktu catatan utang terakhir kontak ini; null bila belum ada catatan.
  DateTime? get latest {
    DateTime? best;
    for (final d in debts) {
      if (best == null || d.createdAt.isAfter(best)) best = d.createdAt;
    }
    return best;
  }
}

class _ContactsPageState extends State<ContactsPage> {
  late Future<_Loaded> _future = _load();
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.newest;

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

  Future<_Loaded> _load() async {
    final r = await Future.wait([widget.repo.contacts(), widget.repo.debts()]);
    return _Loaded(r[0] as List<Contact>, r[1] as List<Debt>);
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _future = _load();
      });
    }
  }

  Future<void> _add() async {
    final c = await showContactForm(context, repo: widget.repo);
    if (c != null) widget.changes.value++;
  }

  Future<void> _open(Contact c) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ContactPage(
        business: widget.business,
        repo: widget.repo,
        contact: c,
        changes: widget.changes,
      ),
    ));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Loaded>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Gagal memuat: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = snap.data!;
        final byContact = <String, List<Debt>>{};
        for (final x in d.debts) {
          byContact.putIfAbsent(x.contactId, () => []).add(x);
        }
        final rows = [
          for (final c in d.contacts) _Row(c, byContact[c.id] ?? const []),
        ];
        final totalReceivable = rows.fold(0, (s, r) => s + r.receivable);
        final totalPayable = rows.fold(0, (s, r) => s + r.payable);

        final q = _search.text.trim().toLowerCase();
        final items = rows.where((r) {
          if (q.isNotEmpty &&
              !r.contact.name.toLowerCase().contains(q) &&
              !(r.contact.phone ?? '').toLowerCase().contains(q)) {
            return false;
          }
          switch (_filter) {
            case _Filter.all:
              return true;
            case _Filter.receivable:
              return r.net > 0;
            case _Filter.payable:
              return r.net < 0;
            case _Filter.settled:
              return r.net == 0;
          }
        }).toList()
          ..sort((a, b) {
            int byName() => a.contact.name
                .toLowerCase()
                .compareTo(b.contact.name.toLowerCase());
            switch (_sort) {
              case _Sort.newest:
              case _Sort.oldest:
                final x = a.latest, y = b.latest;
                // Kontak tanpa catatan selalu di bawah.
                if ((x == null) != (y == null)) return x == null ? 1 : -1;
                if (x == null || y == null) return byName();
                final c =
                    _sort == _Sort.newest ? y.compareTo(x) : x.compareTo(y);
                return c != 0 ? c : byName();
              case _Sort.largest:
              case _Sort.smallest:
                final ab = a.net.abs(), bb = b.net.abs();
                // Yang sudah lunas selalu di bawah.
                if ((ab == 0) != (bb == 0)) return ab == 0 ? 1 : -1;
                final c = _sort == _Sort.largest
                    ? bb.compareTo(ab)
                    : ab.compareTo(bb);
                return c != 0 ? c : byName();
            }
          });
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ContentWidth(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                children: [
                  Row(children: [
                    Expanded(
                      child: _Total(
                        label: 'Piutang',
                        hint: '',
                        value: totalReceivable,
                        color: Brand.receivable,
                        icon: Icons.call_received_rounded,
                        selected: _filter == _Filter.receivable,
                        onTap: () => setState(() => _filter =
                            _filter == _Filter.receivable
                                ? _Filter.all
                                : _Filter.receivable),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Total(
                        label: 'Utang',
                        hint: '',
                        value: totalPayable,
                        color: Brand.payable,
                        icon: Icons.call_made_rounded,
                        selected: _filter == _Filter.payable,
                        onTap: () => setState(() => _filter =
                            _filter == _Filter.payable
                                ? _Filter.all
                                : _Filter.payable),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Cari nama atau nomor telepon',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => setState(_search.clear)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Tambah kontak',
                      onPressed: _add,
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final f in const <(_Filter, String)>[
                        (_Filter.all, 'Semua'),
                        (_Filter.receivable, 'Piutang'),
                        (_Filter.payable, 'Utang'),
                        (_Filter.settled, 'Lunas'),
                      ]) ...[
                        ChoiceChip(
                          label: Text(f.$2),
                          selected: _filter == f.$1,
                          onSelected: (_) => setState(() => _filter = f.$1),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 4),
                  // Urutan di baris sendiri, di kanan, agar tidak berdesakan dengan filter.
                  Row(children: [
                    Expanded(
                      child: Text('${items.length} kontak',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                    ),
                    PopupMenuButton<_Sort>(
                      tooltip: 'Urutkan',
                      initialValue: _sort,
                      onSelected: (v) => setState(() => _sort = v),
                      itemBuilder: (_) => [
                        for (final s in _Sort.values)
                          PopupMenuItem(value: s, child: Text(s.label)),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.swap_vert_rounded, size: 18),
                          const SizedBox(width: 6),
                          Text('Urutkan: ${_sort.label}',
                              style: Theme.of(context).textTheme.labelLarge),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  if (d.contacts.isEmpty)
                    EmptyState(
                      icon: Icons.people_alt_rounded,
                      title: 'Belum ada kontak',
                      actionLabel: 'Tambah kontak',
                      onAction: _add,
                    )
                  else if (items.isEmpty)
                    const EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'Tidak ada yang cocok',
                      subtitle: 'Ubah kata pencarian atau pilihan filter.',
                    ),
                  for (final r in items) ...[
                    _ContactTile(row: r, onTap: () => _open(r.contact)),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.hint,
    required this.value,
    required this.color,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final int value;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: selected ? color.withValues(alpha: 0.10) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
            color: selected ? color : theme.dividerTheme.color ?? Colors.grey,
            width: selected ? 1.6 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconBadge(icon, color: color, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 16),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(rupiah(value),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600, color: color)),
            ),
            if (hint.isNotEmpty)
              Text(hint,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.row, required this.onTap});

  final _Row row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final net = row.net;
    final tone = net > 0
        ? Brand.receivable
        : (net < 0 ? Brand.payable : theme.colorScheme.primary);

    // Nomor telepon ada di halaman kontak; daftar hanya menandai jatuh tempo.
    var sub = '';
    Color? subColor;
    if (net != 0) {
      final due = row.nextDue;
      if (due != null) {
        sub = '${row.overdue ? 'Lewat tempo' : 'Tempo'} ${dateId(due)}';
        if (row.overdue) subColor = Brand.expense;
      }
    }

    return SoftCard(
      onTap: onTap,
      child: Row(children: [
        InitialAvatar(row.contact.name, color: tone),
        const SizedBox(width: 16),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.contact.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            if (sub.isNotEmpty)
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: subColor ?? muted,
                      fontWeight: subColor == null ? null : FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 12),
        if (net == 0)
          Text('Lunas',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: Brand.income, fontWeight: FontWeight.w600))
        else
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(rupiah(net.abs()),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600, color: tone)),
            Text(net > 0 ? 'piutang' : 'utang',
                style: theme.textTheme.labelSmall?.copyWith(color: muted)),
          ]),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, color: muted),
      ]),
    );
  }
}
