import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../common/amount_field.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../debts/contact_picker.dart';
import '../debts/debt_models.dart';
import '../debts/debt_repository.dart';
import '../theme/app_theme.dart';
import 'cash_models.dart';
import 'cash_repository.dart';

/// Lembar formulir catat transaksi.
///
/// * **Lunas**: kas langsung bertambah/berkurang.
/// * **Hutang**: kontak wajib; dicatat sebagai piutang (pemasukan) atau utang
///   (pengeluaran) dan kas baru berubah saat dibayar.
/// * **Penjualan** (kategori penjualan, atau pemasukan hutang yang ditandai
///   penjualan): ada Harga Modal, Diskon, Biaya Tambahan, dan info Keuntungan.
///
/// Mengembalikan true bila tersimpan.
Future<bool> showCashForm(
  BuildContext context, {
  required CashRepository repo,
  required DebtRepository debtRepo,
  required List<Category> categories,
  CashTx? existing,
  String initialType = 'in',
  bool lockType = false,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _CashForm(
      repo: repo,
      debtRepo: debtRepo,
      categories: categories.where((c) => !c.isSystem).toList(),
      existing: existing,
      initialType: existing?.type ?? initialType,
      lockType: lockType && existing == null,
    ),
  );
  return saved ?? false;
}

class _CashForm extends StatefulWidget {
  const _CashForm({
    required this.repo,
    required this.debtRepo,
    required this.categories,
    required this.existing,
    required this.initialType,
    required this.lockType,
  });

  final CashRepository repo;
  final DebtRepository debtRepo;
  final List<Category> categories;
  final CashTx? existing;
  final String initialType;

  /// Jenis (pemasukan/pengeluaran) sudah dipilih sebelumnya, jadi tidak ditanyakan lagi.
  final bool lockType;

  @override
  State<_CashForm> createState() => _CashFormState();
}

class _CashFormState extends State<_CashForm> {
  late String _type = widget.initialType;
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  late String? _categoryId = widget.existing?.categoryId;

  // Pada penjualan, kolom jumlah berarti "Total Penjualan" (sebelum diskon).
  late final _amount = TextEditingController(
      text: widget.existing == null
          ? ''
          : thousands(widget.existing!.isSale
              ? widget.existing!.saleTotal
              : widget.existing!.amount));
  late final _cost =
      TextEditingController(text: _prefill(widget.existing?.costAmount));
  late final _discount =
      TextEditingController(text: _prefill(widget.existing?.discountAmount));
  late final _fee =
      TextEditingController(text: _prefill(widget.existing?.extraFee));
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  final _contact = ContactPickerController();
  List<Contact> _contacts = [];
  int?
      _contactNet; // saldo bersih kontak terpilih: positif = berutang kepada Anda
  String? _netFor;
  bool _credit = false;

  /// Pemasukan = penjualan barang (ada harga modal dan keuntungan). Bawaannya aktif,
  /// baik Lunas maupun Hutang; matikan untuk pemasukan biasa.
  late bool _sale = widget.existing?.isSale ?? true;
  DateTime? _due;
  bool _busy = false;

  static String _prefill(int? v) => (v == null || v == 0) ? '' : thousands(v);

  bool get _isIn => _type == 'in';
  bool get _editing => widget.existing != null;
  Color get _tone => amountColor(_isIn);

  List<Category> get _options =>
      widget.categories.where((c) => c.type == _type).toList();

  /// Mode penjualan: ada harga modal, diskon, biaya tambahan, dan keuntungan.
  bool get _saleMode => _isIn && _sale;

  int get _gross => parseAmount(_amount.text) ?? 0;
  int get _costValue => parseAmount(_cost.text) ?? 0;
  int get _discountValue => parseAmount(_discount.text) ?? 0;
  int get _feeValue => parseAmount(_fee.text) ?? 0;

  /// Uang yang diterima = Total Penjualan - Diskon + Biaya Tambahan.
  int get _received => _gross - _discountValue + _feeValue;

  /// Keuntungan = Total Penjualan - Diskon - Harga Modal.
  int get _profit => _gross - _discountValue - _costValue;

  @override
  void initState() {
    super.initState();
    if (!_editing) _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final list = await widget.debtRepo.contacts();
      if (!mounted) return;
      setState(() {
        _contacts = list;
        // Belum ada kontak sama sekali: langsung arahkan ke tambah kontak baru.
        if (list.isEmpty && _contact.selected == null) _contact.selectNew();
      });
    } catch (_) {
      // Daftar kontak gagal dimuat; pilihan "kontak baru" tetap bisa dipakai.
    }
  }

  /// Memuat saldo bersih kontak terpilih untuk petunjuk kompensasi utang.
  Future<void> _refreshNet() async {
    final id = _contact.selected;
    if (id == null || _contact.isNew) {
      _netFor = null;
      if (_contactNet != null) setState(() => _contactNet = null);
      return;
    }
    if (id == _netFor) return;
    _netFor = id;
    try {
      final n = await widget.debtRepo.contactNet(id);
      if (!mounted || _netFor != id) return;
      setState(() => _contactNet = n);
    } catch (_) {
      // Petunjuk bersifat tambahan; gagal memuatnya tidak menghalangi penyimpanan.
    }
  }

  /// Jumlah yang otomatis dikompensasi bila hutang ini disimpan:
  /// piutang baru memotong utang Anda ke kontak, utang baru memotong piutang kontak.
  int get _offsetPreview {
    final n = _contactNet;
    final amount = _saleMode ? _received : _gross;
    if (!_credit || n == null || amount <= 0) return 0;
    if (_isIn && n < 0) return amount < -n ? amount : -n;
    if (!_isIn && n > 0) return amount < n ? amount : n;
    return 0;
  }

  @override
  void dispose() {
    _amount.dispose();
    _cost.dispose();
    _discount.dispose();
    _fee.dispose();
    _note.dispose();
    _contact.dispose();
    super.dispose();
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<DateTime?> _pick(DateTime initial, {DateTime? last}) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: last ?? DateTime.now().add(const Duration(days: 366 * 5)),
      );

  /// Pesan galat bila isian belum benar; null bila valid.
  String? _validate() {
    if (_gross <= 0) {
      return _saleMode
          ? 'Isi total penjualan lebih dari 0.'
          : 'Isi jumlah lebih dari 0.';
    }
    if (_saleMode) {
      if (_discountValue > _gross) {
        return 'Diskon tidak boleh melebihi total penjualan.';
      }
      if (_received <= 0) return 'Jumlah yang diterima harus lebih dari 0.';
    }
    if (_credit) return _contact.validate();
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      _toast(problem);
      return;
    }
    final sale = _saleMode
        ? SaleDetail(cost: _costValue, discount: _discountValue, fee: _feeValue)
        : null;
    final amount = _saleMode ? _received : _gross;

    // Penjualan tanpa kategori dipilih: otomatis masuk kategori Penjualan.
    var categoryId = _categoryId;
    if (_saleMode && !_credit && categoryId == null) {
      for (final c in _options) {
        if (c.isSale) {
          categoryId = c.id;
          break;
        }
      }
    }

    setState(() => _busy = true);
    try {
      if (_credit) {
        final contactId = await _contact.resolve(widget.debtRepo);
        await widget.debtRepo.create(
          contactId: contactId,
          kind: _isIn ? 'receivable' : 'payable',
          amount: amount,
          cashMoved: false,
          debtDate: _date,
          dueDate: _due,
          note: _note.text,
          sale: sale,
        );
        final off = _offsetPreview;
        final base =
            _isIn ? 'Dicatat sebagai piutang.' : 'Dicatat sebagai utang.';
        _toast(off > 0
            ? '$base ${rupiah(off)} otomatis dikompensasi dengan saldo kontak.'
            : '$base Lihat di tab Utang.');
      } else if (_editing) {
        await widget.repo.edit(widget.existing!.id,
            type: _type,
            amount: amount,
            date: _date,
            categoryId: categoryId,
            note: _note.text,
            sale: sale);
      } else {
        await widget.repo.add(
            type: _type,
            amount: amount,
            date: _date,
            categoryId: categoryId,
            note: _note.text,
            sale: sale);
      }
      if (mounted) Navigator.pop(context, true);
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
    final muted = theme.colorScheme.onSurfaceVariant;
    final sale = _saleMode;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.lockType)
              Row(children: [
                IconBadge(
                    _isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
                    color: _tone,
                    size: 40),
                const SizedBox(width: 12),
                Text(_isIn ? 'Catat pemasukan' : 'Catat pengeluaran',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ])
            else
              Row(children: [
                Expanded(
                    child: _TypeTile('Pemasukan', Icons.south_west_rounded,
                        true, _isIn, () => setState(() => _type = 'in'))),
                const SizedBox(width: 12),
                Expanded(
                    child: _TypeTile('Pengeluaran', Icons.north_east_rounded,
                        false, !_isIn, () => setState(() => _type = 'out'))),
              ]),
            if (!_editing) ...[
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: false,
                      icon: Icon(Icons.check_circle_outline_rounded),
                      label: Text('Lunas')),
                  ButtonSegment(
                      value: true,
                      icon: Icon(Icons.schedule_rounded),
                      label: Text('Hutang')),
                ],
                selected: {_credit},
                onSelectionChanged: (s) => setState(() => _credit = s.first),
              ),
            ],
            if (_isIn)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _sale,
                onChanged: (v) => setState(() => _sale = v),
                title: const Text('Penjualan barang'),
              ),
            if (sale) ...[
              const SizedBox(height: 8),
              _ProfitCard(profit: _profit),
            ],
            const SizedBox(height: 16),
            _AmountBox(
              controller: _amount,
              label: sale ? 'Total Penjualan' : 'Jumlah',
              color: _tone,
              autofocus: !_editing,
              onChanged: () => setState(() {}),
            ),
            if (sale) ...[
              const SizedBox(height: 12),
              _AmountBox(
                controller: _cost,
                label: 'Harga Modal',
                color: Brand.expense,
                large: false,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 4),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  initiallyExpanded: _discountValue > 0 || _feeValue > 0,
                  title: Text('Tambahan perhitungan (opsional)',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  children: [
                    _MoneyField(
                      controller: _discount,
                      label: 'Diskon',
                      color: Brand.expense,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    _MoneyField(
                      controller: _fee,
                      label: 'Biaya Tambahan',
                      color: theme.colorScheme.onSurface,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        _credit ? 'Total piutang' : 'Uang diterima (kas masuk)',
                        style:
                            theme.textTheme.bodyMedium?.copyWith(color: muted)),
                  ),
                  Text(rupiah(_received < 0 ? 0 : _received),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
            const SizedBox(height: 8),
            if (_credit) ...[
              ContactPicker(
                controller: _contact,
                contacts: _contacts,
                label: _isIn
                    ? 'Siapa yang berutang? (wajib)'
                    : 'Berutang kepada siapa? (wajib)',
                onChanged: () {
                  setState(() {});
                  _refreshNet();
                },
              ),
              if (_contactNet != null &&
                  ((_isIn && _contactNet! < 0) || (!_isIn && _contactNet! > 0)))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Brand.profit.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.swap_horiz_rounded,
                          size: 20, color: Brand.profit),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _isIn
                              ? 'Utang Anda ke kontak ini ${rupiah(-_contactNet!)} akan berkurang otomatis.'
                              : 'Piutang kontak ini ${rupiah(_contactNet!)} akan berkurang otomatis.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ]),
                  ),
                ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final d = await _pick(_due ?? _date);
                  if (d != null) setState(() => _due = d);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Jatuh tempo (opsional)',
                    prefixIcon: const Icon(Icons.alarm_rounded),
                    suffixIcon: _due == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _due = null)),
                  ),
                  child: Text(_due == null ? '-' : dateId(_due!)),
                ),
              ),
            ] else ...[
              Text('Kategori', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in _options)
                  ChoiceChip(
                    label: Text(c.name),
                    avatar: Icon(categoryIcon(c.name, income: _isIn), size: 18),
                    selected: _categoryId == c.id,
                    onSelected: (s) =>
                        setState(() => _categoryId = s ? c.id : null),
                  ),
              ]),
            ],
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                final d = await _pick(_date,
                    last: DateTime.now().add(const Duration(days: 366)));
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
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: _tone),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : Text(_editing
                      ? 'Simpan perubahan'
                      : (_credit ? 'Simpan sebagai hutang' : 'Simpan')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Info keuntungan penjualan, tampil di atas isian.
class _ProfitCard extends StatelessWidget {
  const _ProfitCard({required this.profit});

  final int profit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positive = profit >= 0;
    final color = positive ? Brand.income : Brand.expense;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        IconBadge(
            positive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            color: color,
            size: 40),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(positive ? 'Keuntungan' : 'Rugi',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Text(rupiah(profit.abs()),
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      ]),
    );
  }
}

/// Kolom nominal yang tegas: label di atas, kotak berbingkai warna, angka besar.
/// Dipakai untuk Jumlah / Total Penjualan dan Harga Modal.
class _AmountBox extends StatelessWidget {
  const _AmountBox({
    required this.controller,
    required this.label,
    required this.color,
    required this.onChanged,
    this.large = true,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final Color color;
  final VoidCallback onChanged;

  /// Kolom utama berangka besar; kolom pendamping lebih kecil.
  final bool large;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    OutlineInputBorder border(double width, Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: width),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(label,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.onSurface)),
      ),
      AmountField(
        controller: controller,
        autofocus: autofocus,
        title: label,
        onChanged: onChanged,
        style: (large
                ? theme.textTheme.headlineMedium
                : theme.textTheme.titleLarge)
            ?.copyWith(fontWeight: FontWeight.w600, color: color),
        decoration: InputDecoration(
          hintText: '0',
          prefixText: 'Rp ',
          prefixStyle: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600, color: color),
          contentPadding:
              EdgeInsets.symmetric(horizontal: 16, vertical: large ? 20 : 16),
          enabledBorder: border(1.6, color.withValues(alpha: 0.55)),
          focusedBorder: border(2.2, color),
        ),
      ),
    ]);
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    required this.color,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final Color color;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return AmountField(
      controller: controller,
      title: label,
      onChanged: onChanged,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w600, color: color),
      decoration: InputDecoration(
        labelText: label,
        hintText: '0',
        prefixText: 'Rp ',
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile(
      this.label, this.icon, this.income, this.selected, this.onTap);

  final String label;
  final IconData icon;
  final bool income;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = amountColor(income);
    return Material(
      color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: selected
                ? color
                : Theme.of(context).dividerTheme.color ?? Colors.grey,
            width: selected ? 1.6 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? color
                        : Theme.of(context).colorScheme.onSurface)),
          ]),
        ),
      ),
    );
  }
}
