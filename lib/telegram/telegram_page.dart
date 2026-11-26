import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/dialogs.dart';
import '../common/widgets.dart';
import '../theme/app_theme.dart';
import 'package:rekap_rapi/l10n/l10n.dart';

/// Keadaan sambungan Telegram akun yang sedang masuk.
class TelegramStatus {
  const TelegramStatus({this.bot, this.linked = false, this.name});

  /// Nama pengguna bot; null bila bot belum diaktifkan di server.
  final String? bot;
  final bool linked;

  /// Nama akun Telegram yang terhubung.
  final String? name;

  factory TelegramStatus.fromMap(Map<String, dynamic> m) => TelegramStatus(
        bot: m['bot'] as String?,
        linked: (m['linked'] as bool?) ?? false,
        name: m['name'] as String?,
      );
}

/// Alamat yang membuka bot dan langsung mengirim kode penghubung.
Uri telegramStartLink(String bot, String code) =>
    Uri.parse('https://t.me/$bot?start=$code');

/// Akses ke fungsi Telegram di database. Dapat diganti tiruan saat diuji.
class TelegramRepository {
  SupabaseClient get _db => Supabase.instance.client;

  Future<TelegramStatus> status() async {
    final res = await _db.rpc('telegram_status');
    return TelegramStatus.fromMap(Map<String, dynamic>.from(res as Map));
  }

  /// Membuat kode sekali pakai dan mengembalikan alamat untuk membuka bot.
  Future<Uri> createLink(String businessId) async {
    final res = await _db
        .rpc('telegram_create_code', params: {'p_business': businessId});
    final m = Map<String, dynamic>.from(res as Map);
    return telegramStartLink(m['bot'] as String, m['code'] as String);
  }

  Future<void> unlink() => _db.rpc('telegram_unlink');
}

/// Pengaturan > Telegram: menghubungkan akun ini ke bot agar bisa mencatat lewat chat.
/// Sambungan milik akun (bukan milik pembukuan); pembukuan yang dicatat bisa dipindah
/// dari bot dengan /pembukuan.
class TelegramPage extends StatefulWidget {
  const TelegramPage({
    super.key,
    required this.businessId,
    required this.businessName,
    TelegramRepository? repo,
    Future<bool> Function(Uri)? opener,
  })  : _repo = repo,
        _opener = opener;

  final String businessId;
  final String businessName;
  final TelegramRepository? _repo;
  final Future<bool> Function(Uri)? _opener;

  @override
  State<TelegramPage> createState() => _TelegramPageState();
}

class _TelegramPageState extends State<TelegramPage>
    with WidgetsBindingObserver {
  late final TelegramRepository _repo = widget._repo ?? TelegramRepository();
  TelegramStatus? _status;
  String? _error;
  bool _busy = false;

  /// Alamat terakhir yang dibuat, ditampilkan bila Telegram tidak terbuka sendiri.
  Uri? _link;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Kembali dari Telegram: periksa lagi apakah sudah terhubung.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.status();
      if (!mounted) return;
      setState(() {
        _status = s;
        _error = null;
        if (s.linked) _link = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = tr('Gagal memuat: {0}', [e]));
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      final link = await _repo.createLink(widget.businessId);
      if (!mounted) return;
      setState(() => _link = link);
      final open = widget._opener ??
          (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
      var opened = false;
      try {
        opened = await open(link);
      } catch (_) {
        opened = false;
      }
      if (!opened && mounted) {
        _toast(tr('Telegram tidak terbuka. Salin alamat di bawah.'));
      }
    } on PostgrestException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast(tr('Gagal membuat kode: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await confirmDialog(context,
        title: tr('Putuskan Telegram?'),
        body: tr('Bot tidak lagi bisa mencatat ke pembukuan Anda.'),
        okLabel: tr('Putuskan'));
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _repo.unlink();
      await _load();
      if (mounted) _toast(tr('Telegram diputuskan.'));
    } on PostgrestException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final s = _status;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Telegram'))),
      body: ContentWidth(
        maxWidth: 640,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              if (_error != null)
                Text(_error!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.error))
              else if (s == null)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (s.bot == null)
                EmptyState(
                  icon: Icons.send_rounded,
                  title: tr('Bot Telegram belum diaktifkan'),
                  subtitle:
                      tr('Fitur ini belum disiapkan oleh pengelola aplikasi.'),
                )
              else ...[
                SoftCard(
                  child: Row(children: [
                    IconBadge(Icons.send_rounded,
                        color: s.linked ? Brand.income : Brand.info),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                s.linked
                                    ? tr('Terhubung')
                                    : tr('Belum terhubung'),
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            Text(
                                s.linked
                                    ? '${s.name ?? 'Akun Telegram'} · @${s.bot}'
                                    : '@${s.bot}',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: muted)),
                          ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                if (s.linked) ...[
                  FilledButton.icon(
                    onPressed: () async {
                      final open = widget._opener ??
                          (Uri u) => launchUrl(u,
                              mode: LaunchMode.externalApplication);
                      await open(Uri.parse('https://t.me/${s.bot}'));
                    },
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(tr('Buka bot')),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Brand.expense,
                      side: const BorderSide(color: Brand.expense),
                    ),
                    onPressed: _busy ? null : _disconnect,
                    icon: const Icon(Icons.link_off_rounded),
                    label: Text(tr('Putuskan')),
                  ),
                ] else ...[
                  FilledButton.icon(
                    onPressed: _busy ? null : _connect,
                    icon: const Icon(Icons.link_rounded),
                    label: Text(tr('Hubungkan')),
                  ),
                  if (_link != null) ...[
                    const SizedBox(height: 12),
                    SoftCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(tr('Di Telegram tekan Start. Kode berlaku 10 menit dan hanya sekali pakai.'),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: muted)),
                            const SizedBox(height: 8),
                            SelectableText('$_link',
                                style: theme.textTheme.bodySmall),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    await Clipboard.setData(
                                        ClipboardData(text: '$_link'));
                                    _toast(tr('Alamat disalin.'));
                                  },
                                  icon: const Icon(Icons.copy_rounded),
                                  label: Text(tr('Salin')),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _load,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: Text(tr('Periksa')),
                                ),
                              ),
                            ]),
                          ]),
                    ),
                  ],
                ],
                SectionTitle(tr('Cara mencatat lewat chat')),
                SoftCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in const [
                          'jual 50000 modal 30000 kopi',
                          'masuk 25rb titipan',
                          'keluar 20000 listrik',
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(line,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontFamily: 'monospace')),
                          ),
                        Text(tr('Bot menanyakan konfirmasi sebelum menyimpan. /pembukuan untuk pindah pembukuan, /batal untuk menghapus catatan terakhir.'),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted)),
                      ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
