// Ambil satu kontak dari buku kontak HP. Hanya aplikasi Android/iPhone; di web
// tombolnya disembunyikan.
export 'phone_contacts_stub.dart' if (dart.library.io) 'phone_contacts_io.dart';
