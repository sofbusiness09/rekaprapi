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
  (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Transaksi'),
  (Icons.handshake_outlined, Icons.handshake_rounded, 'Utang'),
  (Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'Laporan'),
  (Icons.settings_outlined, Icons.settings_rounded, 'Pengaturan'),
];

/// Kerangka usaha yang sedang aktif: Beranda, Transaksi, Utang, Laporan, Pengaturan.
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

  /// Di ponsel Pengaturan tidak punya tab; dibuka dari lembar nama usaha dan
  /// menggantikan isi layar (bukan halaman baru) agar ikut berganti saat usaha berganti.
  bool _settingsOpen = false;

  Business get _business => widget.business;

  @override
  void initState() {
    super.initState();
    // Tampilan Beranda dan Transaksi dimiliki tiap usaha.
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != null) homePrefs.load(uid, businessId: widget.business.id);
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

  void _openSwitcher({bool withSettings = false}) => showBusinessSwitcher(
        context,
        widget.controller,
        onOpenSettings:
            withSettings ? () => setState(() => _settingsOpen = true) : null,
      );

  Widget _settingsPage() => SettingsPage(
        business: _business,
        repo: _settingsRepo,
        onRenamed: (name) => widget.controller.rename(_business.id, name),
        debtRepo: _debtRepo,
        changes: _changes,
        onSwitchBusiness: _openSwitcher,
        onBusinessGone: () => widget.controller.afterLeft(),
      );

  Widget _body({required bool wide}) => IndexedStack(
        index: wide ? _tab : _tab.clamp(0, _tabs.length - 2),
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
          if (wide) _settingsPage(),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final scheme = Theme.of(context).colorScheme;

    // Nama usaha yang bisa ditekan untuk berpindah usaha.
    final title = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openSwitcher(withSettings: !wide),
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
                      ?.copyWith(fontWeight: FontWeight.w600)),
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
          Expanded(child: _body(wide: true)),
        ]),
      );
    }

    final phoneTabs = _tabs.take(_tabs.length - 1);
    return PopScope(
      canPop: !_settingsOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _settingsOpen = false);
      },
      child: Scaffold(
        appBar: _settingsOpen
            ? AppBar(
                leading: BackButton(
                    onPressed: () => setState(() => _settingsOpen = false)),
                title: const Text('Pengaturan'),
              )
            : AppBar(title: title, titleSpacing: 8),
        body: _settingsOpen ? _settingsPage() : _body(wide: false),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab.clamp(0, _tabs.length - 2),
          onDestinationSelected: (i) => setState(() {
            _tab = i;
            _settingsOpen = false;
          }),
          destinations: [
            for (final t in phoneTabs)
              NavigationDestination(
                  icon: Icon(t.$1), selectedIcon: Icon(t.$2), label: t.$3),
          ],
        ),
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
        initialType: type,
        lockType: true);
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

    // Urutan bagian mengikuti pilihan pengguna; bagian yang dimatikan dilewati.
    final byId = <String, Widget Function()>{
      'hero': () => _HeroCard(
            summary: s,
            showBalance: p.showBalance,
            showFlow: p.showFlow,
          ),
      'profit': () => _ProfitStrip(summary: s),
      'quick': () => Row(children: [
            Expanded(
              child: _QuickAction(
                icon: Icons.south_west_rounded,
                label: 'Kas masuk',
                color: Brand.income,
                onTap: () => _add(d.categories, 'in'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickAction(
                icon: Icons.north_east_rounded,
                label: 'Kas keluar',
                color: Brand.expense,
                onTap: () => _add(d.categories, 'out'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickAction(
                icon: Icons.handshake_rounded,
                label: 'Utang',
                color: Brand.info,
                onTap: () => widget.onOpenTab(2),
              ),
            ),
          ]),
      'debt': () =>
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionTitle('Utang piutang'),
            Row(children: [
              Expanded(
                child: _DebtCard(
                  label: 'Piutang belum lunas',
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
                  value: s.payableOpen,
                  color: Brand.payable,
                  icon: Icons.call_made_rounded,
                  onTap: () => widget.onOpenTab(2),
                ),
              ),
            ]),
          ]),
      'activity': () =>
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionTitle('Aktivitas terbaru',
                action: activities.isEmpty ? null : 'Lihat semua',
                onAction: () => widget.onOpenTab(1)),
            if (!p.anyActivityType)
              const SoftCard(
                child: EmptyState(
                  icon: Icons.filter_alt_off_rounded,
                  title: 'Semua jenis aktivitas disembunyikan',
                  subtitle: 'Atur di Pengaturan > Tampilan Beranda.',
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
    };
    final sections = <Widget>[
      for (final id in p.order)
        if (p.sectionShown(id)) byId[id]!(),
    ];

    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
          children: [
            if (sections.isEmpty)
              const EmptyState(
                icon: Icons.dashboard_customize_rounded,
                title: 'Beranda kosong',
                subtitle: 'Atur di Pengaturan > Tampilan Beranda.',
              ),
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.deep, Brand.seed],
        ),
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
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5)),
          ),
        ],
        if (showBalance && showFlow) const SizedBox(height: 16),
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      // Ikon dan label di baris atas, nominal di bawahnya, supaya label
      // tidak terpotong di layar sempit.
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: FitText(label,
                style:
                    theme.textTheme.labelSmall?.copyWith(color: Colors.white70),
                minFontSize: 9),
          ),
        ]),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(rupiah(value),
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// Keuntungan penjualan bulan ini. Sengaja dibuat paling menonjol setelah kartu
/// saldo: angka besar, alas bertinta warna keuntungan, dan margin di bawahnya.
class _ProfitStrip extends StatelessWidget {
  const _ProfitStrip({required this.summary});

  final Summary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final positive = summary.profit >= 0;
    final color = positive ? Brand.profit : Brand.expense;
    final hasSales = summary.salesTotal > 0;
    final margin = hasSales ? summary.profit * 100 / summary.salesTotal : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
              positive
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              color: color,
              size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(positive ? 'Keuntungan bulan ini' : 'Rugi bulan ini',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w600)),
          ),
          if (margin != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Margin ${margin.toStringAsFixed(1)}%',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: color, fontWeight: FontWeight.w600)),
            ),
        ]),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(rupiah(summary.profit.abs()),
              style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w600, color: color, height: 1.1)),
        ),
        const SizedBox(height: 6),
        Text(
          hasSales
              ? 'dari penjualan ${rupiah(summary.salesTotal)}'
              : 'Belum ada penjualan bulan ini.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
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
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      child: Column(children: [
        IconBadge(icon, color: color, size: 42),
        const SizedBox(height: 8),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String label;
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
        IconBadge(icon, color: color, size: 36),
        const SizedBox(height: 12),
        FitText(label,
            maxLines: 2,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(rupiah(value),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600, color: color)),
        ),
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

    final Color tone;
    final IconData icon;
    if (a.isCredit) {
      tone = a.isIn ? Brand.receivable : Brand.payable;
      icon = categoryIcon(a.title, income: a.isIn);
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

    return EntryRow(
      icon: icon,
      iconColor: tone,
      title: a.title,
      amount: a.isCredit
          ? rupiah(a.amount)
          : '${a.isIn ? '+' : '-'}${rupiah(a.amount)}',
      amountColor: tone,
      sub: sub,
      status: status,
      statusColor: statusColor,
      onTap: onTap,
    );
  }
}
