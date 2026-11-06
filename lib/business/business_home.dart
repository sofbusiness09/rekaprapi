import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backup/backup_controller.dart';
import '../backup/backup_setup_page.dart';
import '../cash/cash_form.dart';
import '../cash/cash_page.dart';
import '../cash/cash_repository.dart';
import '../common/floating_nav_bar.dart';
import '../common/widgets.dart';
import '../debts/contacts_page.dart';
import '../debts/debt_form.dart';
import '../debts/debt_repository.dart';
import '../reports/report_page.dart';
import '../settings/home_prefs.dart';
import '../settings/settings_page.dart';
import '../settings/settings_repository.dart';
import '../theme/app_theme.dart';
import '../theme/background_controller.dart';
import '../theme/theme_picker.dart';
import 'business.dart';
import 'business_controller.dart';
import 'business_switcher.dart';

/// Tab: Rekapan (dashboard utama), Transaksi, Utang, dan Pengaturan. Di ponsel
/// Pengaturan dibuka lewat nama pembukuan, jadi bilah bawah hanya tiga tab.
const _tabs = <(IconData, IconData, String)>[
  (Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'Rekapan'),
  (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Transaksi'),
  (Icons.handshake_outlined, Icons.handshake_rounded, 'Utang'),
  (Icons.settings_outlined, Icons.settings_rounded, 'Pengaturan'),
];

const _phoneTabCount = 3;

/// Pilihan di lembar tombol "+ Catat".
enum _CatatKind { income, expense, debtGroup, payable, receivable }

/// Kerangka pembukuan yang sedang aktif. Layar lebar memakai navigasi samping;
/// layar sempit memakai bilah bawah melayang. Menekan nama pembukuan membuka daftar
/// pembukuan lain, tambah pembukuan, gabung dengan kode, dan Pengaturan.
/// Tombol "+ Catat" melayang di tiga tab utama, dan pilihannya menyesuaikan tab.
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
  late final BackupController _backup = BackupController(
      business: widget.business, cash: _repo, debts: _debtRepo);
  final ValueNotifier<int> _changes = ValueNotifier(0);

  /// Tombol Catat memanjang ("+ Catat"); mengecil menjadi ikon saat daftar digulir ke bawah.
  final ValueNotifier<bool> _fabExpanded = ValueNotifier(true);
  RealtimeChannel? _channel;
  int _tab = 0;

  /// Di ponsel Pengaturan tidak punya tab; dibuka dari lembar nama pembukuan dan
  /// menggantikan isi layar (bukan halaman baru) agar ikut berganti saat pembukuan berganti.
  bool _settingsOpen = false;

  Business get _business => widget.business;

  @override
  void initState() {
    super.initState();
    backgroundController.addListener(_onBackground);
    // Tampilan Transaksi dan Saldo kas dimiliki tiap pembukuan.
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

    _backup.addListener(_onBackup);
    // Backup otomatis harian: dijalankan saat pembukuan dibuka bila sudah waktunya.
    if (_business.canManage) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoBackup());
    }
  }

  void _onBackground() {
    if (mounted) setState(() {});
  }

  void _onBackup() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    backgroundController.removeListener(_onBackground);
    _backup.removeListener(_onBackup);
    _backup.dispose();
    final ch = _channel;
    if (ch != null) Supabase.instance.client.removeChannel(ch);
    _changes.dispose();
    _fabExpanded.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- Backup ---

  Future<void> _autoBackup() async {
    final outcome = await _backup.maybeAutoRun();
    if (outcome != null) _toast(outcome.message);
  }

  Future<void> _openBackupSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BackupSetupPage(
        controller: _backup,
        businessName: _business.name,
        canRestore: _business.role == 'owner',
        onRestored: widget.controller.afterRestore,
      ),
    ));
    await _backup.load();
  }

  Future<void> _backupTap() async {
    if (_backup.running) return;
    if (!_backup.configured) {
      await _openBackupSettings();
      return;
    }
    final outcome = await _backup.run();
    if (outcome != null) _toast(outcome.message);
  }

  /// Ikon awan di bilah atas: backup sekali tekan; titik peringatan bila backup
  /// terakhir gagal atau sudah lama. Hanya untuk Pemilik dan Admin.
  Widget? _backupButton() {
    if (!_backup.allowed) return null;
    if (_backup.running) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    return IconButton(
      tooltip: _backup.configured
          ? 'Backup ke Google Sheet'
          : 'Atur backup Google Sheet',
      onPressed: _backup.loading ? null : _backupTap,
      icon: Badge(
        isLabelVisible: _backup.needsAttention,
        smallSize: 9,
        backgroundColor: Brand.expense,
        child: const Icon(Icons.cloud_upload_outlined),
      ),
    );
  }

  // --- Tombol Catat ---

  List<(_CatatKind, IconData, Color, String)> _catatOptions() {
    const income = (
      _CatatKind.income,
      Icons.south_west_rounded,
      Brand.income,
      'Pemasukan'
    );
    const expense = (
      _CatatKind.expense,
      Icons.north_east_rounded,
      Brand.expense,
      'Pengeluaran'
    );
    const debt = (
      _CatatKind.debtGroup,
      Icons.handshake_rounded,
      Brand.info,
      'Utang piutang'
    );
    const payable =
        (_CatatKind.payable, Icons.call_made_rounded, Brand.payable, 'Utang');
    const receivable = (
      _CatatKind.receivable,
      Icons.call_received_rounded,
      Brand.receivable,
      'Piutang'
    );
    return switch (_tab) {
      1 => [income, expense],
      2 => [payable, receivable],
      _ => [income, expense, debt],
    };
  }

  Future<_CatatKind?> _pick(
      List<(_CatatKind, IconData, Color, String)> options) {
    return showModalBottomSheet<_CatatKind>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Catat apa?',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
            for (final o in options)
              ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                leading: IconBadge(o.$2, color: o.$3, size: 42),
                title: Text(o.$4,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(sheetContext, o.$1),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _catat() async {
    var kind = await _pick(_catatOptions());
    if (kind == null || !mounted) return;
    if (kind == _CatatKind.debtGroup) {
      // Dari tab Rekapan: "Utang piutang" membuka pilihan Utang atau Piutang.
      kind = await _pick(_catatOptions()
          .where((o) =>
              o.$1 == _CatatKind.payable || o.$1 == _CatatKind.receivable)
          .toList());
      if (kind == null || !mounted) return;
    }
    switch (kind) {
      case _CatatKind.income:
        await _openCash('in');
      case _CatatKind.expense:
        await _openCash('out');
      case _CatatKind.payable:
        await _openDebt('payable');
      case _CatatKind.receivable:
        await _openDebt('receivable');
      case _CatatKind.debtGroup:
        break;
    }
  }

  Future<void> _openCash(String type) async {
    final categories = await _repo.categories();
    if (!mounted) return;
    final saved = await showCashForm(context,
        repo: _repo,
        debtRepo: _debtRepo,
        categories: categories,
        initialType: type,
        lockType: true,
        allowSale: !_business.isPersonal,
        showProfit: _business.canSeeProfit);
    if (saved) _changes.value++;
  }

  Future<void> _openDebt(String kind) async {
    final contacts = await _debtRepo.contacts();
    if (!mounted) return;
    final saved = await showDebtForm(context,
        repo: _debtRepo, contacts: contacts, initialKind: kind, lockKind: true);
    if (saved) _changes.value++;
  }

  Widget _catatButton() => ValueListenableBuilder<bool>(
        valueListenable: _fabExpanded,
        builder: (context, expanded, _) => FloatingActionButton.extended(
          isExtended: expanded,
          onPressed: _catat,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Catat'),
        ),
      );

  // --- Kerangka ---

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
        backup: _backup,
        onRestored: widget.controller.afterRestore,
      );

  Widget _body({required bool wide}) {
    final pages = IndexedStack(
      index: wide ? _tab : _tab.clamp(0, _phoneTabCount - 1),
      children: [
        ReportPage(
            business: _business,
            cash: _repo,
            debts: _debtRepo,
            changes: _changes),
        CashPage(
            business: _business,
            repo: _repo,
            debtRepo: _debtRepo,
            changes: _changes),
        ContactsPage(business: _business, repo: _debtRepo, changes: _changes),
        if (wide) _settingsPage(),
      ],
    );
    // Menggulir ke bawah mengecilkan tombol Catat; ke atas memanjangkannya lagi.
    return NotificationListener<UserScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis == Axis.vertical) {
          if (n.direction == ScrollDirection.reverse) {
            _fabExpanded.value = false;
          } else if (n.direction == ScrollDirection.forward) {
            _fabExpanded.value = true;
          }
        }
        return false;
      },
      child: pages,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final scheme = Theme.of(context).colorScheme;

    // Nama pembukuan yang bisa ditekan untuk berpindah pembukuan.
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

    final gradient = backgroundGradient(Theme.of(context).brightness,
        Theme.of(context).scaffoldBackgroundColor);
    Widget withBackground(Widget child) => gradient == null
        ? child
        : DecoratedBox(
            decoration: BoxDecoration(gradient: gradient), child: child);
    final transparent = gradient == null ? null : Colors.transparent;
    final backupButton = _backupButton();

    if (wide) {
      return withBackground(Scaffold(
        backgroundColor: transparent,
        floatingActionButton: _tab < _phoneTabCount ? _catatButton() : null,
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
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (backupButton != null) backupButton,
                    const SizedBox(height: 8),
                    const ThemeModePicker(compact: true),
                  ]),
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
      ));
    }

    final phoneTabs = _tabs.take(_phoneTabCount).toList();
    return PopScope(
      canPop: !_settingsOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _settingsOpen = false);
      },
      child: withBackground(Scaffold(
        backgroundColor: transparent,
        appBar: _settingsOpen
            ? AppBar(
                backgroundColor: transparent,
                leading: BackButton(
                    onPressed: () => setState(() => _settingsOpen = false)),
                title: const Text('Pengaturan'),
              )
            : AppBar(
                backgroundColor: transparent,
                title: title,
                titleSpacing: 8,
                actions: [if (backupButton != null) backupButton],
              ),
        body: _settingsOpen ? _settingsPage() : _body(wide: false),
        floatingActionButton: _settingsOpen ? null : _catatButton(),
        // Panel bawah melayang seperti kapsul di atas isi layar.
        bottomNavigationBar: FloatingNavBar(
          items: [
            for (final t in phoneTabs) FloatingNavItem(t.$1, t.$2, t.$3),
          ],
          selectedIndex: _tab.clamp(0, phoneTabs.length - 1),
          onSelected: (i) => setState(() {
            _tab = i;
            _settingsOpen = false;
            _fabExpanded.value = true;
          }),
        ),
      )),
    );
  }
}
