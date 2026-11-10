import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backup/backup_controller.dart';
import '../backup/backup_setup_page.dart';
import '../business/business.dart';
import '../common/dialogs.dart';
import '../debts/debt_repository.dart';
import '../telegram/telegram_page.dart';
import '../common/amount_field.dart' show isMobilePlatform;
import '../theme/background_controller.dart';
import '../theme/background_picker.dart';
import '../theme/font_controller.dart';
import '../theme/font_picker.dart';
import '../theme/theme_picker.dart';
import 'activity_page.dart';
import 'categories_page.dart';
import 'contacts_manage_page.dart';
import 'home_prefs.dart';
import 'input_prefs.dart';
import 'members_page.dart';
import 'settings_repository.dart';
import 'tx_prefs_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.business,
    required this.repo,
    required this.debtRepo,
    required this.changes,
    required this.onRenamed,
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

  Future<void> _editProfile(BuildContext context) async {
    final data = await repo.business();
    if (!context.mounted) return;
    final result = await showDialog<(String, String, String)>(
        context: context, builder: (_) => _ProfileDialog(data: data));
    if (result == null || !context.mounted) return;
    try {
      await repo.updateBusiness(result.$1, result.$2, result.$3);
      onRenamed(result.$1.trim());
      if (context.mounted) _toast(context, 'Profil pembukuan disimpan.');
    } on PostgrestException catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }

  Future<void> _changeName(BuildContext context) async {
    final profile = await _db
        .from('profiles')
        .select('display_name')
        .eq('id', _db.auth.currentUser!.id)
        .single();
    if (!context.mounted) return;
    final name = await askText(context,
        title: 'Nama tampilan',
        label: 'Nama',
        initial: (profile['display_name'] ?? '') as String);
    if (name == null || name.isEmpty || !context.mounted) return;
    try {
      await repo.updateDisplayName(name);
      if (context.mounted) _toast(context, 'Nama disimpan.');
    } on PostgrestException catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final pw = await askText(context,
        title: 'Ganti password',
        label: 'Password baru (min. 6 karakter)',
        obscure: true);
    if (pw == null || !context.mounted) return;
    if (pw.length < 6) {
      _toast(context, 'Password minimal 6 karakter.');
      return;
    }
    try {
      await repo.changePassword(pw);
      if (context.mounted) _toast(context, 'Password diganti.');
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
        title: 'Keluar dari pembukuan?',
        body:
            'Anda tidak akan bisa mengakses "${business.name}" kecuali diundang lagi.',
        okLabel: 'Keluar')) {
      return;
    }
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.leaveBusiness();
      messenger.showSnackBar(
          SnackBar(content: Text('Anda keluar dari "${business.name}".')));
      onBusinessGone();
    } on PostgrestException catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }

  Future<void> _deleteBusiness(BuildContext context) async {
    final typed = await askText(context,
        title: 'Hapus pembukuan?',
        label: 'Ketik nama pembukuan untuk menghapus: ${business.name}');
    if (typed == null || !context.mounted) return;
    if (typed != business.name) {
      _toast(context, 'Nama tidak cocok. Usaha tidak dihapus.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.deleteBusiness();
      messenger.showSnackBar(
          SnackBar(content: Text('Usaha "${business.name}" dihapus.')));
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
            title: const Text('Profil pembukuan'),
            onTap: () => _editProfile(context),
          ),
        // Pembukuan pribadi tidak dibagikan, jadi tanpa daftar anggota.
        if (!business.isPersonal)
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('Anggota'),
            onTap: () =>
                _push(context, MembersPage(business: business, repo: repo)),
          ),
        ListTile(
          leading: const Icon(Icons.contacts_outlined),
          title: const Text('Kontak Pelanggan'),
          onTap: () => _push(
              context,
              ContactsManagePage(
                  business: business, repo: debtRepo, changes: changes)),
        ),
        ListTile(
          leading: const Icon(Icons.send_outlined),
          title: const Text('Telegram'),
          onTap: () => _push(
              context,
              TelegramPage(
                  businessId: business.id, businessName: business.name)),
        ),
        if (business.canManage) ...[
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Kategori'),
            onTap: () => _push(context, CategoriesPage(repo: repo)),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Backup dan Pemulihan'),
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
            title: const Text('Riwayat aktivitas'),
            onTap: () => _push(context, ActivityPage(repo: repo)),
          ),
        ],
        const Divider(),
        const _Header('Tampilan'),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: ThemeModePicker(),
        ),
        ListenableBuilder(
          listenable: fontController,
          builder: (context, _) => ListTile(
            leading: const Icon(Icons.text_fields_rounded),
            title: const Text('Jenis huruf'),
            subtitle: Text(fontController.font.name),
            onTap: () => showFontPicker(context),
          ),
        ),
        ListenableBuilder(
          listenable: backgroundController,
          builder: (context, _) => ListTile(
            leading: const Icon(Icons.gradient_rounded),
            title: const Text('Latar gradasi'),
            subtitle: Text(backgroundController.enabled
                ? backgroundController.preset.name
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
              title: const Text('Keyboard kalkulator'),
              value: inputPrefs.calcKeypad,
              onChanged: inputPrefs.setCalcKeypad,
            ),
          ),
        ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: const Text('Tampilan Transaksi'),
          onTap: () => _push(context, TxPrefsPage(businessName: business.name)),
        ),
        // Pembukuan Usaha: Saldo Kas disembunyikan kecuali dihidupkan di sini.
        if (business.canSeeProfit)
          ListenableBuilder(
            listenable: homePrefs,
            builder: (context, _) => SwitchListTile(
              secondary: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Tampilkan saldo kas'),
              value: homePrefs.value.showCashBalance,
              onChanged: (v) => homePrefs
                  .update(homePrefs.value.copyWith(showCashBalance: v)),
            ),
          ),
        const Divider(),
        _Header('Akun ($email)'),
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: const Text('Nama tampilan'),
          onTap: () => _changeName(context),
        ),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Ganti password'),
          onTap: () => _changePassword(context),
        ),
        ListTile(
          leading: const Icon(Icons.swap_horiz),
          title: const Text('Pindah / tambah pembukuan'),
          onTap: onSwitchBusiness,
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Keluar dari akun'),
          onTap: () => _signOut(context),
        ),
        const Divider(),
        if (business.role == 'owner')
          ListTile(
            leading:
                Icon(Icons.delete_forever_outlined, color: Colors.red.shade700),
            title: Text('Hapus pembukuan',
                style: TextStyle(color: Colors.red.shade700)),
            onTap: () => _deleteBusiness(context),
          )
        else
          ListTile(
            leading: Icon(Icons.exit_to_app, color: Colors.red.shade700),
            title: Text('Keluar dari pembukuan ini',
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

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.data});

  final Map<String, dynamic> data;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final _name =
      TextEditingController(text: widget.data['name'] as String? ?? '');
  late final _address =
      TextEditingController(text: widget.data['address'] as String? ?? '');
  late final _phone =
      TextEditingController(text: widget.data['phone'] as String? ?? '');

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Profil pembukuan'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nama pembukuan')),
          const SizedBox(height: 12),
          TextField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Alamat')),
          const SizedBox(height: 12),
          TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'No. telepon')),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(context, (_name.text, _address.text, _phone.text));
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
