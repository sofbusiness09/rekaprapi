import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../business/business.dart';
import '../common/dialogs.dart';
import '../common/widgets.dart';
import '../theme/app_theme.dart';
import 'apps_script_client.dart';
import 'backup_settings.dart';
import 'recovery.dart';

/// Pemeriksaan dan penyambungan di sekitar pemulihan. Dapat diganti tiruan saat diuji.
class RestoreBackend {
  SupabaseClient get _db => Supabase.instance.client;

  /// Nama pembukuan lain (yang dikelola pengguna ini) yang backup-nya tersambung ke
  /// [scriptUrl]. Pembukuan milik akun lain tidak terlihat dari sini.
  Future<List<String>> conflicts(String scriptUrl, {String? exceptId}) async {
    try {
      final rows = await _db
          .from('backup_settings')
          .select('business_id')
          .eq('script_url', scriptUrl.trim());
      final ids = [
        for (final r in rows)
          if (r['business_id'] != exceptId) r['business_id'] as String,
      ];
      if (ids.isEmpty) return const [];
      final names = await _db
          .from('businesses')
          .select('name')
          .inFilter('id', ids)
          .isFilter('deleted_at', null);
      return [for (final n in names) n['name'] as String];
    } catch (_) {
      return const [];
    }
  }

  /// Pembukuan belum punya transaksi, utang piutang, atau kontak yang aktif.
  Future<bool> isEmpty(String businessId) async {
    try {
      for (final table in const ['cash_transactions', 'debts', 'contacts']) {
        final rows = await _db
            .from(table)
            .select('id')
            .eq('business_id', businessId)
            .isFilter('deleted_at', null)
            .limit(1);
        if (rows.isNotEmpty) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Menyambungkan backup pembukuan hasil pemulihan ke Google Sheet sumbernya.
  Future<void> connect(String businessId,
          {required String scriptUrl,
          required String token,
          String? spreadsheetUrl}) =>
      BackupSettingsRepository(businessId).save(
          scriptUrl: scriptUrl, token: token, spreadsheetUrl: spreadsheetUrl);
}

/// Pulihkan dari Google Sheet: membaca data pemulihan dari Google Sheet hasil backup
/// lalu memasukkannya sebagai **pembukuan baru**, atau ke pembukuan [target] bila
/// pembukuan itu masih kosong.
///
/// [connected] adalah sheet yang sudah tersambung di pembukuan ini (boleh null).
/// Sumber lain bisa diketik: alamat skrip dan kode rahasia (ada di dalam kode skrip di
/// Google Sheet itu), berguna bila pembukuan aslinya sudah dihapus.
class RestorePage extends StatefulWidget {
  const RestorePage({
    super.key,
    required this.onRestored,
    this.connected,
    this.target,
    AppsScriptClient? client,
    RecoveryImporter? importer,
    RestoreBackend? backend,
  })  : _client = client,
        _importer = importer,
        _backend = backend;

  final BackupSettings? connected;

  /// Pembukuan yang sedang dibuka. Bila pengguna Pemiliknya dan pembukuan masih kosong,
  /// data bisa dipulihkan ke sini alih-alih menjadi pembukuan baru.
  final Business? target;

  /// Dipanggil dengan id pembukuan hasil pemulihan setelah berhasil.
  final Future<void> Function(String businessId) onRestored;

  final AppsScriptClient? _client;
  final RecoveryImporter? _importer;
  final RestoreBackend? _backend;

  @override
  State<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends State<RestorePage> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _name = TextEditingController();
  late final RestoreBackend _backend = widget._backend ?? RestoreBackend();

  RecoveryPayload? _payload;
  String? _savedAt;
  bool _reading = false;
  bool _restoring = false;
  String _step = '';
  double _progress = 0;
  String? _error;
  bool _needsUpdate = false;

  // Sumber yang berhasil dibaca, untuk melanjutkan backup ke sheet yang sama.
  String _srcUrl = '';
  String _srcToken = '';
  String? _srcSheet;

  /// Pembukuan [RestorePage.target] bisa menerima data ini (kosong, jenis sama).
  bool _canUseTarget = false;

  /// true = pulihkan ke pembukuan target; false = jadi pembukuan baru.
  bool _intoTarget = false;

  /// "Lanjutkan backup ke Google Sheet ini".
  bool _keepBackup = true;

  /// Pembukuan lain yang masih backup ke sheet yang sama.
  List<String> _conflicts = const [];

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _name.dispose();
    super.dispose();
  }

  /// Pembukuan target sudah tersambung ke sheet sumber: tidak perlu disambungkan lagi.
  bool get _targetAlreadyConnected =>
      _intoTarget && widget.connected?.scriptUrl.trim() == _srcUrl;

  Future<void> _read(String url, String token) async {
    if (!isValidScriptUrl(url)) {
      setState(() => _error =
          'Alamat harus berbentuk https://script.google.com/macros/s/…/exec');
      return;
    }
    if (token.trim().length < 16) {
      setState(
          () => _error = 'Isi kode rahasia dari kode skrip di Google Sheet.');
      return;
    }
    setState(() {
      _reading = true;
      _error = null;
      _needsUpdate = false;
      _payload = null;
    });
    try {
      final client = widget._client ?? AppsScriptClient();
      final read = await client.readRecovery(url.trim(), token.trim());
      final payload = RecoveryPayload.fromChunks(read.chunks);

      final target = widget.target;
      final canUseTarget = target != null &&
          target.role == 'owner' &&
          target.kind == payload.kind &&
          await _backend.isEmpty(target.id);
      final conflicts = await _backend.conflicts(url, exceptId: target?.id);
      if (!mounted) return;
      setState(() {
        _payload = payload;
        _savedAt = read.savedAt;
        _name.text = '${payload.name} (pulihan)';
        _srcUrl = url.trim();
        _srcToken = token.trim();
        _srcSheet = read.spreadsheetUrl;
        _canUseTarget = canUseTarget;
        _intoTarget = false;
        _conflicts = conflicts;
        // Sheet masih dipakai pembukuan lain: bawaannya tidak disambungkan.
        _keepBackup = conflicts.isEmpty;
      });
    } on BackupException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _needsUpdate = e.code == 'old_script';
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal membaca: $e');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _setKeepBackup(bool value) async {
    if (value && _conflicts.isNotEmpty) {
      final ok = await confirmDialog(
        context,
        title: 'Tetap sambungkan?',
        body:
            'Google Sheet ini masih dipakai untuk backup ${_conflictNames()}. Backup kedua pembukuan akan saling menimpa di sheet yang sama.',
        okLabel: 'Tetap sambungkan',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _keepBackup = value);
  }

  String _conflictNames() =>
      _conflicts.map((n) => 'pembukuan "$n"').join(' dan ');

  Future<void> _restore() async {
    final payload = _payload;
    if (payload == null) return;
    final into = _intoTarget && _canUseTarget;
    final target = widget.target;
    final name = into ? target!.name : _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Isi nama pembukuan baru.');
      return;
    }
    final ok = await confirmDialog(
      context,
      title: into
          ? 'Pulihkan ke pembukuan ini?'
          : 'Pulihkan sebagai pembukuan baru?',
      body: into
          ? 'Data backup (${payload.summary}) akan dimasukkan ke "$name".'
          : '"$name" akan dibuat dari data backup (${payload.summary}). Pembukuan lain tidak diubah.',
      okLabel: 'Pulihkan',
    );
    if (!ok || !mounted) return;
    setState(() {
      _restoring = true;
      _error = null;
      _step = 'Memulai…';
      _progress = 0;
    });
    try {
      final importer = widget._importer ?? RecoveryImporter();
      final id = await importer.restore(payload,
          name: name,
          intoBusinessId: into ? target!.id : null, onProgress: (s, p) {
        if (mounted) {
          setState(() {
            _step = s;
            _progress = p;
          });
        }
      });

      // Menyambungkan backup tidak boleh menggagalkan pemulihan yang sudah berhasil.
      var connectFailed = false;
      if (_keepBackup && !_targetAlreadyConnected) {
        try {
          await _backend.connect(id,
              scriptUrl: _srcUrl, token: _srcToken, spreadsheetUrl: _srcSheet);
        } catch (_) {
          connectFailed = true;
        }
      }

      await widget.onRestored(id);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).popUntil((r) => r.isFirst);
      messenger.showSnackBar(SnackBar(
          content: Text(connectFailed
              ? 'Pembukuan "$name" berhasil dipulihkan, tetapi backup belum tersambung. Sambungkan dari Pengaturan.'
              : 'Pembukuan "$name" berhasil dipulihkan.')));
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = 'Gagal memulihkan: ${e.message}');
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal memulihkan: $e');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final payload = _payload;
    final c = widget.connected;
    final target = widget.target;

    return Scaffold(
      appBar: AppBar(title: const Text('Pulihkan dari Google Sheet')),
      body: ContentWidth(
        maxWidth: 680,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            Text(
              'Data dibaca dari Google Sheet hasil backup, lalu dimasukkan sebagai pembukuan baru. Pembukuan lain tidak diubah.',
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 16),
            if (c != null) ...[
              SoftCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Google Sheet yang tersambung',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _reading || _restoring
                            ? null
                            : () => _read(c.scriptUrl, c.token),
                        icon: const Icon(Icons.cloud_download_rounded),
                        label: const Text('Baca dari sheet ini'),
                      ),
                    ]),
              ),
              const SizedBox(height: 12),
            ],
            SoftCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(c == null ? 'Sumber' : 'Atau sumber lain',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                          labelText: 'Alamat skrip (…/exec)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _token,
                      decoration: const InputDecoration(
                          labelText: 'Kode rahasia (ada di kode skrip)'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _reading || _restoring
                          ? null
                          : () => _read(_url.text, _token.text),
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('Baca data'),
                    ),
                  ]),
            ),
            if (_reading)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error)),
              if (_needsUpdate)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Buka Pengaturan > Backup dan Pemulihan untuk panduan memperbarui skrip.',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
            ],
            if (payload != null) ...[
              const SizedBox(height: 16),
              SoftCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        const IconBadge(Icons.inventory_2_rounded,
                            color: Brand.income),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(payload.name,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600)),
                                Text(
                                    'Pembukuan ${payload.kind.label} · backup ${savedAtLabel(_savedAt ?? payload.createdAt?.toIso8601String())}',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: muted)),
                              ]),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Text(payload.summary, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 16),
                      // Tujuan: pembukuan baru, atau pembukuan ini bila masih kosong.
                      if (_canUseTarget && target != null) ...[
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                                value: false, label: Text('Pembukuan baru')),
                            ButtonSegment(
                                value: true, label: Text('Pembukuan ini')),
                          ],
                          selected: {_intoTarget},
                          onSelectionChanged: _restoring
                              ? null
                              : (s) => setState(() => _intoTarget = s.first),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_intoTarget && target != null)
                        Text(
                            'Data dimasukkan ke "${target.name}" yang masih kosong. Nama dan anggotanya tidak berubah.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted))
                      else
                        TextField(
                          controller: _name,
                          enabled: !_restoring,
                          decoration: const InputDecoration(
                              labelText: 'Nama pembukuan baru'),
                        ),
                      if (!_targetAlreadyConnected) ...[
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                              'Lanjutkan backup ke Google Sheet ini'),
                          subtitle: _conflicts.isEmpty
                              ? const Text(
                                  'Matikan bila pembukuan aslinya masih aktif dan masih backup ke sheet ini.')
                              : null,
                          value: _keepBackup,
                          onChanged: _restoring ? null : _setKeepBackup,
                        ),
                        if (_conflicts.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Brand.pending.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: Brand.pending.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      color: Brand.pending, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                        'Google Sheet ini masih dipakai untuk backup ${_conflictNames()}. Kalau dihidupkan, backup kedua pembukuan akan saling menimpa di sheet yang sama.',
                                        style: theme.textTheme.bodySmall),
                                  ),
                                ]),
                          ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _restoring ? null : _restore,
                        icon: const Icon(Icons.restore_rounded),
                        label: Text(_restoring ? _step : 'Pulihkan'),
                      ),
                      if (_restoring)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(
                              value: _progress == 0 ? null : _progress),
                        ),
                    ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
