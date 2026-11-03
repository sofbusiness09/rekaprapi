import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cash/cash_form.dart';
import '../cash/cash_models.dart';
import '../cash/cash_page.dart';
import '../cash/cash_repository.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../debts/debt_detail_page.dart';
import '../debts/debt_repository.dart';
import '../debts/contacts_page.dart';
import '../reports/report_page.dart';
import '../settings/home_prefs.dart';
import '../settings/settings_page.dart';
import '../settings/settings_repository.dart';
import '../theme/app_theme.dart';
import '../theme/theme_picker.dart';
import 'business.dart';
import 'business_controller.dart';
import 'business_switcher.dart';

const _tabs = <(IconData, IconData, String)>[
  (Icons.home_outlined, Icons.home_rounded, 'Beranda'),
  (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Kas'),
  (Icons.handshake_outlined, Icons.handshake_rounded, 'Utang'),
  (Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'Laporan'),
  (Icons.settings_outlined, Icons.settings_rounded, 'Pengaturan'),
];

/// Kerangka usaha yang sedang aktif: Beranda, Kas, Utang, Laporan, Pengaturan.
/// Layar lebar memakai navigasi samping; layar sempit memakai bilah bawah.
/// Menekan nama usaha membuka daftar usaha lain, tambah usaha, dan gabung dengan kode.
class BusinessHome extends StatefulWidget {
  const BusinessHome(
      {super.key, required this.business, required this.controller});

  final Business business;
  final BusinessController controller;

  @override
  State<BusinessHome> createState() => _BusinessHomeState();
}

class _BusinessHomeState extends State<BusinessHome> {
  late final CashRepository _repo = CashRepository(widget.business.id);
  late final DebtRepository _debtRepo = DebtRepository(widget.business.id);
  late final SettingsRepository _settingsRepo =
      SettingsRepository(widget.business.id);
  final ValueNotifier<int> _changes = ValueNotifier(0);
  RealtimeChannel? _channel;
  int _tab = 0;

  Business get _business => widget.business;

  @override
  void initState() {
    super.initState();
    var channel = Supabase.instance.client.channel('biz_${widget.business.id}');
    for (final table in const ['cash_transactions', 'debts', 'debt_payments']) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'business_id',
          value: widget.business.id,
        ),
        callback: (_) => _changes.value++,
      );
    }
    _channel = channel.subscribe();
  }

  @override
  void dispose() {
    final ch = _channel;
    if (ch != null) Supabase.instance.client.removeChannel(ch);
    _changes.dispose();
    super.dispose();
  }

  void _openSwitcher() => showBusinessSwitcher(context, widget.controller);

  Widget _body() => IndexedStack(
        index: _tab,
        children: [
          _Dashboard(
            business: _business,
            repo: _repo,
            debtRepo: _debtRepo,
            changes: _changes,
            onOpenTab: (i) => setState(() => _tab = i),
          ),
          CashPage(
              business: _business,
              repo: _repo,
              debtRepo: _debtRepo,
              changes: _changes),
          ContactsPage(business: _business, repo: _debtRepo, changes: _changes),
          ReportPage(
              business: _business,
              cash: _repo,
              debts: _debtRepo,
              changes: _changes),
          SettingsPage(
            business: _business,
            repo: _settingsRepo,
            onRenamed: (name) => widget.controller.rename(_business.id, name),
            debtRepo: _debtRepo,
            changes: _changes,
            onSwitchBusiness: _openSwitcher,
            onBusinessGone: () => widget.controller.afterLeft(),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final scheme = Theme.of(context).colorScheme;

    // Nama usaha yang bisa ditekan untuk berpindah usaha.
    final title = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _openSwitcher,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          InitialAvatar(_business.name, size: 38),
          const SizedBox(width: 12),
          Flexible(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_business.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(roleNames[_business.role] ?? _business.role,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 4),
          Icon(Icons.unfold_more_rounded, color: scheme.onSurfaceVariant),
        ]),
      ),
    );

    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: true,
            minExtendedWidth: 220,
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            leading: Padding(
              padding: const EdgeInsets.fromLTRB(8, 20, 8, 16),
              child: SizedBox(width: 204, child: title),
            ),
            trailing: const Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: ThemeModePicker(compact: true),
                ),
              ),
            ),
            destinations: [
              for (final t in _tabs)
                NavigationRailDestination(
                  icon: Icon(t.$1),
                  selectedIcon: Icon(t.$2),
                  label: Text(t.$3),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _body()),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(title: title, titleSpacing: 8),
      body: _body(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
                icon: Icon(t.$1), selectedIcon: Icon(t.$2), label: t.$3),
        ],
      ),
    );
  }
}

class _DashData {
  _DashData(this.summary, this.categories, this.recent);
  final Summary summary;
  final List<Category> categories;
  final List<Activity> recent;
}

class _Dashboard extends StatefulWidget {
  const _Dashboard({
    required this.business,
    required this.repo,
    required this.debtRepo,
    required this.changes,
    required this.onOpenTab,
  });

  final Business business;
  final CashRepository repo;
  final DebtRepository debtRepo;
  final ValueNotifier<int> changes;
  final ValueChanged<int> onOpenTab;

  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  late Future<_DashData> _future = _load();

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

  Future<_DashData> _load() async {
    final now = DateTime.now();
    final r = await Future.wait([
      widget.repo.summary(firstOfMonth(now), lastOfMonth(now)),
      widget.repo.categories(),
      widget.repo.recentActivity(60),
    ]);
    return _DashData(
        r[0] as Summary, r[1] as List<Category>, r[2] as List<Activity>);
  }

  void _reload() {
    if (mounted)
      setState(() {
        _future = _load();
      });
  }

  /// Aktivitas yang terkait catatan hutang membuka detailnya; kas biasa membuka tab Kas.
  Future<void> _openActivity(Activity a) async {
    final debtId = a.debtId;
    if (debtId == null) {
      widget.onOpenTab(1);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DebtDetailPage(
        business: widget.business,
        repo: widget.debtRepo,
        debtId: debtId,
        contactName: a.contactName ?? 'Kontak',
        changes: widget.changes,
      ),
    ));
    _reload();
  }

  Future<void> _add(List<Category> cats, String type) async {
    final saved = await showCashForm(context,
        repo: widget.repo,
        debtRepo: widget.debtRepo,
        categories: cats,
        initialType: type);
    if (saved) widget.changes.value++;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashData>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Gagal memuat: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = snap.data!;
        // Pilihan Beranda di Pengaturan; bawaannya menampilkan semuanya.
        return ListenableBuilder(
          listenable: homePrefs,
          builder: (context, _) => _content(d, homePrefs.value),
        );
      },
    );
  }

  Widget _content(_DashData d, HomePrefs p) {
    final s = d.summary;
    final activities = d.recent.where(p.allows).take(p.activityCount).toList();

    // Setiap bagian dipisah jarak yang sama; bagian yang dimatikan dilewati.
    final sections = <Widget>[
      if (p.showHero)
        _HeroCard(
          summary: s,
          showBalance: p.showBalance,
          showFlow: p.showFlow,
        ),
      if (p.showProfit) _ProfitStrip(summary: s),
      if (p.showQuickActions)
        Row(children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.south_west_rounded,
              label: 'Kas masuk',
              color: Brand.income,
              onTap: () => _add(d.categories, 'in'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickAction(
              icon: Icons.north_east_rounded,
              label: 'Kas keluar',
              color: Brand.expense,
              onTap: () => _add(d.categories, 'out'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickAction(
              icon: Icons.handshake_rounded,
              label: 'Utang',
              color: Brand.info,
              onTap: () => widget.onOpenTab(2),
            ),
          ),
        ]),
      if (p.showDebtCards)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('Utang piutang'),
          Row(children: [
            Expanded(
              child: _DebtCard(
                label: 'Piutang belum lunas',
                hint: 'Uang yang harus Anda tagih',
                value: s.receivableOpen,
                color: Brand.receivable,
                icon: Icons.call_received_rounded,
                onTap: () => widget.onOpenTab(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DebtCard(
                label: 'Utang belum lunas',
                hint: 'Uang yang harus Anda bayar',
                value: s.payableOpen,
                color: Brand.payable,
                icon: Icons.call_made_rounded,
                onTap: () => widget.onOpenTab(2),
              ),
            ),
          ]),
        ]),
      if (p.showActivity)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle('Aktivitas terbaru',
              action: activities.isEmpty ? null : 'Lihat semua',
              onAction: () => widget.onOpenTab(1)),
          if (!p.anyActivityType)
            const SoftCard(
              child: EmptyState(
                icon: Icons.filter_alt_off_rounded,
                title: 'Semua jenis aktivitas disembunyikan',
                subtitle:
                    'Pilih jenis yang ingin tampil di Pengaturan > Tampilan Beranda.',
              ),
            )
          else if (activities.isEmpty)
            SoftCard(
              child: EmptyState(
                icon: Icons.receipt_long_rounded,
                title: 'Belum ada aktivitas',
                subtitle: d.recent.isEmpty
                    ? 'Aktivitas uang yang Anda pilih akan tampil di sini.'
                    : 'Tidak ada aktivitas dari jenis yang Anda pilih.',
                actionLabel: d.recent.isEmpty ? 'Catat kas masuk' : null,
                onAction:
                    d.recent.isEmpty ? () => _add(d.categories, 'in') : null,
              ),
            )
          else
            SoftCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < activities.length; i++) ...[
                  if (i > 0) const Divider(indent: 72),
                  _ActivityTile(
                    activity: activities[i],
                    onTap: () => _openActivity(activities[i]),
                  ),
                ],
              ]),
            ),
        ]),
    ];

    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (sections.isEmpty)
              const EmptyState(
                icon: Icons.dashboard_customize_rounded,
                title: 'Beranda kosong',
                subtitle:
                    'Semua bagian Beranda disembunyikan. Pilih yang ingin tampil di Pengaturan > Tampilan Beranda.',
              ),
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              sections[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.summary,
    required this.showBalance,
    required this.showFlow,
  });

  final Summary summary;
  final bool showBalance;
  final bool showFlow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.deep, Brand.seed],
        ),
        boxShadow: [
          BoxShadow(
              color: Brand.seed.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 12)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showBalance) ...[
          Row(children: [
            const Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Text('Saldo kas',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: Colors.white70)),
          ]),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(rupiah(summary.balance),
                style: theme.textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
          ),
        ],
        if (showBalance && showFlow) const SizedBox(height: 20),
        if (showFlow)
          Row(children: [
            Expanded(
              child: _HeroPill(
                  icon: Icons.south_west_rounded,
                  label: 'Masuk bulan ini',
                  value: summary.totalIn),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _HeroPill(
                  icon: Icons.north_east_rounded,
                  label: 'Keluar bulan ini',
                  value: summary.totalOut),
            ),
          ]),
      ]),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.white70)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(rupiah(value),
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Keuntungan penjualan bulan ini, di bawah kartu saldo.
class _ProfitStrip extends StatelessWidget {
  const _ProfitStrip({required this.summary});

  final Summary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positive = summary.profit >= 0;
    final color = positive ? Brand.profit : Brand.expense;
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        IconBadge(
            positive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            color: color,
            size: 44),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(positive ? 'Keuntungan bulan ini' : 'Rugi bulan ini',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(rupiah(summary.profit.abs()),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800, color: color)),
            ),
          ]),
        ),
        Text(
          summary.salesTotal > 0
              ? 'dari penjualan\n${rupiah(summary.salesTotal)}'
              : 'Catat penjualan\nuntuk melihat untung',
          textAlign: TextAlign.right,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ]),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(children: [
        IconBadge(icon, color: color, size: 48),
        const SizedBox(height: 10),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({
    required this.label,
    required this.hint,
    required this.value,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String hint;
  final int value;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconBadge(icon, color: color, size: 40),
        const SizedBox(height: 14),
        Text(label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(rupiah(value),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800, color: color)),
        ),
        const SizedBox(height: 4),
        Text(hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

/// Satu aktivitas uang. Kas tampil dengan tanda +/-; transaksi hutang tampil dengan
/// status Belum lunas / Sisa / Lunas karena uangnya belum berpindah.
class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity, required this.onTap});

  final Activity activity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    final Color tone;
    final IconData icon;
    if (a.isCredit) {
      tone = a.isIn ? Brand.receivable : Brand.payable;
      icon = Icons.schedule_rounded;
    } else {
      tone = amountColor(a.isIn);
      icon = categoryIcon(a.title, income: a.isIn);
    }

    final sub = [
      if (a.contactName != null) a.contactName!,
      if (a.isSale && a.profit != null)
        '${a.profit! >= 0 ? 'Untung' : 'Rugi'} ${rupiah(a.profit!.abs())}',
      if (a.note != null) a.note!,
      dayLabel(a.date),
    ].join(' · ');

    String? status;
    Color? statusColor;
    if (a.isCredit) {
      if (a.settled) {
        status = 'Lunas';
        statusColor = Brand.income;
      } else {
        final paid = a.amount - (a.remaining ?? a.amount);
        status = paid > 0 ? 'Sisa ${rupiah(a.remaining!)}' : 'Belum lunas';
        statusColor = Brand.pending;
      }
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          IconBadge(icon, color: tone),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
                a.isCredit
                    ? rupiah(a.amount)
                    : '${a.isIn ? '+' : '-'}${rupiah(a.amount)}',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800, color: tone)),
            if (status != null)
              Text(status,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor, fontWeight: FontWeight.w700)),
          ]),
        ]),
      ),
    );
  }
}
