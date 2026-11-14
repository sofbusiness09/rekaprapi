import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/business/business.dart';
import 'package:rekap_rapi/common/widgets.dart';
import 'package:rekap_rapi/settings/business_photo_page.dart';

class _FakeRepo extends BusinessPhotoRepository {
  _FakeRepo() : super('b1');

  PickedPhoto? uploaded;
  bool removed = false;
  Object? failWith;

  @override
  Future<String> upload(PickedPhoto photo) async {
    if (failWith != null) throw failWith!;
    uploaded = photo;
    return 'https://x/business-photos/b1/baru.jpg';
  }

  @override
  Future<void> remove() async => removed = true;
}

Future<List<String?>> _pump(WidgetTester tester, _FakeRepo repo,
    {String? photoUrl, Future<PickedPhoto?> Function()? picker}) async {
  final changes = <String?>[];
  await tester.pumpWidget(MaterialApp(
    home: BusinessPhotoPage(
      businessId: 'b1',
      businessName: 'Toko Rahmart',
      photoUrl: photoUrl,
      onChanged: changes.add,
      repo: repo,
      picker: picker,
    ),
  ));
  return changes;
}

void main() {
  test('jenis berkas: hanya JPG, PNG, WebP', () {
    expect(photoMimeType('image/png', 'a'), 'image/png');
    expect(photoMimeType(null, 'Foto.JPG'), 'image/jpeg');
    expect(photoMimeType(null, 'a.jpeg'), 'image/jpeg');
    expect(photoMimeType('application/octet-stream', 'a.webp'), 'image/webp');
    expect(photoMimeType(null, 'a.gif'), isNull);
    expect(photoMimeType('image/heic', 'a.heic'), isNull);
    expect(PickedPhoto(Uint8List(0), 'image/png').extension, 'png');
    expect(PickedPhoto(Uint8List(0), 'image/jpeg').extension, 'jpg');
  });

  test('foto pembukuan ikut saat nama diganti, dan bisa dihapus', () {
    const b = Business(id: '1', name: 'A', role: 'owner', photoUrl: 'u');
    expect(b.copyWith(name: 'B').photoUrl, 'u');
    expect(b.withPhoto(null).photoUrl, isNull);
    expect(b.withPhoto('v').name, 'A');
  });

  testWidgets('tanpa foto: inisial, tombol Pilih foto, tanpa Hapus',
      (tester) async {
    await _pump(tester, _FakeRepo());
    expect(find.text('TR'), findsOneWidget);
    expect(find.text('Pilih foto'), findsOneWidget);
    expect(find.text('Hapus foto'), findsNothing);
  });

  testWidgets('memilih foto mengunggah dan memberi tahu alamat baru',
      (tester) async {
    final repo = _FakeRepo();
    final changes = await _pump(tester, repo,
        picker: () async =>
            PickedPhoto(Uint8List.fromList([1, 2, 3]), 'image/jpeg'));
    await tester.tap(find.text('Pilih foto'));
    await tester.pump();
    await tester.pump();
    expect(repo.uploaded!.bytes.length, 3);
    expect(changes, ['https://x/business-photos/b1/baru.jpg']);
    expect(find.text('Ganti foto'), findsOneWidget);
    expect(find.text('Hapus foto'), findsOneWidget);
  });

  testWidgets('batal memilih atau gambar tidak cocok: tidak ada yang berubah',
      (tester) async {
    final repo = _FakeRepo();
    final changes = await _pump(tester, repo, picker: () async => null);
    await tester.tap(find.text('Pilih foto'));
    await tester.pump();
    await tester.pump();
    expect(repo.uploaded, isNull);
    expect(changes, isEmpty);

    final changes2 = await _pump(tester, repo,
        picker: () async =>
            throw const FormatException('Pakai gambar JPG, PNG, atau WebP.'));
    await tester.tap(find.text('Pilih foto'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Pakai gambar JPG, PNG, atau WebP.'), findsOneWidget);
    expect(changes2, isEmpty);
  });

  testWidgets('avatar tanpa alamat foto menampilkan inisial', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: InitialAvatar('Toko Rahmart', photoUrl: ''))));
    expect(find.text('TR'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
