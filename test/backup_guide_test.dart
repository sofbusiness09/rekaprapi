import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/backup/backup_guide.dart';

String _allText(BackupGuide g) => [
      for (final s in g.steps) ...[s.title, ...s.paragraphs, ...s.items],
      ...g.troubleshooting,
    ].join('\n');

void main() {
  final id = buildBackupGuide(GuideLang.id, businessName: 'Toko Rapi');
  final en = buildBackupGuide(GuideLang.en, businessName: 'Toko Rapi');

  test(
      'kedua bahasa punya langkah, sub-langkah, dan bantuan yang sama banyaknya',
      () {
    expect(en.steps.map((s) => s.key), id.steps.map((s) => s.key));
    expect(id.steps.map((s) => s.key), ['sheet', 'code', 'deploy', 'url']);
    for (var i = 0; i < id.steps.length; i++) {
      expect(en.steps[i].items.length, id.steps[i].items.length,
          reason: 'sub-langkah ${id.steps[i].key}');
      expect(en.steps[i].paragraphs.length, id.steps[i].paragraphs.length,
          reason: 'paragraf ${id.steps[i].key}');
    }
    expect(en.troubleshooting.length, id.troubleshooting.length);
  });

  test('penanda tebal seimbang pada semua teks', () {
    for (final g in [id, en]) {
      for (final line in _allText(g).split('\n')) {
        expect('**'.allMatches(line).length.isEven, isTrue, reason: line);
      }
    }
  });

  test('menjelaskan kolom Deskripsi, akses Siapa saja, dan penamaan Sheet', () {
    final deployId =
        id.steps.firstWhere((s) => s.key == 'deploy').items.join('\n');
    expect(deployId, contains('Deskripsi'));
    expect(deployId, contains('opsional'));
    expect(deployId, contains('Jalankan sebagai'));
    expect(deployId, contains('Siapa saja'));
    expect(deployId, contains('/exec'));

    final deployEn =
        en.steps.firstWhere((s) => s.key == 'deploy').items.join('\n');
    expect(deployEn, contains('Description'));
    expect(deployEn, contains('optional'));
    expect(deployEn, contains('Execute as'));
    expect(deployEn, contains('Who has access'));
    expect(deployEn, contains('Anyone'));

    expect(id.steps.first.paragraphs.join(' '), contains('Beri nama'));
    expect(en.steps.first.paragraphs.join(' '), contains('Name it'));
  });

  test('menu Google memakai nama sesuai bahasa', () {
    final textId = _allText(id);
    for (final term in [
      'Ekstensi',
      'Apps Script',
      'Terapkan',
      'Penerapan baru',
      'Pilih jenis',
      'Aplikasi web',
      'Beri otorisasi akses',
      'Lanjutan',
      'Izinkan',
      'Kelola penerapan',
      'Uji penerapan',
    ]) {
      expect(textId, contains(term), reason: 'ID: $term');
    }
    final textEn = _allText(en);
    for (final term in [
      'Extensions',
      'Apps Script',
      'Deploy',
      'New deployment',
      'Select type',
      'Web app',
      'Authorize access',
      'Advanced',
      'Allow',
      'Manage deployments',
      'Test deployments',
    ]) {
      expect(textEn, contains(term), reason: 'EN: $term');
    }
  });

  test('nama usaha masuk ke contoh nama dan karakter berbahaya dibuang', () {
    expect(id.steps.first.paragraphs.join(' '),
        contains('RekapRapi Backup - Toko Rapi'));
    expect(suggestedSheetName('Toko "A" [B]/C'),
        'RekapRapi Backup - Toko  A   B  C');
    expect(suggestedSheetName('   '), 'RekapRapi Backup - Usaha');
  });

  test('tidak ada penanda tempat yang tertinggal', () {
    for (final g in [id, en]) {
      final text = _allText(g);
      expect(text.contains('{name}'), isFalse);
      expect(text.contains('\$name'), isFalse);
    }
  });
}
