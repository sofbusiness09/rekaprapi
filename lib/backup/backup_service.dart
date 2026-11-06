import '../business/business.dart';
import '../cash/cash_models.dart';
import '../cash/cash_repository.dart';
import '../debts/debt_models.dart';
import '../debts/debt_repository.dart';
import 'apps_script_client.dart';
import 'backup_settings.dart';
import 'backup_sheets.dart';
import 'recovery.dart';

/// Menjalankan satu kali backup: mengambil SEMUA data usaha, menyusunnya menjadi lembar,
/// mengirimnya ke Google Sheet, lalu mencatat hasilnya.
class BackupService {
  BackupService({
    required this.business,
    required this.cash,
    required this.debts,
    required this.settings,
    this.userId,
    this.userEmail,
    AppsScriptClient? client,
  }) : _client = client ?? AppsScriptClient();

  final Business business;
  final CashRepository cash;
  final DebtRepository debts;
  final BackupSettingsRepository settings;

  /// Pengguna yang menjalankan backup; namanya dicatat di lembar Info.
  final String? userId;
  final String? userEmail;
  final AppsScriptClient _client;

  /// Mengumpulkan seluruh data usaha (semua waktu).
  Future<BackupData> gather() async {
    final from = DateTime(2000);
    final to = DateTime(2100, 12, 31);
    final r = await Future.wait<Object>([
      cash.summary(from, to),
      cash.listAll(from, to),
      cash.categories(),
      cash.memberNames(),
      debts.debts(),
      debts.contacts(),
      debts.allPayments(),
    ]);
    final names = r[3] as Map<String, String>;
    return BackupData(
      businessName: business.name,
      generatedAt: DateTime.now(),
      generatedBy:
          (userId == null ? null : names[userId]) ?? userEmail ?? 'Pengguna',
      summary: r[0] as Summary,
      cash: r[1] as List<CashTx>,
      categories: {for (final c in r[2] as List<Category>) c.id: c.name},
      memberNames: names,
      debts: r[4] as List<Debt>,
      contacts: r[5] as List<Contact>,
      payments: r[6] as List<Map<String, dynamic>>,
    );
  }

  /// [onStep] menerima keterangan langkah untuk ditampilkan saat berjalan.
  Future<BackupResult> run(
    BackupSettings config, {
    void Function(String step)? onStep,
  }) async {
    try {
      onStep?.call('Mengambil data usaha…');
      final data = await gather();
      final sheets = buildBackupSheets(data);

      // Data lengkap untuk fitur Pulihkan dari Google Sheet (lembar tersembunyi).
      onStep?.call('Menyiapkan data pemulihan…');
      final recovery = (await RecoveryExporter(business).export()).toChunks();

      onStep?.call('Mengirim ke Google Sheet…');
      final result = await _client.send(config.scriptUrl, config.token, sheets,
          recovery: recovery);

      onStep?.call('Mencatat hasil…');
      await settings.recordSuccess(result);
      return result;
    } on BackupException catch (e) {
      await settings.recordFailure(e.message);
      rethrow;
    } catch (e) {
      await settings.recordFailure('Gagal mengambil data: $e');
      rethrow;
    }
  }
}
