import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backup/backup_controller.dart';
import '../backup/backup_setup_page.dart';
import '../business/business.dart';
import '../common/currency.dart';
import '../common/currency_picker.dart';
import '../common/dialogs.dart';
import '../debts/debt_repository.dart';
import '../telegram/telegram_page.dart';
import '../common/amount_field.dart' show isMobilePlatform;
import '../theme/app_style.dart';
import '../theme/background_controller.dart';
import '../theme/background_picker.dart';
import '../theme/font_controller.dart';
import '../theme/font_picker.dart';
import '../theme/style_picker_page.dart';
import '../theme/theme_picker.dart';
import '../update/app_update.dart';
import 'activity_page.dart';
import 'business_photo_page.dart';
import 'categories_page.dart';
import 'contacts_manage_page.dart';
import 'home_prefs.dart';
import 'input_prefs.dart';
import 'members_page.dart';
import 'settings_repository.dart';
import 'report_prefs_page.dart';
import 'tx_prefs_page.dart';
import 'package:rekap_rapi/l10n/l10n.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.business,
    required this.repo,
    required this.debtRepo,
    required this.changes,
    required this.onRenamed,
    required this.onPhotoChanged,
    required this.onCurrencyChanged,
    required this.onSwitchBusiness,
    required this.onBusinessGone,
    required this.backup,
    required this.onRestored,
  });

  final Business business;
  final SettingsRepository repo;
  final DebtRepository debtRepo;

  /// Dinaikkan setelah kontak berubah agar tab Utang ikut memuat ulang.
  final ValueNotifier<int> changes;

  /// Dipanggil setelah nama usaha diubah, agar judul di atas ikut berubah.
  final ValueChanged<String> onRenamed;

  /// Dipanggil setelah foto profil diganti (alamat baru) atau dihapus (null).
  final ValueChanged<String?> onPhotoChanged;

  /// Mengganti mata uang pembukuan (kode ISO). Melempar galat bila ditolak.
  final Future<void> Function(String code) onCurrencyChanged;

  /// Membuka daftar usaha untuk berpindah.
  final VoidCallback onSwitchBusiness;

  /// Dipanggil setelah pengguna keluar dari atau menghapus usaha ini.
  final VoidCallback onBusinessGone;

  /// Status dan aksi Backup Google Sheet pembukuan ini.
  final BackupController backup;

  /// Dipanggil dengan id pembukuan baru setelah pemulihan berhasil.
  final Future<void> Function(String businessId) onRestored;

  SupabaseClient get _db => Supabase.instance.client;

  void _toast(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _changeCurrency(BuildContext context) async {
    final picked = await showCurrencyPicker(context,
        selected: business.currency, title: tr('Mata uang pembukuan'));
    if (picked == null ||
        picked.code == business.currency ||
        !context.mounted) {
      return;
    }
    final ok = await confirmDialog(context,
        title: tr('Ganti ke {0}?', [picked.name]),
        body: tr(
            'Semua jumlah di "{0}" akan ditampilkan dalam {1}. Angkanya tidak dikonversi: {2} menjadi {3}.',
            [
              business.name,
              picked.code,
              formatMoney(50000, currencyByCode(business.currency)),
              formatMoney(50000, picked)
            ]),
        okLabel: tr('Ganti'));
    if (!ok || !context.mounted) return;
    try {
      await onCurrencyChanged(picked.code);
      if (context.mounted)
        _toast(context, tr('Mata uang diganti ke {0}.', [picked.code]));
    } on PostgrestException catch (e) {
      if (context.mounted) _toast(context, e.message);
    } catch (e) {
      if (context.mounted)
        _toast(context, tr('Gagal mengganti mata uang: {0}', [e]));
    }
  }

  Future<void> _chooseLanguage(BuildContext context) async {
    final picked = await showModalBottomSheet<AppLanguage>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final l in AppLanguage.values)
            ListTile(
              leading: Icon(l == languageController.language
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: Text(l.label),
              onTap: () => Navigator.pop(sheetContext, l),
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
    if (picked != null) await languageController.set(picked);
  }

  Future<void> _changeName(BuildContext context) async {
    final profile = await _db
        .from('profiles')
        .select('display_name')
        .eq('id', _db.auth.currentUser!.id)
        .single();
    if (!context.mounted) return;
    final name = await askText(context,
        title: tr('Nama tampilan'),
        label: tr('Nama'),
        initial: (profile['display_name'] ?? '') as String);
    if (name == null || name.isEmpty || !context.mounted) return;
    try {
      await repo.updateDisplayName(name);
      if (context.mounted) _toast(context, tr('Nama disimpan.'));
    } on PostgrestException catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final pw = await askText(context,
        title: tr('Ganti password'),
        label: tr('Password baru (min. 6 karakter)'),
        obscure: true);
    if (pw == null || !context.mounted) return;
    if (pw.length < 6) {
      _toast(context, tr('Password minimal 6 karakter.'));
      return;
    }
    try {
      await repo.changePassword(pw);
      if (context.mounted) _toast(context, tr('Password diganti.'));
    } on AuthException catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }

  Future<void> _signOut(BuildContext context) async {
    Navigator.of(context).popUntil((r) => r.isFirst);
    await _db.auth.signOut();
  }

  Future<void> _leave(BuildContext context) async {
    if (!await confirmDialog(context,
        title: tr('Keluar dari pembukuan?'),
        body: tr('Anda tidak akan bisa mengakses "{0}" kecuali diundang lagi.',
            [business.name]),
        okLabel: tr('Keluar'))) {
      return;
    }
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.leaveBusiness();
      messenger.showSnackBar(SnackBar(
          content: Text(tr('Anda keluar dari "{0}".', [business.name]))));
      onBusinessGone();
    } on PostgrestException catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }

  Future<void> _deleteBusiness(BuildContext context) async {
    final typed = await askText(context,
        title: tr('Hapus pembukuan?'),
        label:
            tr('Ketik nama pembukuan untuk menghapus: {0}', [business.name]));
    if (typed == null || !context.mounted) return;
    if (typed != business.name) {
      _toast(context, tr('Nama tidak cocok. Usaha tidak dihapus.'));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.deleteBusiness();
      messenger.showSnackBar(
          SnackBar(content: Text(tr('Usaha "{0}" dihapus.', [business.name]))));
      onBusinessGone();
    } on PostgrestException catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _db.auth.currentUser?.email ?? '';
    return ListView(
      children: [
        _Header(
            '${business.kind.label}: ${business.name} (${roleLabel[business.role]})'),
        if (business.canManage)
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: Text(tr('Profil pembukuan')),
            onTap: () => _push(
                context,
                BusinessPhotoPage(
                  businessId: business.id,
                  businessName: business.name,
                  photoUrl: business.photoUrl,
                  onChanged: onPhotoChanged,
                  loadProfile: repo.business,
                  saveProfile: (name, address, phone) async {
                    await repo.updateBusiness(name, address, phone);
                    onRenamed(name.trim());
                  },
                )),
          ),
        if (business.canManage)
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(tr('Mata uang')),
            subtitle: Text(currencyByCode(business.currency).label),
            onTap: () => _changeCurrency(context),
          ),
        // Pembukuan pribadi tidak dibagikan, jadi tanpa daftar anggota.
        if (!business.isPersonal)
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: Text(tr('Anggota')),
            onTap: () =>
                _push(context, MembersPage(business: business, repo: repo)),
          ),
        ListTile(
          leading: const Icon(Icons.contacts_outlined),
          title:
              Text(business.isPersonal ? tr('Kontak') : tr('Kontak Pelanggan')),
          onTap: () => _push(
              context,
              ContactsManagePage(
                  business: business, repo: debtRepo, changes: changes)),
        ),
        ListTile(
          leading: const Icon(Icons.send_outlined),
          title: Text(tr('Telegram')),
          onTap: () => _push(
              context,
              TelegramPage(
                  businessId: business.id, businessName: business.name)),
        ),
        if (business.canManage) ...[
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: Text(tr('Kategori')),
            onTap: () => _push(context, CategoriesPage(repo: repo)),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: Text(tr('Backup dan Pemulihan')),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => BackupSetupPage(
                  controller: backup,
                  businessName: business.name,
                  canRestore: business.role == 'owner',
                  onRestored: onRestored,
                ),
              ));
              // Ikon backup di bilah atas ikut menyesuaikan.
              await backup.load();
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(tr('Riwayat aktivitas')),
            onTap: () => _push(context, ActivityPage(repo: repo)),
          ),
        ],
        const Divider(),
        _Header(tr('Tampilan')),
        ListenableBuilder(
          listenable: languageController,
          builder: (context, _) => ListTile(
            leading: const Icon(Icons.translate_rounded),
            title: Text(tr('Bahasa')),
            subtitle: Text(languageController.language.label),
            onTap: () => _chooseLanguage(context),
          ),
        ),
        ListenableBuilder(
          listenable: styleController,
          builder: (context, _) => ListTile(
            leading: const Icon(Icons.style_outlined),
            title: Text(tr('Gaya tampilan')),
            subtitle: Text(styleController.style.title),
            onTap: () => _push(context, const StylePickerPage()),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: ThemeModePicker(),
        ),
        ListenableBuilder(
          listenable: fontController,
          builder: (context, _) => ListTile(
            leading: const Icon(Icons.text_fields_rounded),
            title: Text(tr('Jenis huruf')),
            subtitle: Text(fontController.font.name),
            onTap: () => showFontPicker(context),
          ),
        ),
        ListenableBuilder(
          listenable: backgroundController,
          builder: (context, _) => ListTile(
            leading: const Icon(Icons.gradient_rounded),
            title: Text(tr('Latar gradasi')),
            subtitle: Text(backgroundController.enabled
                ? tr(backgroundController.preset.name)
                : 'Mati'),
            onTap: () => showBackgroundPicker(context),
          ),
        ),
        // Hanya relevan di perangkat sentuh.
        if (isMobilePlatform)
          ListenableBuilder(
            listenable: inputPrefs,
            builder: (context, _) => SwitchListTile(
              secondary: const Icon(Icons.calculate_outlined),
              title: Text(tr('Keyboard kalkulator')),
              value: inputPrefs.calcKeypad,
              onChanged: inputPrefs.setCalcKeypad,
            ),
          ),
        ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text(tr('Tampilan Transaksi')),
          onTap: () => _push(context, TxPrefsPage(businessName: business.name)),
        ),
        ListTile(
          leading: const Icon(Icons.bar_chart_rounded),
          title: Text(tr('Tampilan Rekapan')),
          onTap: () => _push(
              context,
              ReportPrefsPage(
                  businessName: business.name,
                  personal: business.isPersonal,
                  canSeeProfit: business.canSeeProfit)),
        ),
        // Pembukuan Usaha: Saldo Kas disembunyikan kecuali dihidupkan di sini.
        if (business.canSeeProfit)
          ListenableBuilder(
            listenable: homePrefs,
            builder: (context, _) => SwitchListTile(
              secondary: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(tr('Tampilkan saldo kas')),
              value: homePrefs.value.showCashBalance,
              onChanged: (v) => homePrefs
                  .update(homePrefs.value.copyWith(showCashBalance: v)),
            ),
          ),
        const Divider(),
        _Header(tr('Akun ({0})', [email])),
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: Text(tr('Nama tampilan')),
          onTap: () => _changeName(context),
        ),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: Text(tr('Ganti password')),
          onTap: () => _changePassword(context),
        ),
        ListTile(
          leading: const Icon(Icons.swap_horiz),
          title: Text(tr('Pindah / tambah pembukuan')),
          onTap: onSwitchBusiness,
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(tr('Keluar dari akun')),
          onTap: () => _signOut(context),
        ),
        const _VersionTile(),
        const Divider(),
        if (business.role == 'owner')
          ListTile(
            leading:
                Icon(Icons.delete_forever_outlined, color: Colors.red.shade700),
            title: Text(tr('Hapus pembukuan'),
                style: TextStyle(color: Colors.red.shade700)),
            onTap: () => _deleteBusiness(context),
          )
        else
          ListTile(
            leading: Icon(Icons.exit_to_app, color: Colors.red.shade700),
            title: Text(tr('Keluar dari pembukuan ini'),
                style: TextStyle(color: Colors.red.shade700)),
            onTap: () => _leave(context),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

/// Versi aplikasi yang terpasang; di Android sekaligus tombol periksa pembaruan.
class _VersionTile extends StatefulWidget {
  const _VersionTile();

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  String? _version;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = p.version);
    }).catchError((_) {});
  }

  Future<void> _check() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checking = true);
    try {
      final r = await maybeShowUpdate(context, force: true);
      if (r == null) {
        messenger.showSnackBar(
            SnackBar(content: Text(tr('Aplikasi sudah versi terbaru.'))));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content: Text(tr(
              'Tidak bisa memeriksa pembaruan. Periksa koneksi internet.'))));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.info_outline_rounded),
      title: Text(tr('Versi aplikasi {0}', [_version ?? '']).trim()),
      subtitle: updatesSupported ? Text(tr('Periksa pembaruan')) : null,
      trailing: _checking
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4))
          : null,
      onTap: updatesSupported && !_checking ? _check : null,
    );
  }
}
