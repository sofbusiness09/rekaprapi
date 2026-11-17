// Pembaca teks nota. Di Android memakai Google ML Kit (di perangkat, tanpa internet);
// di web tidak tersedia, jadi tombol Scan nota disembunyikan.
export 'receipt_ocr_stub.dart' if (dart.library.io) 'receipt_ocr_io.dart';
