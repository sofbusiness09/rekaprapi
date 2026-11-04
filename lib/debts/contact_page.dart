import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../business/business.dart';
import '../common/amount_field.dart';
import '../common/dialogs.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../theme/app_theme.dart';
import 'contact_form.dart';
import 'debt_detail_page.dart';
import 'debt_models.dart';
import 'debt_repository.dart';
import '../common/glass.dart';

/// Halaman satu kontak: data kontak yang bisa diubah (telepon, alamat, catatan),
/// saldo bersih (piutang dan utang digabung), tombol **Lunaskan** dan
/// **Catat manual** (terima / berikan uang), serta riwayatnya.
class ContactPage extends StatefulWidget {
  const ContactPage({
    super.key,
    required this.business,
    required this.repo,
    required this.contact,
    required this.changes,
  });

  final Business business;
  final DebtRepository repo;
  final Contact contact;
  final ValueNotifier<int> changes;

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  late Contact _contact = widget.contact;
  late Future<Ledger> _future = widget.repo.ledger(_contact.id);

  @override
  void initState() {
    super.initState();
    widget.changes.addListener(_reload);
  }

  @override
  void dispose() {
    widget.changes.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _future = widget.repo.ledger(_contact.id);
      });
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      widget.changes.value++;
      _toast(done);
    } on PostgrestException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Gagal: $e');
    }
  }

  Future<void> _edit() async {
    final updated =
        await showContactForm(context, repo: widget.repo, existing: _contact);
    if (updated == null) return;
    setState(() => _contact = updated);
    widget.changes.value++;
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'Hapus kontak?',
        body:
            '${_contact.name} akan dihapus dari daftar kontak. Riwayat transaksi lamanya tetap tersimpan.',
        okLabel: 'Hapus');
    if (!ok) return;
    try {
      await widget.repo.deleteContact(_contact.id);
      widget.changes.value++;
      if (mounted) Navigator.pop(context);
    } on PostgrestException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Gagal: $e');
    }
  }

  Future<void> _settle(Ledger l) async {
    final net = l.net;
    final ok = await confirmDialog(
      context,
      title: 'Lunaskan?',
      body: net > 0
          ? '${_contact.name} membayar ${rupiah(net)}. Kas masuk otomatis tercatat.'
          : 'Anda membayar/mengembalikan ${rupiah(-net)} kepada ${_contact.name}. Kas keluar otomatis tercatat.',
      okLabel: 'Lunaskan',
    );
    if (!ok) return;
    await _run(
      () => widget.repo.settle(_contact.id, paidOn: DateTime.now()),
      'Lunas.',
    );
  }

  Future<void> _manual(Ledger l) async {
    final net = l.net;
    final choice = await showGlassSheet<bool>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading:
                const IconBadge(Icons.south_west_rounded, color: Brand.income),
            title: Text(_receiveTitle(net)),
            subtitle: Text(net > 0
                ? 'Melunasi piutang dari yang terlama. Kelebihannya menjadi utang Anda kepada ${_contact.name}.'
                : 'Uang masuk dari ${_contact.name}, dicatat sebagai utang/modal (Anda berutang kepadanya).'),
            onTap: () => Navigator.pop(context, true),
          ),
          ListTile(
            leading:
                const IconBadge(Icons.north_east_rounded, color: Brand.expense),
            title: Text(_giveTitle(net)),
            subtitle: Text(net < 0
                ? 'Membayar utang dari yang terlama. Kelebihannya menjadi piutang (Anda memberi hutang).'
                : 'Uang keluar untuk ${_contact.name}, dicatat sebagai piutang (Anda memberi hutang). Di luar penjualan.'),
            onTap: () => Navigator.pop(context, false),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;

    final r = await showGlassSheet<_MoneyResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) =>
          _MoneySheet(receive: choice, net: net, contactName: _contact.name),
    );
    if (r == null) return;
    await _run(
      () => widget.repo.transfer(_contact.id,
          receive: choice, amount: r.amount, paidOn: r.date, note: r.note),
      choice ? 'Uang masuk dicatat.' : 'Uang keluar dicatat.',
    );
  }

  static String _receiveTitle(int net) =>
      net > 0 ? 'Terima pembayaran' : 'Terima utang / modal';

  static String _giveTitle(int net) =>
      net < 0 ? 'Bayar utang' : 'Berikan hutang';

  Future<void> _openDebt(Debt d) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DebtDetailPage(
        business: widget.business,
        repo: widget.repo,
        debtId: d.id,
        contactName: _contact.name,
        changes: widget.changes,
      ),
    ));
    _reload();
  }

  String _label(LedgerEntry e) {
    if (e.isOffset) return 'Dikompensasi';
    if (e.isPayment) {
      return e.parent!.isReceivable ? 'Pembayaran diterima' : 'Utang dibayar';
    }
    final d = e.debt!;
    if (d.isReceivable) {
      if (d.isSale) return 'Penjualan';
      return d.cashMoved ? 'Pemberian hutang' : 'Transaksi';
    }
    return d.cashMoved ? 'Utang diterima (modal)' : 'Pembelian kredit';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          InitialAvatar(_contact.name, size: 38),
          const SizedBox(width: 12),
          Flexible(
            child: Text(_contact.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
        actions: [
          IconButton(
              tooltip: 'Ubah kontak',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit),
          if (widget.business.canManage)
            IconButton(
                tooltip: 'Hapus kontak',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _delete),
        ],
      ),
      // Dibangun ulang bersama data: sebelumnya tombol dibuat saat data belum ada
      // sehingga tetap mati walau data sudah tampil.
      floatingActionButton: FutureBuilder<Ledger>(
        future: _future,
        builder: (context, snap) => FloatingActionButton.extended(
          onPressed: snap.hasData ? () => _manual(snap.data!) : null,
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('Catat manual'),
        ),
      ),
      body: FutureBuilder<Ledger>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Gagal memuat: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final l = snap.data!;
          final net = l.net;
          final muted = theme.colorScheme.onSurfaceVariant;
          final entries = l.entries;

          final Color tone;
          final String balanceLabel;
          final String balanceHint;
          if (net > 0) {
            tone = Brand.receivable;
            balanceLabel = 'Piutang';
            balanceHint = '${_contact.name} berutang kepada Anda';
          } else if (net < 0) {
            tone = Brand.payable;
            balanceLabel = 'Utang';
            balanceHint = 'Anda berutang kepada ${_contact.name}';
          } else {
            tone = Brand.income;
            balanceLabel = 'Saldo';
            balanceHint = 'Tidak ada utang piutang';
          }

          return ContentWidth(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
              children: [
                _ProfileCard(contact: _contact, onEdit: _edit),
                const SizedBox(height: 12),
                SoftCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(balanceLabel,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(color: muted)),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                        net == 0 ? 'Lunas' : rupiah(net.abs()),
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: tone)),
                                  ),
                                  Text(balanceHint,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: muted)),
                                ]),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(120, 48),
                              foregroundColor: Brand.income,
                              side: const BorderSide(
                                  color: Brand.income, width: 1.4),
                            ),
                            onPressed: net != 0 ? () => _settle(l) : null,
                            child: const Text('LUNASKAN'),
                          ),
                        ]),
                      ]),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(children: [
                    Expanded(
                        child: Text('Tanggal',
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: muted))),
                    SizedBox(
                      width: 104,
                      child: Text('Menerima',
                          textAlign: TextAlign.right,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: muted)),
                    ),
                    SizedBox(
                      width: 104,
                      child: Text('Memberi',
                          textAlign: TextAlign.right,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: muted)),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                if (entries.isEmpty)
                  const EmptyState(
                    icon: Icons.history_rounded,
                    title: 'Belum ada catatan',
                    subtitle:
                        'Catatan muncul saat ada transaksi hutang atau uang yang diterima/diberikan.',
                  ),
                for (final e in entries) ...[
                  _EntryTile(
                    entry: e,
                    label: _label(e),
                    onTap: () => _openDebt(e.isPayment ? e.parent! : e.debt!),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Data kontak: telepon (bisa disalin), alamat, catatan.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.contact, required this.onEdit});

  final Contact contact;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final empty = contact.phone == null &&
        contact.address == null &&
        contact.note == null;

    Widget line(IconData icon, String text, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(icon, size: 20, color: muted),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            if (trailing != null) trailing,
          ]),
        );

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: empty
          ? Row(children: [
              Expanded(
                child: Text('Belum ada nomor telepon atau alamat.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
              ),
              TextButton(onPressed: onEdit, child: const Text('Lengkapi')),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (contact.phone != null)
                line(
                  Icons.phone_outlined,
                  contact.phone!,
                  trailing: IconButton(
                    tooltip: 'Salin nomor',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(
                          ClipboardData(text: contact.phone!));
                      messenger.showSnackBar(
                          const SnackBar(content: Text('Nomor disalin.')));
                    },
                  ),
                ),
              if (contact.address != null)
                line(Icons.location_on_outlined, contact.address!),
              if (contact.note != null)
                line(Icons.notes_rounded, contact.note!),
            ]),
    );
  }
}

/// Satu baris riwayat. Kolom "Menerima" dan "Memberi" dilihat dari sisi Anda.
/// Kompensasi (utang dan piutang saling mengurangi) bukan uang berpindah, jadi tampil abu-abu.
class _EntryTile extends StatelessWidget {
  const _EntryTile(
      {required this.entry, required this.label, required this.onTap});

  final LedgerEntry entry;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final debt = entry.debt;
    final offset = entry.isOffset;

    final receiving = entry.receiving;
    final color = offset ? muted : (receiving ? Brand.income : Brand.expense);

    String? status;
    Color? statusColor;
    if (debt != null) {
      if (debt.settled) {
        status = 'Lunas';
        statusColor = Brand.income;
      } else {
        status =
            debt.paid > 0 ? 'Sisa ${rupiah(debt.remaining)}' : 'Belum lunas';
        statusColor = debt.overdue ? Brand.expense : Brand.pending;
      }
    }
    final note = entry.isPayment ? entry.payment!.note : debt!.note;

    final amount = Text(rupiah(entry.amount),
        textAlign: TextAlign.right,
        style: theme.textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w600, color: color));

    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(dateId(entry.date),
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            const SizedBox(height: 2),
            Text(label,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            if (status != null)
              Text(status,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: statusColor, fontWeight: FontWeight.w600)),
            if (note != null)
              Text(note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ]),
        ),
        SizedBox(width: 104, child: receiving ? amount : null),
        SizedBox(width: 104, child: receiving ? null : amount),
      ]),
    );
  }
}

class _MoneyResult {
  const _MoneyResult(this.amount, this.date, this.note);
  final int amount;
  final DateTime date;
  final String? note;
}

/// Lembar uang yang berpindah: terima atau berikan. Menjelaskan dampaknya pada saldo
/// sebelum disimpan (melunasi, sebagian, atau menjadi utang/piutang baru).
class _MoneySheet extends StatefulWidget {
  const _MoneySheet(
      {required this.receive, required this.net, required this.contactName});

  final bool receive;

  /// Saldo bersih saat ini: positif = kontak berutang kepada Anda.
  final int net;
  final String contactName;

  @override
  State<_MoneySheet> createState() => _MoneySheetState();
}

class _MoneySheetState extends State<_MoneySheet> {
  // Kosong: pengguna mengetik sendiri. Sisa saldo bisa diisi lewat tombol di bawah kolom.
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();

  /// Jumlah yang menutup saldo bila arahnya sesuai (terima saat ia berutang, dst.).
  int get _settleable {
    if (widget.receive) return widget.net > 0 ? widget.net : 0;
    return widget.net < 0 ? -widget.net : 0;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _value => parseAmount(_amount.text) ?? 0;

  /// Penjelasan dampak jumlah yang diketik terhadap saldo.
  String _effect() {
    final v = _value;
    final s = _settleable;
    if (v <= 0) return ' ';
    if (widget.receive) {
      if (s == 0) {
        return 'Dicatat sebagai utang/modal ${rupiah(v)}. Anda berutang ${rupiah(v)} kepada ${widget.contactName}.';
      }
      if (v < s) return 'Piutang berkurang. Sisa piutang ${rupiah(s - v)}.';
      if (v == s) return 'Piutang lunas.';
      return 'Piutang lunas, kelebihan ${rupiah(v - s)} menjadi utang Anda kepada ${widget.contactName}.';
    }
    if (s == 0) {
      return 'Dicatat sebagai piutang ${rupiah(v)}. ${widget.contactName} berutang ${rupiah(v)} kepada Anda.';
    }
    if (v < s) return 'Utang berkurang. Sisa utang ${rupiah(s - v)}.';
    if (v == s) return 'Utang lunas.';
    return 'Utang lunas, kelebihan ${rupiah(v - s)} menjadi piutang.';
  }

  String get _title {
    if (widget.receive)
      return widget.net > 0 ? 'Terima pembayaran' : 'Terima utang / modal';
    return widget.net < 0 ? 'Bayar utang' : 'Berikan hutang';
  }

  void _submit() {
    final v = _value;
    if (v <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Isi jumlah lebih dari 0.')));
      return;
    }
    final note = _note.text.trim();
    Navigator.pop(context, _MoneyResult(v, _date, note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final color = widget.receive ? Brand.income : Brand.expense;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_title,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              widget.receive
                  ? 'Kas masuk otomatis tercatat.'
                  : 'Kas keluar otomatis tercatat.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 16),
            AmountField(
              controller: _amount,
              autofocus: true,
              title: _title,
              textAlign: TextAlign.center,
              onChanged: () => setState(() {}),
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w600, color: color),
              decoration: const InputDecoration(
                hintText: '0',
                prefixText: 'Rp ',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
            if (_settleable > 0)
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () => setState(() {
                    _amount.text = thousands(_settleable);
                  }),
                  child: Text('Isi sesuai total (${rupiah(_settleable)})'),
                ),
              ),
            Text(_effect(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 366)),
                );
                if (d != null) setState(() => _date = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Tanggal',
                  prefixIcon: Icon(Icons.event_rounded),
                ),
                child: Text(dateId(_date)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(backgroundColor: color),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}
