/// Diisi saat build, bukan ditulis di kode:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// Gunakan anon key (publik). Jangan pernah memakai service_role key di aplikasi.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Alamat versi web. Tautan reset password selalu membuka web, juga bila diminta
/// dari aplikasi Android. Harus terdaftar di Supabase > Authentication > Redirect URLs.
const webAppUrl = String.fromEnvironment('WEB_APP_URL',
    defaultValue: 'https://sofbusiness09.github.io/rekaprapi/');
