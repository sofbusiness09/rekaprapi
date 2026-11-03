import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/dialogs.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../theme/app_theme.dart';
import 'apps_script_client.dart';
import 'backup_guide.dart';
import 'backup_settings.dart';

/// Membuka alamat di browser/aplikasi lain; mengembalikan false bila gagal.
Future<bool> openLink(String url) async {
  try {
    return await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Teks dengan penanda **tebal** menjadi huruf tebal (untuk nama menu Google).
class _Rich extends StatelessWidget {
  const _Rich(this.markup, {this.style});

  final String markup;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final parts = markup.split('**');
    return Text.rich(TextSpan(children: [
      for (var i = 0; i < parts.length; i++)
        TextSpan(
          text: parts[i],
          style: i.isOdd ? base.copyWith(fontWeight: FontWeight.w700) : base,
        ),
    ]));
  }
}

/// Pengaturan > Backup Google Sheet: langkah menyambungkan Google Sheet Anda.
/// Hanya Pemilik dan Admin (database menolak peran lain).
class BackupSetupPage extends StatefulWidget {
  const BackupSetupPage(
      {super.key, required this.repo, required this.businessName});

  final BackupSettingsRepository repo;
  final String businessName;

  @override
  State<BackupSetupPage> createState() => _BackupSetupPageState();
}

class _BackupSetupPageState extends State<BackupSetupPage> {
  static const _placeholder = '__KODE_RAHASIA__';

  final _url = TextEditingController();
  BackupSettings? _saved;
  String _token = generateBackupToken();
  String? _scriptTemplate;
  bool _loading = true;
  bool _busy = false;
  bool _showCode = false;
  String? _error;
  Object? _loadError;

  // Bahasa panduan mengikuti bahasa perangkat; bisa diganti agar cocok dengan akun Google.
  GuideLang _lang = PlatformDispatcher.instance.locale.languageCode == 'id'
      ? GuideLang.id
      : GuideLang.en;

  bool get _id => _lang == GuideLang.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object?>([
        widget.repo.load(),
        rootBundle.loadString('assets/backup_apps_script.gs'),
      ]);
      final saved = results[0] as BackupSettings?;
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _scriptTemplate = results[1] as String;
        if (saved != null) {
          _token = saved.token;
          _url.text = saved.scriptUrl;
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  /// Kode skrip dengan kode rahasia akun ini sudah terisi, siap ditempel.
  String get _code =>
      (_scriptTemplate ?? '').replaceFirst(_placeholder, _token);

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _copy(String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast(done);
  }

  Future<void> _connect() async {
    final url = _url.text.trim();
    if (!isValidScriptUrl(url)) {
      setState(() => _error = _id
          ? 'Alamat harus berbentuk https://script.google.com/macros/s/…/exec'
          : 'The address must look like https://script.google.com/macros/s/…/exec');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final spreadsheetUrl = await AppsScriptClient().ping(url, _token);
      await widget.repo
          .save(scriptUrl: url, token: _token, spreadsheetUrl: spreadsheetUrl);
      await _load();
      _toast(
          _id ? 'Tersambung ke Google Sheet.' : 'Connected to Google Sheets.');
    } on BackupException catch (e) {
      setState(() => _error = e.message);
    } on PostgrestException catch (e) {
      setState(() => _error = 'Gagal menyimpan pengaturan: ${e.message}');
    } catch (e) {
      setState(() => _error = 'Gagal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await confirmDialog(context,
        title: 'Hapus pengaturan backup?',
        body:
            'Alamat dan kode rahasia dihapus dari RekapRapi. Google Sheet Anda dan isinya tidak dihapus.',
        okLabel: 'Hapus');
    if (!ok) return;
    try {
      await widget.repo.delete();
      if (!mounted) return;
      setState(() {
        _saved = null;
        _url.clear();
        _token =
            generateBackupToken(); // kode rahasia baru untuk sambungan berikutnya
        _error = null;
      });
      _toast('Pengaturan backup dihapus.');
    } on PostgrestException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Backup Google Sheet')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: EmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: 'Pengaturan backup belum bisa dimuat',
                    subtitle:
                        '$_loadError\n\nPastikan migrasi 20261109000000_backup_settings.sql sudah dijalankan dan Anda Pemilik atau Admin.',
                  ),
                )
              : ContentWidth(
                  maxWidth: 680,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                    children: [
                      Text(
                        'Simpan salinan seluruh data usaha (kas, utang piutang, kontak) ke Google Sheet Anda dengan satu klik. '
                        'Setiap backup menimpa isi sheet dengan data terbaru.',
                        style:
                            theme.textTheme.bodyMedium?.copyWith(color: muted),
                      ),
                      const SizedBox(height: 16),
                      if (_saved != null) _StatusCard(settings: _saved!),
                      ..._guide(theme),
                      const SizedBox(height: 4),
                      SoftCard(
                        color: Brand.info.withValues(alpha: 0.08),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.shield_outlined,
                                color: Brand.info),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _id
                                    ? 'Keamanan: skrip hanya meminta izin untuk Google Sheet tempat ia ditempel, dan menolak permintaan tanpa kode rahasia yang sudah tertanam di kode di atas. '
                                        'Jangan bagikan alamat atau kode itu. Data hanya dikirim dari RekapRapi ke Google Sheet Anda sendiri.'
                                    : 'Security: the script only asks permission for the Google Sheet it is pasted into, and rejects any request without the secret code embedded in the code above. '
                                        'Do not share the address or the code. Data is only sent from RekapRapi to your own Google Sheet.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_saved != null) ...[
                        const SizedBox(height: 20),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Brand.expense),
                          onPressed: _disconnect,
                          icon: const Icon(Icons.link_off_rounded),
                          label: const Text('Hapus pengaturan backup'),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  /// Panduan bertahap dalam bahasa terpilih, beserta tombol dan isian di tiap langkah.
  List<Widget> _guide(ThemeData theme) {
    final guide = buildBackupGuide(_lang, businessName: widget.businessName);
    final l = guide.labels;
    final muted = theme.colorScheme.onSurfaceVariant;

    return [
      SectionTitle(l.sectionTitle),
      Row(children: [
        SegmentedButton<GuideLang>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: GuideLang.id, label: Text('Indonesia')),
            ButtonSegment(value: GuideLang.en, label: Text('English')),
          ],
          selected: {_lang},
          onSelectionChanged: (s) => setState(() => _lang = s.first),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
        child: Text(l.languageHint,
            style: theme.textTheme.bodySmall?.copyWith(color: muted)),
      ),
      for (var i = 0; i < guide.steps.length; i++)
        _Step(
          number: i + 1,
          title: guide.steps[i].title,
          paragraphs: guide.steps[i].paragraphs,
          items: guide.steps[i].items,
          extra: _extra(guide.steps[i].key, guide, theme),
        ),
      _Troubleshooting(
          title: l.troubleshootingTitle, items: guide.troubleshooting),
    ];
  }

  /// Tombol dan isian yang menyertai satu langkah panduan.
  Widget? _extra(String key, BackupGuide guide, ThemeData theme) {
    final l = guide.labels;
    final muted = theme.colorScheme.onSurfaceVariant;

    switch (key) {
      case 'sheet':
        final name = suggestedSheetName(widget.businessName);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () async {
              if (!await openLink('https://sheets.new')) {
                _toast(_id
                    ? 'Buka sheets.new di browser Anda.'
                    : 'Open sheets.new in your browser.');
              }
            },
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(l.openSheets),
          ),
          const SizedBox(height: 12),
          Text(l.suggestedName,
              style: theme.textTheme.labelMedium?.copyWith(color: muted)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            IconButton(
              tooltip: l.copyName,
              icon: const Icon(Icons.copy_rounded, size: 20),
              onPressed: () => _copy(name, l.nameCopied),
            ),
          ]),
        ]);
      case 'code':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => _copy(_code, l.codeCopied),
              icon: const Icon(Icons.copy_rounded),
              label: Text(l.copyCode),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => setState(() => _showCode = !_showCode),
              child: Text(_showCode ? l.hideCode : l.showCode),
            ),
          ]),
          if (_showCode) ...[
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _code,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ]);
      case 'url':
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: _id
                      ? 'URL aplikasi web (…/exec)'
                      : 'Web app URL (…/exec)',
                  prefixIcon: const Icon(Icons.link_rounded),
                  errorText: _error,
                  errorMaxLines: 4,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _connect,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : Text(_saved == null
                        ? (_id
                            ? 'Simpan dan uji koneksi'
                            : 'Save and test connection')
                        : (_id
                            ? 'Simpan perubahan dan uji koneksi'
                            : 'Save changes and test connection')),
              ),
            ]);
    }
    return null;
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.settings});

  final BackupSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final s = settings;
    final never = s.lastBackupAt == null;
    final failed = !never && !s.lastOk;

    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconBadge(
              failed ? Icons.error_outline_rounded : Icons.cloud_done_rounded,
              color: failed ? Brand.expense : Brand.income),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tersambung',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                never
                    ? 'Belum pernah dibackup.'
                    : failed
                        ? 'Backup terakhir gagal (${timeId(s.lastBackupAt!)}): ${s.lastStatus}'
                        : 'Backup terakhir ${timeId(s.lastBackupAt!)} · ${s.lastTotalRows} baris',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: failed ? Brand.expense : muted),
              ),
            ]),
          ),
        ]),
        if (s.spreadsheetUrl != null) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => openLink(s.spreadsheetUrl!),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Buka Google Sheet'),
          ),
        ],
      ]),
    );
  }
}

/// Satu langkah panduan: nomor, judul, paragraf, sub-langkah bernomor, dan isian tambahan.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.paragraphs,
    required this.items,
    this.extra,
  });

  final int number;
  final String title;
  final List<String> paragraphs;
  final List<String> items;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text('$number',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onPrimaryContainer)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final p in paragraphs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _Rich(p, style: body),
                ),
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text('$number.${i + 1}',
                            style: body?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700)),
                      ),
                      Expanded(child: _Rich(items[i], style: body)),
                    ],
                  ),
                ),
              if (extra != null) ...[
                const SizedBox(height: 4),
                extra!,
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Troubleshooting extends StatelessWidget {
  const _Troubleshooting({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        padding: EdgeInsets.zero,
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: Text(title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final t in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(
                          child: _Rich(t, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
