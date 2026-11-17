import 'receipt_parser.dart';

/// Web: pembacaan nota tidak tersedia.
bool get receiptScanSupported => false;

Future<List<ReceiptLine>> readReceiptText(String imagePath) => Future.error(
    UnsupportedError('Scan nota hanya tersedia di aplikasi Android.'));
