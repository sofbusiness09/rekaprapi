import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'backup_sheets.dart';

/// Galat backup dengan pesan yang bisa langsung ditampilkan ke pengguna.
class BackupException implements Exception {
  const BackupException(this.message, {this.code});

  final String message;

  /// Kode dari skrip, mis. 'no_recovery' bila Google Sheet belum berisi data pemulihan.
  final String? code;

  @override
  String toString() => message;
}

/// Hasil backup yang berhasil.
class BackupResult {
  const BackupResult(this.sheets, this.spreadsheetUrl,
      {this.scriptVersion, this.recoveryChunks = 0});

  /// Nama lembar -> jumlah baris data.
  final Map<String, int> sheets;
  final String? spreadsheetUrl;

  /// Versi skrip Google yang menjawab; null untuk skrip lama (versi 1).
  final int? scriptVersion;

  /// Jumlah potongan data pemulihan yang tersimpan (0 bila skrip lama).
  final int recoveryChunks;

  int get totalRows => sheets.values.fold(0, (s, n) => s + n);
}

/// Alamat Web App Google Apps Script yang sah (pribadi atau domain Google Workspace).
final scriptUrlPattern = RegExp(
    r'^https://script\.google\.com/(a/macros/[^/]+|macros)/s/[A-Za-z0-9_-]+/exec$');

bool isValidScriptUrl(String url) => scriptUrlPattern.hasMatch(url.trim());

/// Versi skrip yang dibutuhkan fitur Pulihkan dari Google Sheet.
const requiredScriptVersion = 2;

/// Keterangan skrip dari pemeriksaan sambungan.
class ScriptInfo {
  const ScriptInfo({this.spreadsheetUrl, this.version});

  final String? spreadsheetUrl;

  /// Null untuk skrip lama yang belum menyebut versi.
  final int? version;

  bool get current => (version ?? 1) >= requiredScriptVersion;
}

/// Isi lembar pemulihan yang dibaca dari Google Sheet.
class RecoveryRead {
  const RecoveryRead(this.chunks, {this.savedAt, this.spreadsheetUrl});

  final List<String> chunks;
  final String? savedAt;
  final String? spreadsheetUrl;
}

/// Mengirim data ke skrip Google Apps Script milik pengguna.
class AppsScriptClient {
  AppsScriptClient(
      {http.Client? client, this.timeout = const Duration(minutes: 3)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  /// Memeriksa alamat dan kode rahasia tanpa menulis apa pun.
  /// Mengembalikan alamat spreadsheet bila skrip memberikannya.
  Future<String?> ping(String url, String token) async =>
      (await pingInfo(url, token)).spreadsheetUrl;

  /// Seperti [ping], tetapi juga mengembalikan versi skrip.
  Future<ScriptInfo> pingInfo(String url, String token) async {
    final json = await _post(url, {'token': token, 'ping': true});
    return ScriptInfo(
      spreadsheetUrl: json['spreadsheetUrl'] as String?,
      version: (json['version'] as num?)?.toInt(),
    );
  }

  /// Membaca data pemulihan dari Google Sheet. Skrip lama (tanpa fitur ini) menjawab
  /// tanpa potongan; itu dilaporkan sebagai galat agar pengguna memperbarui skripnya.
  Future<RecoveryRead> readRecovery(String url, String token) async {
    final json = await _post(url, {'token': token, 'read': true});
    final chunks = json['chunks'];
    if (chunks is! List) {
      throw const BackupException(
          'Skrip Google Anda belum mendukung pemulihan. Perbarui skripnya ke versi terbaru, lalu jalankan Backup sekali.',
          code: 'old_script');
    }
    return RecoveryRead(
      [for (final c in chunks) c.toString()],
      savedAt: json['savedAt'] as String?,
      spreadsheetUrl: json['spreadsheetUrl'] as String?,
    );
  }

  /// Menimpa lembar-lembar di Google Sheet dengan data terbaru.
  ///
  /// [recovery] adalah data pemulihan yang sudah dipotong (lihat RecoveryPayload);
  /// skrip versi 2 menyimpannya di lembar tersembunyi.
  Future<BackupResult> send(String url, String token, List<BackupSheet> sheets,
      {List<String>? recovery}) async {
    final json = await _post(url, {
      'token': token,
      'sheets': [for (final s in sheets) s.toJson()],
      if (recovery != null) 'recovery': {'format': 1, 'chunks': recovery},
    });
    final counts = <String, int>{
      for (final e in (json['sheets'] as Map? ?? const {}).entries)
        e.key as String: (e.value as num).toInt(),
    };
    return BackupResult(counts, json['spreadsheetUrl'] as String?,
        scriptVersion: (json['version'] as num?)?.toInt(),
        recoveryChunks: (json['recoveryChunks'] as num?)?.toInt() ?? 0);
  }

  Future<Map<String, dynamic>> _post(
      String url, Map<String, dynamic> body) async {
    if (!isValidScriptUrl(url)) {
      throw const BackupException(
          'Alamat bukan alamat aplikasi web Google Apps Script yang berakhiran /exec.');
    }
    try {
      // text/plain menghindari permintaan pra-periksa (preflight) yang tidak
      // dilayani Apps Script.
      final request = http.Request('POST', Uri.parse(url.trim()))
        ..headers['Content-Type'] = 'text/plain;charset=utf-8'
        ..body = jsonEncode(body);
      // Apps Script menjawab dengan pengalihan (302); di aplikasi seluler pengalihan
      // untuk POST harus diikuti sendiri. Peramban mengikutinya otomatis.
      if (!kIsWeb) request.followRedirects = false;

      // Batas waktu mencakup seluruh perjalanan (kirim, ikuti pengalihan, baca jawaban),
      // bukan hanya pembacaan jawaban; kalau tidak, server yang diam membuat tombol menggantung.
      final response = await _roundTrip(request).timeout(timeout);
      final text = utf8.decode(response.bodyBytes);
      final Object? decoded;
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        throw BackupException(
            'Google tidak memberi jawaban yang benar (status ${response.statusCode}). '
            'Pastikan penerapan aplikasi web diatur "Yang memiliki akses: Siapa saja" '
            'dan alamatnya berakhiran /exec.');
      }
      if (decoded is! Map<String, dynamic>) {
        throw const BackupException('Jawaban dari Google tidak dikenali.');
      }
      if (decoded['ok'] != true) {
        throw BackupException(
            (decoded['error'] as String?) ??
                'Backup ditolak oleh skrip Google.',
            code: decoded['code'] as String?);
      }
      return decoded;
    } on BackupException {
      rethrow;
    } on TimeoutException {
      throw const BackupException(
          'Google terlalu lama menjawab. Coba lagi beberapa saat lagi.');
    } on http.ClientException {
      throw const BackupException(
          'Tidak bisa menghubungi Google. Periksa koneksi internet Anda.');
    }
  }

  Future<http.Response> _roundTrip(http.Request request) async {
    var response = await http.Response.fromStream(await _client.send(request));
    var hops = 0;
    while (
        {301, 302, 303, 307, 308}.contains(response.statusCode) && hops < 5) {
      final location = response.headers['location'];
      if (location == null) break;
      response = await _client.get(Uri.parse(location));
      hops++;
    }
    return response;
  }

  void close() => _client.close();
}
