import 'dart:io' show Platform;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'receipt_parser.dart';

/// ML Kit hanya untuk Android dan iOS.
bool get receiptScanSupported => Platform.isAndroid || Platform.isIOS;

/// Membaca teks dari foto nota di [imagePath]. Baris diurutkan dari atas ke bawah
/// beserta posisinya, supaya kata "TOTAL" bisa dipasangkan dengan angka sebarisnya.
Future<List<ReceiptLine>> readReceiptText(String imagePath) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result =
        await recognizer.processImage(InputImage.fromFilePath(imagePath));
    final lines = [
      for (final block in result.blocks)
        for (final line in block.lines)
          ReceiptLine(line.text,
              top: line.boundingBox.top,
              bottom: line.boundingBox.bottom,
              left: line.boundingBox.left),
    ]..sort((a, b) {
        final c = a.top!.compareTo(b.top!);
        return c != 0 ? c : a.left!.compareTo(b.left!);
      });
    return lines;
  } finally {
    await recognizer.close();
  }
}
