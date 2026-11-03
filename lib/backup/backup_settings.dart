import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'apps_script_client.dart';

/// Pengaturan Backup Google Sheet satu usaha (alamat skrip, kode rahasia, hasil terakhir).
class BackupSettings {
  const BackupSettings({
    required this.scriptUrl,
    required this.token,
    this.spreadsheetUrl,
    this.lastBackupAt,
    this.lastStatus,
    this.lastSummary,
  });

  final String scriptUrl;
  final String token;
  final String? spreadsheetUrl;
  final DateTime? lastBackupAt;

  /// 'ok' atau pesan galat dari backup terakhir.
  final String? lastStatus;

  /// Nama lembar -> jumlah baris pada backup terakhir.
  final Map<String, int>? lastSummary;

  bool get lastOk => lastStatus == 'ok';

  int get lastTotalRows =>
      lastSummary?.values.fold<int>(0, (s, n) => s + n) ?? 0;

  factory BackupSettings.fromMap(Map<String, dynamic> m) => BackupSettings(
        scriptUrl: m['script_url'] as String,
        token: m['token'] as String,
        spreadsheetUrl: m['spreadsheet_url'] as String?,
        lastBackupAt: m['last_backup_at'] == null
            ? null
            : DateTime.parse(m['last_backup_at'] as String).toLocal(),
        lastStatus: m['last_status'] as String?,
        lastSummary: m['last_summary'] == null
            ? null
            : {
                for (final e in (m['last_summary'] as Map).entries)
                  e.key as String: (e.value as num).toInt(),
              },
      );
}

/// Kode rahasia acak yang membuat skrip hanya menerima permintaan dari RekapRapi.
String generateBackupToken([Random? random]) {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final r = random ?? Random.secure();
  return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Akses tabel backup_settings. Hanya Pemilik dan Admin yang diizinkan oleh database.
class BackupSettingsRepository {
  BackupSettingsRepository(this.businessId);

  final String businessId;
  SupabaseClient get _db => Supabase.instance.client;

  Future<BackupSettings?> load() async {
    final row = await _db
        .from('backup_settings')
        .select()
        .eq('business_id', businessId)
        .maybeSingle();
    return row == null ? null : BackupSettings.fromMap(row);
  }

  Future<void> save({
    required String scriptUrl,
    required String token,
    String? spreadsheetUrl,
  }) async {
    await _db.from('backup_settings').upsert({
      'business_id': businessId,
      'script_url': scriptUrl.trim(),
      'token': token,
      'spreadsheet_url': spreadsheetUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'business_id');
  }

  Future<void> recordSuccess(BackupResult r) async {
    await _db.from('backup_settings').update({
      'last_backup_at': DateTime.now().toUtc().toIso8601String(),
      'last_backup_by': _db.auth.currentUser?.id,
      'last_status': 'ok',
      'last_summary': r.sheets,
      if (r.spreadsheetUrl != null) 'spreadsheet_url': r.spreadsheetUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('business_id', businessId);
  }

  Future<void> recordFailure(String message) async {
    try {
      await _db.from('backup_settings').update({
        'last_backup_at': DateTime.now().toUtc().toIso8601String(),
        'last_backup_by': _db.auth.currentUser?.id,
        'last_status':
            message.length > 300 ? message.substring(0, 300) : message,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('business_id', businessId);
    } catch (_) {
      // Mencatat kegagalan tidak boleh menutupi galat aslinya.
    }
  }

  Future<void> delete() async {
    await _db.from('backup_settings').delete().eq('business_id', businessId);
  }
}
