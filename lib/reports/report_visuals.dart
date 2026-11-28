import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../cash/cash_models.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../debts/debt_models.dart';
import '../theme/app_theme.dart';
import 'package:rekap_rapi/l10n/l10n.dart';

/// Warna kategori. Hijau dan merah sengaja tidak dipakai agar tidak tertukar dengan
/// arti pemasukan dan pengeluaran.
const categoryPalette = <Color>[
  Color(0xFFD85A30), // oranye bata
  Color(0xFF7F77DD), // ungu
  Color(0xFF378ADD), // biru
  Color(0xFFEF9F27), // kuning
  Color(0xFF1D9E9E), // toska
  Color(0xFFD4537E), // merah muda
  Color(0xFF5C6BC0), // nila
  Color(0xFF8D6E63), // cokelat
  Color(0xFF00ACC1), // sian
  Color(0xFFA4A02A), // zaitun
];

/// Abu untuk gabungan "kategori lainnya".
const otherCategoryColor = Color(0xFFA8A6A0);

/// Warna pilihan sebuah kategori (indeks di [categoryPalette]): kategori umum punya
/// warna sendiri, kategori buatan pengguna mendapat warna dari namanya.
int categoryColorIndex(String name) {
  final n = name.toLowerCase();
  const byKeyword = <String, int>{
    'stok': 0,
    'beli': 0,
    'gaji': 1,
    'sewa': 2,
    'listrik': 3,
    'air': 3,
    'transport': 4,
    'bbm': 4,
    'bensin': 4,
    'makan': 5,
    'jual': 8,
    'belanja': 6,
    'tabung': 9,
  };
  for (final e in byKeyword.entries) {
    if (n.contains(e.key)) return e.value;
  }
  var h = 0;
  for (final c in n.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h % categoryPalette.length;
}

Color categoryColor(String name) => categoryPalette[categoryColorIndex(name)];

/// Warna untuk kategori yang tampil bersama, urut dari yang terbesar. Tiap kategori
/// memakai warna pilihannya; bila sudah dipakai kategori yang lebih besar, warna
/// berikutnya yang belum terpakai. Jadi tidak ada dua kategori berwarna sama
/// (hingga sepuluh kategori).
List<Color> distinctCategoryColors(List<String> names) {
  final used = <int>{};
  final out = <Color>[];
  for (final name in names) {
    var i = categoryColorIndex(name);
    if (used.length < categoryPalette.length) {
      while (used.contains(i)) {
        i = (i + 1) % categoryPalette.length;
      }
    }
    used.add(i);
    out.add(categoryPalette[i]);
  }
  return out;
}

/// Latar lembut sewarna kategori, untuk lingkaran ikon.
Color softTint(BuildContext context, Color c) => c.withValues(
    alpha: Theme.of(context).brightness == Brightness.dark ? 0.28 : 0.16);

/// Naik/turun dibanding periode lalu. Null bila tidak bisa dibandingkan.
String? changeLabel(int now, int? before) {
  if (before == null) return null;
  if (before <= 0) return now > 0 ? tr('Baru') : null;
  final pct = ((now - before) * 100 / before).round();
  if (pct == 0) return '0%';
  return '${pct > 0 ? '▲' : '▼'} ${pct.abs()}%';
}

/// Rincian per kategori: donat yang bisa diketuk, ikon berwarna, batang porsi, dan
/// perubahan dari periode lalu. Pengeluaran di kiri, pemasukan di kanan.
class CategoryBreakdown extends StatefulWidget {
  const CategoryBreakdown({
    super.key,
    required this.rows,
    required this.income,
    required this.onToggle,
    this.previous,
  });

  final List<Map<String, dynamic>> rows;
  final bool income;
  final ValueChanged<bool> onToggle;

  /// Baris periode sebelumnya, untuk tanda naik/turun (null: tanpa perbandingan).
  final List<Map<String, dynamic>>? previous;

  @override
  State<CategoryBreakdown> createState() => _CategoryBreakdownState();
}

class _Slice {
  _Slice(this.name, this.total, this.color, {this.before, this.others = 0});
  final String name;
  final int total;
  Color color;
  final int? before;

  /// Jumlah kategori yang digabung (0: kategori biasa).
  final int others;
}

class _CategoryBreakdownState extends State<CategoryBreakdown> {
  static const _shown = 5;

  /// Irisan yang dipilih; null: total.
  int? _selected = 0;
  bool _expanded = false;

  @override
  void didUpdateWidget(CategoryBreakdown old) {
    super.didUpdateWidget(old);
    if (old.income != widget.income || old.rows != widget.rows) {
      _selected = 0;
      _picked = false;
      _expanded = false;
    }
  }

  /// Pengguna sudah mengetuk irisan atau baris.
  bool _picked = false;

  void _select(int i) => setState(() {
        _picked = true;
        _selected = _selected == i ? null : i;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final type = widget.income ? 'in' : 'out';
    final before = <String, int>{
      for (final r in widget.previous ?? const <Map<String, dynamic>>[])
        if (r['type'] == type)
          r['category_name'] as String: (r['total'] as num).toInt(),
    };
    final all = [
      for (final r in widget.rows)
        if (r['type'] == type && (r['total'] as num) > 0)
          _Slice(
            r['category_name'] as String,
            (r['total'] as num).toInt(),
            categoryColor(r['category_name'] as String),
            before: widget.previous == null
                ? null
                : before[r['category_name'] as String] ?? 0,
          ),
    ]..sort((a, b) => b.total.compareTo(a.total));
    // Kategori yang tampil bersama tidak pernah berwarna sama.
    final colors = distinctCategoryColors([for (final s in all) s.name]);
    for (var i = 0; i < all.length; i++) {
      all[i].color = colors[i];
    }
    final total = all.fold<int>(0, (s, r) => s + r.total);

    // Banyak kategori: lima terbesar, sisanya digabung agar donat tidak penuh irisan tipis.
    final grouped = all.length > _shown + 1;
    final rest = grouped ? all.sublist(_shown) : const <_Slice>[];
    final slices = grouped
        ? [
            ...all.take(_shown),
            _Slice(tr('Lainnya'), rest.fold(0, (s, r) => s + r.total),
                otherCategoryColor,
                others: rest.length),
          ]
        : all;
    final sel = _selected != null && _selected! < slices.length
        ? slices[_selected!]
        : null;
    final tone = widget.income ? Brand.income : Brand.expense;

    String pct(int v) => '${total == 0 ? 0 : (v * 100 / total).round()}%';

    Widget row(_Slice s, {int? index, bool nested = false}) {
      final change = changeLabel(s.total, s.before);
      // Pengeluaran naik = merah; pemasukan naik = hijau.
      final up = s.before != null && s.total > s.before!;
      final good = widget.income ? up : !up;
      final active = index != null && _selected == index;
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: index == null
            ? null
            : s.others > 0
                ? () => setState(() => _expanded = !_expanded)
                : () => _select(index),
        child: Container(
          padding: EdgeInsets.fromLTRB(nested ? 12 : 6, 7, 6, 7),
          decoration: BoxDecoration(
            color: active ? softTint(context, s.color) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Container(
              width: nested ? 26 : 32,
              height: nested ? 26 : 32,
              decoration: BoxDecoration(
                  color: softTint(context, s.color), shape: BoxShape.circle),
              child: Icon(
                  s.others > 0
                      ? Icons.more_horiz_rounded
                      : categoryIcon(s.name, income: widget.income),
                  size: nested ? 15 : 18,
                  color: s.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                            s.others > 0
                                ? tr('{0} kategori lainnya', [s.others])
                                : tr(s.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium),
                      ),
                      if (change != null && s.others == 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(change,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: change == '0%'
                                      ? muted
                                      : (good ? Brand.income : Brand.expense))),
                        ),
                      const SizedBox(width: 8),
                      Text(rupiah(s.total),
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 5),
                    Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: total == 0 ? 0 : s.total / total,
                            minHeight: 5,
                            color: s.color,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(pct(s.total),
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: muted)),
                      ),
                    ]),
                  ]),
            ),
            if (s.others > 0)
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  color: muted),
          ]),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: tone.withValues(alpha: 0.16),
          selectedForegroundColor: tone,
        ),
        segments: [
          ButtonSegment(value: false, label: Text(tr('Pengeluaran'))),
          ButtonSegment(value: true, label: Text(tr('Pemasukan'))),
        ],
        selected: {widget.income},
        onSelectionChanged: (s) => widget.onToggle(s.first),
      ),
      const SizedBox(height: 16),
      if (all.isEmpty)
        EmptyState(icon: Icons.pie_chart_rounded, title: tr('Belum ada data'))
      else ...[
        SizedBox(
          height: 210,
          child: Stack(alignment: Alignment.center, children: [
            PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 66,
                // Irisan pertama (terbesar) mulai dari atas, searah jarum jam.
                startDegreeOffset: -90,
                pieTouchData: PieTouchData(
                  touchCallback: (event, res) {
                    if (event is! FlTapUpEvent) return;
                    final i = res?.touchedSection?.touchedSectionIndex ?? -1;
                    if (i >= 0) _select(i);
                  },
                ),
                sections: [
                  for (var i = 0; i < slices.length; i++)
                    PieChartSectionData(
                      value: slices[i].total.toDouble(),
                      // Irisan lain meredup hanya setelah pengguna memilih.
                      color: !_picked || sel == null || _selected == i
                          ? slices[i].color
                          : slices[i].color.withValues(alpha: 0.35),
                      radius: _selected == i ? 34 : 28,
                      showTitle: false,
                    ),
                ],
              ),
            ),
            IgnorePointer(
              child: SizedBox(
                width: 118,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                      sel == null
                          ? tr('Total')
                          : sel.others > 0
                              ? tr('Lainnya')
                              : tr(sel.name),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: sel?.color ?? muted,
                          fontWeight: FontWeight.w600)),
                  if (sel != null)
                    Text(pct(sel.total),
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(rupiah(sel?.total ?? total),
                        style: (sel == null
                                ? theme.textTheme.titleMedium
                                : theme.textTheme.labelMedium)
                            ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: sel == null ? null : muted)),
                  ),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < slices.length; i++) ...[
          row(slices[i], index: i),
          if (slices[i].others > 0 && _expanded)
            for (final r in rest) row(r, nested: true),
        ],
      ],
    ]);
  }
}

/// Kalender pengeluaran satu bulan: makin pekat, makin besar pengeluaran hari itu.
/// Bila periode lebih dari satu bulan, tombol ‹ › berpindah antarbulan dalam periode.
class SpendingCalendar extends StatefulWidget {
  const SpendingCalendar({
    super.key,
    required this.points,
    required this.month,
    this.from,
    this.to,
  });

  final List<DailyPoint> points;

  /// Hari mana pun di bulan yang ditampilkan lebih dulu.
  final DateTime month;

  /// Batas periode untuk tombol pindah bulan (null: hanya [month]).
  final DateTime? from;
  final DateTime? to;

  @override
  State<SpendingCalendar> createState() => _SpendingCalendarState();
}

class _SpendingCalendarState extends State<SpendingCalendar> {
  DateTime? _picked;
  late DateTime _month = _monthOf(widget.month);

  static DateTime _monthOf(DateTime d) => DateTime(d.year, d.month);

  @override
  void didUpdateWidget(SpendingCalendar old) {
    super.didUpdateWidget(old);
    if (old.month != widget.month ||
        old.from != widget.from ||
        old.to != widget.to) {
      _month = _monthOf(widget.month);
      _picked = null;
    }
  }

  void _shift(int by) => setState(() {
        _month = DateTime(_month.year, _month.month + by);
        _picked = null;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final first = _month;
    final minMonth = _monthOf(widget.from ?? widget.month);
    final maxMonth = _monthOf(widget.to ?? widget.month);
    final canBack = first.isAfter(minMonth);
    final canNext = first.isBefore(maxMonth);
    final days = DateTime(first.year, first.month + 1, 0).day;
    final spend = <int, int>{
      for (final p in widget.points)
        if (p.day.year == first.year && p.day.month == first.month)
          p.day.day: p.cashOut,
    };
    final peak = spend.values.fold<int>(0, math.max);
    final now = DateTime.now();
    final today =
        now.year == first.year && now.month == first.month ? now.day : null;
    final lead = first.weekday - 1; // Senin di kolom pertama
    final weekdays = [
      tr('Sen'),
      tr('Sel'),
      tr('Rab'),
      tr('Kam'),
      tr('Jum'),
      tr('Sab'),
      tr('Min'),
    ];
    final active = spend.values.where((v) => v > 0).toList();
    final avg = active.isEmpty
        ? 0
        : active.fold<int>(0, (s, v) => s + v) ~/ active.length;
    final picked = _picked;
    final cells = lead + days;

    final calendar =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (canBack || canNext)
        Row(children: [
          IconButton(
            tooltip: tr('Bulan sebelumnya'),
            onPressed: canBack ? () => _shift(-1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(monthId(first),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          IconButton(
            tooltip: tr('Bulan berikutnya'),
            onPressed: canNext ? () => _shift(1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ]),
      Row(children: [
        for (final w in weekdays)
          Expanded(
            child: Text(w,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(color: muted)),
          ),
      ]),
      const SizedBox(height: 6),
      for (var week = 0; week * 7 < cells; week++)
        Row(children: [
          for (var col = 0; col < 7; col++)
            Expanded(
              child: Builder(builder: (context) {
                final day = week * 7 + col - lead + 1;
                if (day < 1 || day > days) {
                  return const AspectRatio(aspectRatio: 1, child: SizedBox());
                }
                final v = spend[day] ?? 0;
                // Sedikit dilengkungkan agar hari kecil tetap terlihat, tetapi hari
                // boros tetap jauh lebih pekat.
                final t = peak == 0 ? 0.0 : math.pow(v / peak, 0.8).toDouble();
                final date = DateTime(first.year, first.month, day);
                final isPicked = picked != null && picked.day == day;
                final strong = t > 0.55;
                return Padding(
                  padding: const EdgeInsets.all(2),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Material(
                      color: v == 0
                          ? theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.6)
                          : Brand.expense.withValues(alpha: 0.08 + 0.87 * t),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: isPicked || day == today
                            ? BorderSide(
                                color: isPicked
                                    ? theme.colorScheme.onSurface
                                    : Brand.expense,
                                width: 1.6)
                            : BorderSide.none,
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () =>
                            setState(() => _picked = isPicked ? null : date),
                        child: Center(
                          child: Text('$day',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: strong ? Colors.white : null)),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
        ]),
      const SizedBox(height: 10),
      Text(
        picked != null
            ? tr('{0}: {1}', [dateId(picked), rupiah(spend[picked.day] ?? 0)])
            : tr('Rata-rata {0} per hari berbelanja', [rupiah(avg)]),
        style: theme.textTheme.bodySmall?.copyWith(color: muted),
      ),
    ]);
    // Di layar lebar kalender tidak melebar sampai kotak tanggal raksasa.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: calendar,
      ),
    );
  }
}

/// Sisa utang atau piutang menurut jatuh tempo.
class DueBuckets {
  int overdue = 0;
  int thisWeek = 0;
  int later = 0;
  int noDate = 0;

  int get total => overdue + thisWeek + later + noDate;

  static DueBuckets of(Iterable<Debt> debts, {DateTime? now}) {
    final b = DueBuckets();
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    for (final d in debts) {
      if (d.settled) continue;
      final due = d.dueDate;
      if (due == null) {
        b.noDate += d.remaining;
      } else {
        final day = DateTime(due.year, due.month, due.day);
        if (day.isBefore(today)) {
          b.overdue += d.remaining;
        } else if (day.difference(today).inDays < 7) {
          b.thisWeek += d.remaining;
        } else {
          b.later += d.remaining;
        }
      }
    }
    return b;
  }
}

/// Batang bertingkat piutang dan utang: lewat jatuh tempo, minggu ini, nanti, tanpa
/// tanggal.
class DueDebtsCard extends StatelessWidget {
  const DueDebtsCard({super.key, required this.debts});

  final List<Debt> debts;

  static const _soon = Color(0xFFEF9F27);
  static const _later = Color(0xFF378ADD);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final receivable = DueBuckets.of(debts.where((d) => d.isReceivable));
    final payable = DueBuckets.of(debts.where((d) => !d.isReceivable));
    final parts = <(String, Color, int Function(DueBuckets))>[
      (tr('Lewat jatuh tempo'), Brand.expense, (b) => b.overdue),
      (tr('7 hari ke depan'), _soon, (b) => b.thisWeek),
      (tr('Nanti'), _later, (b) => b.later),
      (tr('Tanpa tanggal'), otherCategoryColor, (b) => b.noDate),
    ];

    Widget bar(String title, DueBuckets b) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600))),
            Text(rupiah(b.total),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: b.total == 0
                  ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
                  : Row(children: [
                      for (final p in parts)
                        if (p.$3(b) > 0)
                          Expanded(
                            // Bagian kecil tetap terlihat.
                            flex: math.max(1, p.$3(b) * 1000 ~/ b.total),
                            child: Container(
                              margin: const EdgeInsets.only(right: 2),
                              color: p.$2,
                            ),
                          ),
                    ]),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 14, runSpacing: 2, children: [
            for (final p in parts)
              if (p.$3(b) > 0)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: p.$2, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('${p.$1} ${rupiah(p.$3(b))}',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: p.$2 == Brand.expense ? Brand.expense : muted,
                          fontWeight:
                              p.$2 == Brand.expense ? FontWeight.w600 : null)),
                ]),
          ]),
        ]),
      );
    }

    if (receivable.total == 0 && payable.total == 0) {
      return EmptyState(
          icon: Icons.event_available_rounded,
          title: tr('Tidak ada utang atau piutang yang belum lunas'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (receivable.total > 0)
        bar(tr('Piutang (uang yang akan masuk)'), receivable),
      if (payable.total > 0)
        bar(tr('Utang (uang yang harus dibayar)'), payable),
    ]);
  }
}
