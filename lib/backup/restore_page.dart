import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../common/dialogs.dart';
import '../common/widgets.dart';
import '../theme/app_theme.dart';
import 'apps_script_client.dart';
import 'backup_settings.dart';
import 'recovery.dart';

/// Pulihkan dari Google Sheet: membaca data pemulihan dari Google Sheet hasil backup
/// lalu memasukkannya sebagai **pembukuan baru**. Pembukuan yang ada tidak diubah.
///
/// [connected] adalah sheet yang sudah tersambung di pembukuan ini (boleh null).
/// Sumber lain bisa diketik: alamat skrip dan kode rahasia (ada di dalam kode skrip di
/// Google Sheet itu), berguna bila pembukuan aslinya sudah dihapus.
class RestorePage extends StatefulWidget {
  const RestorePage({
    super.key,
    required this.onRestored,
    this.connected,
    AppsScriptClient? client,
    RecoveryImporter? importer,
  })  : _client = client,
        _importer = importer;

  final BackupSettings? connected;

  /// Dipanggil dengan id pembukuan baru setelah berhasil.
  final Future<void> Function(String businessId) onRestored;

  final AppsScriptClient? _client;
  final RecoveryImporter? _importer;

  @override
  State<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends State<RestorePage> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _name = TextEditingController();

  RecoveryPayload? _payload;
  String? _savedAt;
  bool _reading = false;
  bool _restoring = false;
  String _step = '';
  double _progress = 0;
  String? _error;
  bool _needsUpdate = false;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _name.dispose();
    super.dispose();
  }

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
      if (!mounted) return;
      setState(() {
        _payload = payload;
        _savedAt = read.savedAt;
        _name.text = '${payload.name} (pulihan)';
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

  Future<void> _restore() async {
    final payload = _payload;
    final name = _name.text.trim();
    if (payload == null) return;
    if (name.isEmpty) {
      setState(() => _error = 'Isi nama pembukuan baru.');
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Pulihkan sebagai pembukuan baru?',
      body:
          '"$name" akan dibuat dari data backup (${payload.summary}). Pembukuan lain tidak diubah.',
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
      final id =
          await importer.restore(payload, name: name, onProgress: (s, p) {
        if (mounted) {
          setState(() {
            _step = s;
            _progress = p;
          });
        }
      });
      await widget.onRestored(id);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).popUntil((r) => r.isFirst);
      messenger.showSnackBar(
          SnackBar(content: Text('Pembukuan "$name" berhasil dipulihkan.')));
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

    return Scaffold(
      appBar: AppBar(title: const Text('Pulihkan dari Google Sheet')),
      body: ContentWidth(
        maxWidth: 680,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            Text(
              'Data dibaca dari Google Sheet hasil backup, lalu dimasukkan sebagai pembukuan baru. Pembukuan yang ada tidak diubah.',
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
                      TextField(
                        controller: _name,
                        enabled: !_restoring,
                        decoration: const InputDecoration(
                            labelText: 'Nama pembukuan baru'),
                      ),
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
