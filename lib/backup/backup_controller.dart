import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../business/business.dart';
import '../cash/cash_repository.dart';
import '../common/format.dart';
import '../debts/debt_repository.dart';
import 'apps_script_client.dart';
import 'backup_service.dart';
import 'backup_settings.dart';

/// Hasil satu kali backup, siap ditampilkan sebagai pesan singkat.
class BackupOutcome {
  const BackupOutcome(this.ok, this.message);

  final bool ok;
  final String message;
}

/// Status dan aksi Backup Google Sheet satu pembukuan, dipakai ikon awan di bilah atas,
/// backup otomatis harian, dan halaman pengaturan.
class BackupController extends ChangeNotifier {
  BackupController({
    required this.business,
    required this.cash,
    required this.debts,
    DateTime Function()? clock,
  })  : repo = BackupSettingsRepository(business.id),
        _clock = clock ?? DateTime.now;

  final Business business;
  final CashRepository cash;
  final DebtRepository debts;
  final BackupSettingsRepository repo;
  final DateTime Function() _clock;

  BackupSettings? settings;
  bool loading = true;
  Object? loadError;

  bool running = false;
  String step = '';

  /// Backup dan pemulihan hanya untuk Pemilik dan Admin.
  bool get allowed => business.canManage;

  bool get configured => settings != null;

  /// Memuat ulang pengaturan dari akun.
  Future<void> load() async {
    if (!allowed) {
      loading = false;
      notifyListeners();
      return;
    }
    try {
      settings = await repo.load();
      loadError = null;
    } catch (e) {
      loadError = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Titik peringatan di ikon: belum pernah, gagal, atau sudah lebih dari 2 hari.
  bool get needsAttention {
    final s = settings;
    if (s == null) return false;
    final last = s.lastBackupAt;
    if (last == null || !s.lastOk) return true;
    return _clock().difference(last) > const Duration(days: 2);
  }

  /// Sudah waktunya backup otomatis: tiap 24 jam; bila terakhir gagal, coba lagi
  /// setelah 1 jam agar tidak terus mengulang.
  bool get dueForAuto {
    final s = settings;
    if (s == null || !s.autoDaily) return false;
    final last = s.lastBackupAt;
    if (last == null) return true;
    final age = _clock().difference(last);
    return s.lastOk
        ? age >= const Duration(hours: 24)
        : age >= const Duration(hours: 1);
  }

  /// Menjalankan backup. Mengembalikan null bila sedang berjalan atau belum disambungkan.
  Future<BackupOutcome?> run() async {
    final config = settings;
    if (!allowed || config == null || running) return null;
    final user = Supabase.instance.client.auth.currentUser;
    final service = BackupService(
      business: business,
      cash: cash,
      debts: debts,
      settings: repo,
      userId: user?.id,
      userEmail: user?.email,
    );
    running = true;
    step = 'Memulai…';
    notifyListeners();
    try {
      final r = await service.run(config, onStep: (s) {
        step = s;
        notifyListeners();
      });
      final note =
          r.scriptVersion == null || r.scriptVersion! < requiredScriptVersion
              ? ' Skrip Google perlu diperbarui agar data bisa dipulihkan.'
              : '';
      return BackupOutcome(true,
          'Backup selesai ${clockId(_clock())}: ${r.totalRows} baris.$note');
    } on BackupException catch (e) {
      return BackupOutcome(false, 'Backup gagal: ${e.message}');
    } catch (e) {
      return BackupOutcome(false, 'Backup gagal: $e');
    } finally {
      running = false;
      await load();
    }
  }

  /// Dipanggil saat pembukuan dibuka: menjalankan backup bila sudah waktunya.
  /// Pengaturan dimuat ulang dari server lebih dulu agar dua perangkat tidak
  /// mem-backup berbarengan.
  Future<BackupOutcome?> maybeAutoRun() async {
    if (!allowed || running) return null;
    await load();
    if (!dueForAuto) return null;
    final outcome = await run();
    if (outcome == null) return null;
    return BackupOutcome(
        outcome.ok,
        outcome.ok
            ? 'Backup otomatis: ${outcome.message}'
            : 'Backup otomatis gagal. ${outcome.message}');
  }
}
