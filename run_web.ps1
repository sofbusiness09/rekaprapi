# Menjalankan RekapRapi di Chrome (uji lokal). Butuh Flutter SDK.
# Kunci di bawah adalah publishable key (aman ada di aplikasi). Jangan taruh secret/service_role key di sini.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Test-Path 'android') -or -not (Test-Path 'web')) {
  flutter create . --platforms=android,web --project-name rekap_rapi
}
flutter pub get
flutter run -d chrome --web-port=5000 `
  --dart-define=SUPABASE_URL=https://eeaplifuoznpktwtdlxx.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=sb_publishable__PD5RfyX2g8H22pVqnoTQQ_zNJQ5kyW
