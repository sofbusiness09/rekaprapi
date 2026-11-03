import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../business/business.dart';
import '../cash/cash_repository.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../debts/debt_repository.dart';
import '../theme/app_theme.dart';
import 'apps_script_client.dart';
import 'backup_service.dart';
import 'backup_settings.dart';
import 'backup_setup_page.dart';

/// Kartu "Backup ke Google Sheet" di Laporan: satu klik menimpa Google Sheet
/// dengan data terbaru. Hanya untuk Pemilik dan Admin.
class BackupCard extends StatefulWidget {
  const BackupCard({
    super.key,
    required this.business,
    required this.cash,
    required this.debts,
  });

  final Business business;
  final CashRepository cash;
  final DebtRepository debts;

  @override
  State<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<BackupCard> {
  late final _repo = BackupSettingsRepository(widget.business.id);
  BackupSettings? _settings;
  bool _loading = true;
  Object? _loadError;
  bool _running = false;
  String _step = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.load();
      if (!mounted) return;
      setState(() {
        _settings = s;
        _loadError = null;
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

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _openSetup() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          BackupSetupPage(repo: _repo, businessName: widget.business.name),
    ));
    if (mounted) {
      setState(() => _loading = true);
      await _load();
    }
  }

  Future<void> _backup() async {
    final config = _settings;
    if (config == null) return;
    final user = Supabase.instance.client.auth.currentUser;
    final service = BackupService(
      business: widget.business,
      cash: widget.cash,
      debts: widget.debts,
      settings: _repo,
      userId: user?.id,
      userEmail: user?.email,
    );
    setState(() {
      _running = true;
      _step = 'Memulai…';
    });
    try {
      final r = await service.run(
        config,
        onStep: (s) {
          if (mounted) setState(() => _step = s);
        },
      );
      _toast(
          'Backup selesai: ${r.totalRows} baris di ${r.sheets.length} lembar.');
    } on BackupException catch (e) {
      _toast('Backup gagal: ${e.message}');
    } catch (e) {
      _toast('Backup gagal: $e');
    } finally {
      if (mounted) {
        setState(() => _running = false);
        await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    if (_loading) {
      return const SoftCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5)),
          ),
        ),
      );
    }

    if (_loadError != null) {
      return SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Fitur backup belum siap.',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Pastikan migrasi 20261109000000_backup_settings.sql sudah dijalankan di Supabase.\n$_loadError',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _load, child: const Text('Coba lagi')),
        ]),
      );
    }

    final s = _settings;
    if (s == null) {
      return SoftCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const IconBadge(Icons.cloud_upload_rounded, color: Brand.info),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Simpan salinan seluruh data ke Google Sheet Anda dengan satu klik.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ]),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: _openSetup,
            icon: const Icon(Icons.settings_suggest_rounded),
            label: const Text('Atur backup Google Sheet'),
          ),
        ]),
      );
    }

    final never = s.lastBackupAt == null;
    final failed = !never && !s.lastOk;
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconBadge(
              failed ? Icons.error_outline_rounded : Icons.cloud_done_rounded,
              color: failed ? Brand.expense : Brand.income),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  never
                      ? 'Belum pernah dibackup'
                      : failed
                          ? 'Backup terakhir gagal'
                          : 'Backup terakhir',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                never
                    ? 'Tekan Backup sekarang untuk menyimpan data pertama kali.'
                    : failed
                        ? '${timeId(s.lastBackupAt!)} · ${s.lastStatus}'
                        : '${timeId(s.lastBackupAt!)} · ${s.lastTotalRows} baris',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: failed ? Brand.expense : muted),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _running ? null : _backup,
          icon: const Icon(Icons.cloud_upload_rounded),
          label: Text(_running ? _step : 'Backup sekarang'),
        ),
        if (_running)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 4),
        Row(children: [
          if (s.spreadsheetUrl != null)
            TextButton.icon(
              onPressed: () async {
                if (!await openLink(s.spreadsheetUrl!)) {
                  _toast('Tidak bisa membuka Google Sheet.');
                }
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Buka Google Sheet'),
            ),
          const Spacer(),
          TextButton(onPressed: _openSetup, child: const Text('Pengaturan')),
        ]),
      ]),
    );
  }
}
