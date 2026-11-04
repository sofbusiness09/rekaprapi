import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../backup/backup_card.dart';
import '../business/business.dart';
import '../cash/cash_models.dart';
import '../cash/cash_repository.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../debts/debt_repository.dart';
import '../theme/app_theme.dart';
import 'report_exporter.dart';

enum _Preset { thisMonth, lastMonth, thisYear, custom }

/// Irisan terbesar memakai aksen merek; sisanya abu bertingkat agar tidak seperti pelangi.
const _palette = <Color>[
  Color(0xFF0E9F6E),
  Color(0xFF3D4A44),
  Color(0xFF66736D),
  Color(0xFF8E9A94),
  Color(0xFFB0BAB5),
  Color(0xFFCBD2CE),
  Color(0xFFDDE2DF),
  Color(0xFFEBEEEC),
];

class ReportPage extends StatefulWidget {
  const ReportPage({
    super.key,
    required this.business,
    required this.cash,
    required this.debts,
    required this.changes,
  });

  final Business business;
  final CashRepository cash;
  final DebtRepository debts;
  final ValueNotifier<int> changes;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _Loaded {
  _Loaded(this.summary, this.daily, this.byCategory);
  final Summary summary;
  final List<DailyPoint> daily;
  final List<Map<String, dynamic>> byCategory;
}

/// Satu batang/titik grafik: satu hari, atau satu bulan untuk rentang panjang.
class _Bucket {
  _Bucket(this.label, this.title);
  final String label;
  final String title;
  int cashIn = 0;
  int cashOut = 0;
  int profit = 0;
}

class _ReportPageState extends State<ReportPage> {
  _Preset _preset = _Preset.thisMonth;
  late DateTime _from = firstOfMonth(DateTime.now());
  late DateTime _to = lastOfMonth(DateTime.now());
  late Future<_Loaded> _future = _load();
  bool _exporting = false;
  bool _showIncome = true; // donat kategori: pemasukan dulu, lalu pengeluaran

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

  Future<_Loaded> _load() async {
    final r = await Future.wait([
      widget.cash.summary(_from, _to),
      widget.cash.daily(_from, _to),
      widget.cash.byCategory(_from, _to),
    ]);
    return _Loaded(r[0] as Summary, r[1] as List<DailyPoint>,
        r[2] as List<Map<String, dynamic>>);
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _future = _load();
      });
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _setPreset(_Preset p) async {
    final now = DateTime.now();
    switch (p) {
      case _Preset.thisMonth:
        _from = firstOfMonth(now);
        _to = lastOfMonth(now);
      case _Preset.lastMonth:
        final prev = DateTime(now.year, now.month - 1);
        _from = firstOfMonth(prev);
        _to = lastOfMonth(prev);
      case _Preset.thisYear:
        _from = DateTime(now.year);
        _to = DateTime(now.year, 12, 31);
      case _Preset.custom:
        final r = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(now.year + 1, 12, 31),
          initialDateRange: DateTimeRange(start: _from, end: _to),
        );
        if (r == null) return;
        _from = r.start;
        _to = r.end;
    }
    _preset = p;
    _reload();
  }

  Future<void> _export(bool xlsx) async {
    setState(() => _exporting = true);
    try {
      final exporter = ReportExporter(
          businessName: widget.business.name,
          cash: widget.cash,
          debts: widget.debts);
      if (xlsx) {
        await exporter.exportXlsx(_from, _to);
      } else {
        await exporter.exportCsv(_from, _to);
      }
      _toast('Berkas laporan dibuat.');
    } catch (e) {
      _toast('Gagal ekspor: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Rentang pendek per hari, rentang panjang per bulan.
  List<_Bucket> _buckets(List<DailyPoint> pts) {
    if (pts.length <= 31) {
      return [
        for (final p in pts)
          _Bucket('${p.day.day}', dateId(p.day))
            ..cashIn = p.cashIn
            ..cashOut = p.cashOut
            ..profit = p.profit,
      ];
    }
    final multiYear = pts.first.day.year != pts.last.day.year;
    final byMonth = <String, _Bucket>{};
    for (final p in pts) {
      final key = '${p.day.year}-${p.day.month}';
      final b = byMonth.putIfAbsent(
        key,
        () => _Bucket(
          multiYear
              ? "${monthShort(p.day)} '${p.day.year % 100}"
              : monthShort(p.day),
          monthId(p.day),
        ),
      );
      b.cashIn += p.cashIn;
      b.cashOut += p.cashOut;
      b.profit += p.profit;
    }
    return byMonth.values.toList();
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
        final buckets = _buckets(d.daily);
        final hasProfit = buckets.any((b) => b.profit != 0);

        return RefreshIndicator(
          edgeOffset: MediaQuery.paddingOf(context).top,
          onRefresh: () async => _reload(),
          child: ContentWidth(
            maxWidth: 900,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  16,
                  8 + MediaQuery.paddingOf(context).top,
                  16,
                  32 + MediaQuery.paddingOf(context).bottom),
              children: [
                if (snap.connectionState == ConnectionState.waiting)
                  const LinearProgressIndicator(minHeight: 3),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final f in const <(_Preset, String)>[
                    (_Preset.thisMonth, 'Bulan ini'),
                    (_Preset.lastMonth, 'Bulan lalu'),
                    (_Preset.thisYear, 'Tahun ini'),
                    (_Preset.custom, 'Pilih tanggal'),
                  ])
                    ChoiceChip(
                      label: Text(f.$2),
                      selected: _preset == f.$1,
                      onSelected: (_) => _setPreset(f.$1),
                    ),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                  child: Text('${dateId(_from)} – ${dateId(_to)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
                _Kpis(summary: d.summary),
                const SectionTitle('Arus kas'),
                SoftCard(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
                  child: _CashFlowChart(buckets: buckets),
                ),
                const SectionTitle('Keuntungan penjualan'),
                SoftCard(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
                  child: hasProfit
                      ? _ProfitChart(buckets: buckets)
                      : const EmptyState(
                          icon: Icons.trending_up_rounded,
                          title: 'Belum ada data keuntungan',
                          subtitle:
                              'Catat transaksi dengan kategori Penjualan dan isi Harga Modal agar keuntungan tampil di sini.',
                        ),
                ),
                const SectionTitle('Per kategori'),
                SoftCard(
                    child: _CategoryBreakdown(
                  rows: d.byCategory,
                  income: _showIncome,
                  onToggle: (v) => setState(() => _showIncome = v),
                )),
                if (widget.business.canManage) ...[
                  const SectionTitle('Ekspor'),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: _exporting ? null : () => _export(true),
                          icon: const Icon(Icons.table_chart_outlined),
                          label: const Text('Unduh Excel (.xlsx)'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _exporting ? null : () => _export(false),
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('Unduh CSV (transaksi kas)'),
                        ),
                        if (_exporting)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: LinearProgressIndicator(),
                          ),
                      ],
                    ),
                  ),
                  const SectionTitle('Backup ke Google Sheet'),
                  BackupCard(
                    business: widget.business,
                    cash: widget.cash,
                    debts: widget.debts,
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      'Ekspor laporan hanya untuk Pemilik dan Admin.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.summary});

  final Summary summary;

  @override
  Widget build(BuildContext context) {
    final net = summary.totalIn - summary.totalOut;
    final cards = <Widget>[
      _Kpi(
          'Kas masuk', summary.totalIn, Brand.income, Icons.south_west_rounded),
      _Kpi('Kas keluar', summary.totalOut, Brand.expense,
          Icons.north_east_rounded),
      _Kpi(
          'Keuntungan',
          summary.profit,
          summary.profit >= 0 ? Brand.profit : Brand.expense,
          Icons.trending_up_rounded,
          sub: summary.salesTotal > 0
              ? 'dari penjualan ${rupiah(summary.salesTotal)}'
              : 'dari penjualan'),
      _Kpi('Selisih periode', net, net >= 0 ? Brand.income : Brand.expense,
          Icons.swap_vert_rounded),
      _Kpi('Saldo kas saat ini', summary.balance, Brand.deep,
          Icons.account_balance_wallet_rounded),
      _Kpi('Piutang belum lunas', summary.receivableOpen, Brand.receivable,
          Icons.call_received_rounded),
      _Kpi('Utang belum lunas', summary.payableOpen, Brand.payable,
          Icons.call_made_rounded),
    ];
    return LayoutBuilder(builder: (context, c) {
      const gap = 12.0;
      final cols = c.maxWidth >= 720 ? 4 : 2;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final k in cards) SizedBox(width: w, child: k)],
      );
    });
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.color, this.icon, {this.sub});

  final String label;
  final int value;
  final Color color;
  final IconData icon;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconBadge(icon, color: color, size: 32),
          const SizedBox(width: 8),
          Expanded(
            child: FitText(label,
                maxLines: 2,
                minFontSize: 10,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ]),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(rupiah(value),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600, color: color)),
        ),
        if (sub != null)
          FitText(sub!,
              maxLines: 2,
              minFontSize: 10,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

FlTitlesData _titles(BuildContext context, List<_Bucket> buckets) {
  final muted = Theme.of(context).colorScheme.onSurfaceVariant;
  final style = Theme.of(context)
      .textTheme
      .labelSmall
      ?.copyWith(color: muted, fontSize: 10);
  // Hindari label menumpuk pada rentang bulan yang berisi 28-31 batang.
  final step = buckets.length > 16 ? 5 : (buckets.length > 8 ? 2 : 1);
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 48,
        getTitlesWidget: (v, meta) {
          if (v == meta.max || v == meta.min && v != 0) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            meta: meta,
            child: Text(compact(v), style: style),
          );
        },
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 26,
        interval: 1,
        getTitlesWidget: (v, meta) {
          final i = v.toInt();
          if (i < 0 || i >= buckets.length || i % step != 0) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            meta: meta,
            space: 6,
            child: Text(buckets[i].label, style: style),
          );
        },
      ),
    ),
  );
}

FlGridData _grid(BuildContext context) => FlGridData(
      show: true,
      drawVerticalLine: false,
      getDrawingHorizontalLine: (_) => FlLine(
        color: Theme.of(context).dividerTheme.color ?? Colors.grey,
        strokeWidth: 1,
      ),
    );

class _Legend extends StatelessWidget {
  const _Legend(this.items);

  final List<(String, Color)> items;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 16, runSpacing: 4, children: [
        for (final i in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: i.$2, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Text(i.$1, style: Theme.of(context).textTheme.labelMedium),
          ]),
      ]);
}

class _CashFlowChart extends StatelessWidget {
  const _CashFlowChart({required this.buckets});

  final List<_Bucket> buckets;

  @override
  Widget build(BuildContext context) {
    final peak = buckets.fold<int>(
        0, (m, b) => [m, b.cashIn, b.cashOut].reduce((a, c) => a > c ? a : c));
    if (peak == 0) {
      return const EmptyState(
        icon: Icons.bar_chart_rounded,
        title: 'Belum ada arus kas',
        subtitle:
            'Grafik muncul setelah ada kas masuk atau keluar pada periode ini.',
      );
    }
    final dense = buckets.length > 16;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(left: 16, bottom: 12),
        child: _Legend(
            [('Kas masuk', Brand.income), ('Kas keluar', Brand.expense)]),
      ),
      SizedBox(
        height: 240,
        child: BarChart(
          BarChartData(
            maxY: peak * 1.15,
            minY: 0,
            alignment: BarChartAlignment.spaceAround,
            gridData: _grid(context),
            borderData: FlBorderData(show: false),
            titlesData: _titles(context, buckets),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, gi, rod, ri) {
                  final b = buckets[group.x];
                  final kind = ri == 0 ? 'Masuk' : 'Keluar';
                  return BarTooltipItem(
                    '${b.title}\n$kind ${rupiah(rod.toY)}',
                    const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                  );
                },
              ),
            ),
            barGroups: [
              for (var i = 0; i < buckets.length; i++)
                BarChartGroupData(
                  x: i,
                  barsSpace: dense ? 1 : 3,
                  barRods: [
                    BarChartRodData(
                      toY: buckets[i].cashIn.toDouble(),
                      color: Brand.income,
                      width: dense ? 4 : 10,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    BarChartRodData(
                      toY: buckets[i].cashOut.toDouble(),
                      color: Brand.expense,
                      width: dense ? 4 : 10,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _ProfitChart extends StatelessWidget {
  const _ProfitChart({required this.buckets});

  final List<_Bucket> buckets;

  @override
  Widget build(BuildContext context) {
    final maxV = buckets.fold<int>(0, (m, b) => b.profit > m ? b.profit : m);
    final minV = buckets.fold<int>(0, (m, b) => b.profit < m ? b.profit : m);
    final span = (maxV - minV) == 0 ? 1 : (maxV - minV);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(left: 16, bottom: 12),
        child: _Legend([('Keuntungan', Brand.profit)]),
      ),
      SizedBox(
        height: 220,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: (buckets.length - 1).toDouble().clamp(1, double.infinity),
            minY: minV < 0 ? minV - span * 0.1 : 0,
            maxY: maxV + span * 0.15,
            gridData: _grid(context),
            borderData: FlBorderData(show: false),
            titlesData: _titles(context, buckets),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => [
                  for (final s in spots)
                    LineTooltipItem(
                      '${buckets[s.x.toInt()].title}\nUntung ${rupiah(s.y)}',
                      const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12),
                    ),
                ],
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < buckets.length; i++)
                    FlSpot(i.toDouble(), buckets[i].profit.toDouble()),
                ],
                isCurved: true,
                curveSmoothness: 0.2,
                preventCurveOverShooting: true,
                color: Brand.profit,
                barWidth: 3,
                dotData: FlDotData(show: buckets.length <= 16),
                belowBarData: BarAreaData(
                  show: true,
                  color: Brand.profit.withValues(alpha: 0.14),
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown(
      {required this.rows, required this.income, required this.onToggle});

  final List<Map<String, dynamic>> rows;
  final bool income;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = income ? 'in' : 'out';
    final items = rows.where((r) => r['type'] == type).toList()
      ..sort((a, b) => (b['total'] as num).compareTo(a['total'] as num));
    final total = items.fold<int>(0, (s, r) => s + (r['total'] as num).toInt());

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: true, label: Text('Pemasukan')),
          ButtonSegment(value: false, label: Text('Pengeluaran')),
        ],
        selected: {income},
        onSelectionChanged: (s) => onToggle(s.first),
      ),
      const SizedBox(height: 16),
      if (items.isEmpty)
        const EmptyState(
          icon: Icons.pie_chart_rounded,
          title: 'Belum ada data',
          subtitle:
              'Belum ada transaksi pada kategori ini di periode terpilih.',
        )
      else ...[
        SizedBox(
          height: 200,
          child: Stack(alignment: Alignment.center, children: [
            PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 62,
                sections: [
                  for (var i = 0; i < items.length; i++)
                    PieChartSectionData(
                      value: (items[i]['total'] as num).toDouble(),
                      color: _palette[i % _palette.length],
                      radius: 30,
                      showTitle: false,
                    ),
                ],
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Total',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text(rupiah(total),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: _palette[i % _palette.length],
                      borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 12),
              Expanded(
                child: Text(items[i]['category_name'] as String,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Text(
                  '${total == 0 ? 0 : ((items[i]['total'] as num) * 100 / total).round()}%',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(width: 12),
              Text(rupiah((items[i]['total'] as num).toInt()),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ]),
          ),
      ],
    ]);
  }
}
