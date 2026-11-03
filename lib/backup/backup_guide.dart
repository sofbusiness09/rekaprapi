/// Bahasa panduan sekaligus bahasa nama menu Google yang disebut di dalamnya.
/// Pengguna yang akun Google-nya berbahasa Inggris melihat menu persis seperti di layar mereka.
enum GuideLang { id, en }

/// Satu langkah panduan. Teks memakai penanda **tebal** untuk nama menu dan tombol Google.
class GuideStep {
  const GuideStep({
    required this.key,
    required this.title,
    this.paragraphs = const [],
    this.items = const [],
  });

  /// 'sheet' | 'code' | 'deploy' | 'url' — menentukan tombol/isian apa yang ditambahkan di bawahnya.
  final String key;
  final String title;
  final List<String> paragraphs;

  /// Sub-langkah bernomor.
  final List<String> items;
}

/// Teks tombol dan judul yang ikut berganti bahasa bersama panduan.
class GuideLabels {
  const GuideLabels({
    required this.sectionTitle,
    required this.languageHint,
    required this.openSheets,
    required this.copyName,
    required this.nameCopied,
    required this.copyCode,
    required this.showCode,
    required this.hideCode,
    required this.codeCopied,
    required this.troubleshootingTitle,
    required this.suggestedName,
  });

  final String sectionTitle;
  final String languageHint;
  final String openSheets;
  final String copyName;
  final String nameCopied;
  final String copyCode;
  final String showCode;
  final String hideCode;
  final String codeCopied;
  final String troubleshootingTitle;
  final String suggestedName;
}

class BackupGuide {
  const BackupGuide({
    required this.labels,
    required this.steps,
    required this.troubleshooting,
  });

  final GuideLabels labels;
  final List<GuideStep> steps;
  final List<String> troubleshooting;
}

/// Nama spreadsheet yang disarankan; tanda kutip dibuang agar aman disalin.
String suggestedSheetName(String businessName) {
  final clean = businessName.replaceAll(RegExp(r'["\[\]\\/*?:]'), ' ').trim();
  return 'RekapRapi Backup - ${clean.isEmpty ? 'Usaha' : clean}';
}

BackupGuide buildBackupGuide(GuideLang lang, {required String businessName}) {
  final name = suggestedSheetName(businessName);
  return lang == GuideLang.id ? _id(name) : _en(name);
}

BackupGuide _id(String name) => BackupGuide(
      labels: const GuideLabels(
        sectionTitle: 'Cara menyambungkan',
        languageHint:
            'Pilih bahasa yang sama dengan tampilan akun Google Anda agar nama menunya cocok.',
        openSheets: 'Buka sheets.new',
        copyName: 'Salin nama',
        nameCopied: 'Nama disalin.',
        copyCode: 'Salin kode skrip',
        showCode: 'Lihat kode',
        hideCode: 'Sembunyikan kode',
        codeCopied: 'Kode skrip disalin. Tempel di Apps Script.',
        troubleshootingTitle: 'Jika gagal',
        suggestedName: 'Nama yang disarankan',
      ),
      steps: [
        GuideStep(
          key: 'sheet',
          title: 'Buat Google Sheet baru dan beri nama',
          paragraphs: [
            'Klik tombol di bawah untuk membuat Google Sheet kosong, atau buka **sheets.google.com** lalu pilih **Spreadsheet kosong**.',
            'Beri nama: klik judul di kiri atas (bawaannya **Spreadsheet tanpa judul**), ketik namanya, lalu tekan Enter. Contoh: **$name**. Nama bebas dan tidak memengaruhi cara kerja backup, tetapi nama yang jelas memudahkan Anda mencarinya nanti.',
            'Sebaiknya pakai Sheet khusus backup. Setiap backup menimpa lembar bernama **Info, Ringkasan, Kas, Piutang, Utang, Pembayaran, Kontak**. Lembar lain di Sheet itu tidak disentuh.',
          ],
        ),
        const GuideStep(
          key: 'code',
          title: 'Tempel kode skrip',
          items: [
            'Di Google Sheet, buka menu **Ekstensi** > **Apps Script**. Editor skrip terbuka di tab baru.',
            'Di editor sudah ada kode bawaan (**function myFunction() { }**). Klik di dalam kode itu, tekan **Ctrl+A**, lalu **Delete** untuk menghapus semuanya.',
            'Klik **Salin kode skrip** di bawah, lalu tempel di editor dengan **Ctrl+V**. Kode ini sudah berisi kode rahasia khusus untuk usaha Anda.',
            'Klik ikon disket **Simpan project** (atau tekan **Ctrl+S**). Jika diminta nama project, isi bebas, misalnya **RekapRapi Backup**.',
          ],
        ),
        const GuideStep(
          key: 'deploy',
          title: 'Terapkan sebagai aplikasi web',
          items: [
            'Di editor Apps Script, klik tombol biru **Terapkan** (kanan atas) > **Penerapan baru**.',
            'Di jendela yang muncul, klik ikon roda gigi di samping **Pilih jenis**, lalu pilih **Aplikasi web**.',
            'Kolom **Deskripsi**: opsional. Ketik **RekapRapi Backup** atau biarkan kosong. Isinya hanya catatan untuk Anda.',
            '**Jalankan sebagai** (Execute as): pilih **Saya** (email Anda).',
            '**Yang memiliki akses** (Who has access): pilih **Siapa saja**. Jangan pilih "Siapa saja yang memiliki akun Google" atau "Hanya saya", karena RekapRapi tidak bisa mengirim data dengan pilihan itu.',
            'Klik **Terapkan**. Google meminta izin: klik **Beri otorisasi akses**, lalu pilih akun Anda.',
            'Akan muncul peringatan **Google belum memverifikasi aplikasi ini**. Ini normal karena skrip dibuat sendiri oleh Anda. Klik **Lanjutan** > **Buka … (tidak aman)** > **Izinkan**. Izin yang diminta hanya untuk Google Sheet ini.',
            'Setelah berhasil, salin **URL aplikasi web** yang berakhiran **/exec** dengan tombol **Salin**, lalu klik **Selesai**.',
          ],
        ),
        const GuideStep(
          key: 'url',
          title: 'Tempel alamatnya di sini',
          paragraphs: [
            'Tempel URL aplikasi web (berakhiran **/exec**) di bawah, lalu klik tombolnya. RekapRapi memeriksa sambungan tanpa menulis apa pun ke Sheet.',
            'Pemeriksaan manual (opsional): buka URL itu di tab baru. Jika benar, tampil teks seperti **{"ok":true,"app":"RekapRapi Backup",…}**.',
          ],
        ),
      ],
      troubleshooting: const [
        '**Google tidak memberi jawaban yang benar**: akses belum **Siapa saja**, atau alamat yang ditempel bukan yang berakhiran **/exec**. Alamat berakhiran **/dev** berasal dari **Uji penerapan** dan tidak bisa dipakai.',
        '**Kode rahasia tidak cocok**: kode di skrip berbeda dengan kode di aplikasi. Salin ulang kode dari halaman ini, tempel menimpa isi editor, lalu **Simpan**.',
        '**Sudah mengubah kode skrip?** Buat versi baru: **Terapkan** > **Kelola penerapan** > klik ikon pensil > pada **Versi** pilih **Versi baru** > **Terapkan**. URL tetap sama.',
        '**Akun kantor atau kampus (Google Workspace)** kadang melarang akses "Siapa saja". Coba dengan akun Gmail pribadi, atau minta admin Google Anda mengizinkannya.',
        '**Tidak ada menu Ekstensi?** Pastikan yang dibuka adalah Google Sheet, bukan berkas Excel di Drive. Pilih **File** > **Simpan sebagai Google Spreadsheet**.',
      ],
    );

BackupGuide _en(String name) => BackupGuide(
      labels: const GuideLabels(
        sectionTitle: 'How to connect',
        languageHint:
            'Pick the same language as your Google account so the menu names match your screen.',
        openSheets: 'Open sheets.new',
        copyName: 'Copy name',
        nameCopied: 'Name copied.',
        copyCode: 'Copy script code',
        showCode: 'Show code',
        hideCode: 'Hide code',
        codeCopied: 'Script code copied. Paste it into Apps Script.',
        troubleshootingTitle: 'If it fails',
        suggestedName: 'Suggested name',
      ),
      steps: [
        GuideStep(
          key: 'sheet',
          title: 'Create a new Google Sheet and name it',
          paragraphs: [
            'Click the button below to create a blank Google Sheet, or open **sheets.google.com** and choose **Blank spreadsheet**.',
            'Name it: click the title at the top left (default **Untitled spreadsheet**), type a name, and press Enter. Example: **$name**. Any name works and it does not affect how the backup runs, but a clear name helps you find it later.',
            'Use a Sheet dedicated to backups. Every backup overwrites the sheets named **Info, Ringkasan, Kas, Piutang, Utang, Pembayaran, Kontak**. Other sheets in that file are left alone.',
          ],
        ),
        const GuideStep(
          key: 'code',
          title: 'Paste the script code',
          items: [
            'In the Google Sheet, open the **Extensions** > **Apps Script** menu. The script editor opens in a new tab.',
            'The editor already has some default code (**function myFunction() { }**). Click inside it, press **Ctrl+A**, then **Delete** to remove everything.',
            'Click **Copy script code** below, then paste it into the editor with **Ctrl+V**. This code already contains the secret code for your business.',
            'Click the floppy-disk icon **Save project** (or press **Ctrl+S**). If it asks for a project name, anything works, for example **RekapRapi Backup**.',
          ],
        ),
        const GuideStep(
          key: 'deploy',
          title: 'Deploy it as a web app',
          items: [
            'In the Apps Script editor, click the blue **Deploy** button (top right) > **New deployment**.',
            'In the window that appears, click the gear icon next to **Select type**, then choose **Web app**.',
            'The **Description** field is optional. Type **RekapRapi Backup** or leave it empty. It is only a note for you.',
            '**Execute as**: choose **Me** (your email).',
            '**Who has access**: choose **Anyone**. Do not choose "Anyone with Google account" or "Only myself", because RekapRapi cannot send data with those options.',
            'Click **Deploy**. Google asks for permission: click **Authorize access**, then choose your account.',
            'A warning appears: **Google hasn\'t verified this app**. This is normal because you created the script yourself. Click **Advanced** > **Go to … (unsafe)** > **Allow**. The permission is only for this Google Sheet.',
            'When it succeeds, copy the **Web app URL** that ends with **/exec** using the **Copy** button, then click **Done**.',
          ],
        ),
        const GuideStep(
          key: 'url',
          title: 'Paste the address here',
          paragraphs: [
            'Paste the web app URL (ending in **/exec**) below, then click the button. RekapRapi checks the connection without writing anything to the Sheet.',
            'Manual check (optional): open that URL in a new tab. If it is correct you will see text like **{"ok":true,"app":"RekapRapi Backup",…}**.',
          ],
        ),
      ],
      troubleshooting: const [
        '**Google did not give a proper answer**: access is not set to **Anyone**, or the pasted address does not end in **/exec**. An address ending in **/dev** comes from **Test deployments** and cannot be used.',
        '**Secret code does not match**: the code in the script differs from the code in the app. Copy the code again from this page, paste it over the editor content, then **Save**.',
        '**Changed the script code?** Create a new version: **Deploy** > **Manage deployments** > click the pencil icon > under **Version** choose **New version** > **Deploy**. The URL stays the same.',
        '**Work or school accounts (Google Workspace)** sometimes block "Anyone" access. Try a personal Gmail account, or ask your Google admin to allow it.',
        '**No Extensions menu?** Make sure you opened a Google Sheet, not an Excel file in Drive. Choose **File** > **Save as Google Sheets**.',
      ],
    );
