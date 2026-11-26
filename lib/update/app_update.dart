import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rekap_rapi/l10n/l10n.dart';

/// Repositori GitHub tempat APK rilis diterbitkan (Releases).
const githubRepo = 'sofbusiness09/rekaprapi';

/// Nama berkas APK yang dilampirkan workflow pada setiap rilis.
const releaseApkName = 'RekapRapi.apk';

/// Penanda di catatan rilis (dari pesan commit) bahwa pembaruan wajib dipasang.
const mandatoryMarker = '[wajib]';

/// Satu rilis di GitHub.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.notes,
    required this.downloadUrl,
    this.mandatory = false,
  });

  /// Tanpa awalan "v", mis. 1.0.16.
  final String version;

  /// Baris catatan perubahan untuk pengguna (penanda wajib sudah dibuang).
  final List<String> notes;
  final String downloadUrl;
  final bool mandatory;

  /// Dari jawaban API `releases/latest`; null bila bentuknya tidak dikenal.
  static AppRelease? fromGithub(Map<String, dynamic> json) {
    final tag = json['tag_name'];
    if (tag is! String || tag.isEmpty) return null;
    final version = tag.replaceFirst(RegExp(r'^[vV]'), '');
    if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(version)) return null;

    var url = json['html_url'] as String? ??
        'https://github.com/$githubRepo/releases/latest';
    for (final a in (json['assets'] as List? ?? const [])) {
      if (a is Map &&
          a['name'] == releaseApkName &&
          a['browser_download_url'] is String) {
        url = a['browser_download_url'] as String;
      }
    }

    final body = (json['body'] as String? ?? '');
    final mandatory = body.toLowerCase().contains(mandatoryMarker);
    final notes = <String>[
      for (final raw in const LineSplitter().convert(body))
        if (raw.trim().isNotEmpty)
          raw
              .replaceAll(
                  RegExp(RegExp.escape(mandatoryMarker), caseSensitive: false),
                  '')
              .replaceFirst(RegExp(r'^\s*[-*•]\s*'), '')
              .trim(),
    ].where((l) => l.isNotEmpty).take(8).toList();

    return AppRelease(
        version: version, notes: notes, downloadUrl: url, mandatory: mandatory);
  }
}

/// Membandingkan versi angka bertitik: negatif bila [a] lebih lama dari [b].
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
        for (final p in v.split('+').first.split('.')) int.tryParse(p) ?? 0,
      ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// Pemeriksa pembaruan aplikasi Android dari GitHub Releases.
class UpdateChecker {
  UpdateChecker({
    http.Client? client,
    DateTime Function()? clock,
    Future<String> Function()? currentVersion,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now,
        _currentVersion = currentVersion ??
            (() async => (await PackageInfo.fromPlatform()).version);

  final http.Client _client;
  final DateTime Function() _clock;
  final Future<String> Function() _currentVersion;

  /// Pemeriksaan otomatis (saat aplikasi dibuka atau kembali dibuka) paling sering
  /// tiap jam. Batas GitHub 60 permintaan per jam per jaringan, jadi aman.
  static const checkEvery = Duration(hours: 1);

  /// "Nanti" menunda pengingat versi yang sama selama sehari.
  static const snoozeFor = Duration(days: 1);

  static const _lastCheckKey = 'update_last_check';
  static String _snoozeKey(String v) => 'update_snooze_$v';

  /// Pembaruan yang perlu ditawarkan, atau null. [force] (dari Pengaturan)
  /// mengabaikan jeda pemeriksaan dan penundaan "Nanti".
  /// Melempar galat jaringan hanya bila [force]; pemeriksaan otomatis diam saja.
  Future<AppRelease?> check({bool force = false}) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null;
    }
    final now = _clock();
    if (!force) {
      final last = prefs?.getInt(_lastCheckKey);
      if (last != null &&
          now.difference(DateTime.fromMillisecondsSinceEpoch(last)) <
              checkEvery) {
        return null;
      }
    }

    final AppRelease? latest;
    try {
      final res = await _client.get(
        Uri.parse('https://api.github.com/repos/$githubRepo/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 404) {
        latest = null; // belum ada rilis sama sekali
      } else if (res.statusCode != 200) {
        throw http.ClientException('GitHub menjawab ${res.statusCode}');
      } else {
        latest = AppRelease.fromGithub(
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
      }
    } catch (e) {
      if (force) rethrow;
      return null;
    }
    await prefs?.setInt(_lastCheckKey, now.millisecondsSinceEpoch);
    if (latest == null) return null;

    final current = await _currentVersion();
    if (compareVersions(latest.version, current) <= 0) return null;

    if (!force && !latest.mandatory) {
      final snoozed = prefs?.getInt(_snoozeKey(latest.version));
      if (snoozed != null &&
          now.difference(DateTime.fromMillisecondsSinceEpoch(snoozed)) <
              snoozeFor) {
        return null;
      }
    }
    return latest;
  }

  Future<void> snooze(AppRelease r) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _snoozeKey(r.version), _clock().millisecondsSinceEpoch);
    } catch (_) {
      // Tanpa penyimpanan, pengingat muncul lagi pada pemeriksaan berikutnya.
    }
  }
}

/// Pembaruan hanya ditawarkan di aplikasi Android; web selalu versi terbaru.
bool get updatesSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Memeriksa lalu menampilkan jendela "Versi baru tersedia" bila ada.
/// Mengembalikan rilis yang ditawarkan, atau null.
bool _updateBusy = false;

Future<AppRelease?> maybeShowUpdate(
  BuildContext context, {
  bool force = false,
  UpdateChecker? checker,
  Future<bool> Function(Uri)? opener,
}) async {
  // Satu pemeriksaan atau satu jendela dalam satu waktu.
  if (_updateBusy) return null;
  _updateBusy = true;
  try {
    final c = checker ?? UpdateChecker();
    final release = await c.check(force: force);
    if (release == null || !context.mounted) return null;
    await showUpdateDialog(context, release, checker: c, opener: opener);
    return release;
  } finally {
    _updateBusy = false;
  }
}

/// Jendela pembaruan. Versi wajib tidak bisa ditutup atau ditunda.
Future<void> showUpdateDialog(
  BuildContext context,
  AppRelease release, {
  UpdateChecker? checker,
  Future<bool> Function(Uri)? opener,
}) {
  final open =
      opener ?? (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
  return showDialog<void>(
    context: context,
    barrierDismissible: !release.mandatory,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return PopScope(
        canPop: !release.mandatory,
        child: AlertDialog(
          title: Text(tr('Versi {0} tersedia', [release.version])),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (release.mandatory)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                        tr(
                            'Pembaruan ini wajib dipasang agar aplikasi tetap berjalan dengan benar.'),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                for (final n in release.notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $n', style: theme.textTheme.bodyMedium),
                  ),
                const SizedBox(height: 8),
                Text(tr('Setelah unduhan selesai, buka berkasnya lalu tekan Pasang. Data Anda tetap aman.'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          actions: [
            if (!release.mandatory)
              TextButton(
                onPressed: () {
                  checker?.snooze(release);
                  Navigator.pop(dialogContext);
                },
                child: Text(tr('Nanti')),
              ),
            FilledButton(
              onPressed: () async {
                await open(Uri.parse(release.downloadUrl));
                // Versi wajib: jendela tetap terbuka sampai versi baru terpasang.
                if (!release.mandatory && dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: Text(tr('Perbarui')),
            ),
          ],
        ),
      );
    },
  );
}
