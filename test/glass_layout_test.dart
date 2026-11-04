import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/common/glass.dart';

/// Kerangka ponsel yang sama dengan BusinessHome: header dan tab bawah berkaca,
/// isi bergulir di bawahnya, dan halaman anak punya Scaffold sendiri untuk tombol.
Widget _frame({required bool dark}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    // Tema polos: tes ini hanya memeriksa letak, bukan huruf yang diunduh.
    theme: ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorSchemeSeed: const Color(0xFF0E9F6E),
      scaffoldBackgroundColor:
          dark ? const Color(0xFF101211) : const Color(0xFFF5F6F5),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          flexibleSpace: const GlassBar(top: true),
          title: const Text('Warung Contoh'),
        ),
        body: Builder(builder: (pageContext) {
          // Dibaca di luar Scaffold anak, seperti halaman Transaksi dan Utang.
          final pageInsets = MediaQuery.paddingOf(pageContext);
          return Scaffold(
            backgroundColor: Colors.transparent,
            // Seperti halaman sungguhan: dibaca dari konteks di bawah Scaffold luar.
            body: Builder(
                builder: (context) => ListView(
                      key: const Key('list'),
                      padding: EdgeInsets.fromLTRB(
                        14,
                        4 + MediaQuery.paddingOf(context).top,
                        14,
                        24 + MediaQuery.paddingOf(context).bottom,
                      ),
                      children: [
                        for (var i = 0; i < 12; i++)
                          Card(
                            color: i == 1 ? const Color(0xFF0E9F6E) : null,
                            child: SizedBox(
                                height: 90,
                                child: Center(child: Text('Kartu $i'))),
                          ),
                      ],
                    )),
            floatingActionButton: Padding(
              padding: EdgeInsets.only(bottom: pageInsets.bottom),
              child: FloatingActionButton.extended(
                onPressed: () {},
                label: const Text('Catat manual'),
              ),
            ),
          );
        }),
        bottomNavigationBar: GlassBar(
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedIndex: 0,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Beranda'),
              NavigationDestination(
                  icon: Icon(Icons.receipt_long), label: 'Transaksi'),
              NavigationDestination(
                  icon: Icon(Icons.handshake), label: 'Utang'),
              NavigationDestination(
                  icon: Icon(Icons.bar_chart), label: 'Laporan'),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'kaca ${dark ? 'gelap' : 'terang'}: baris pertama dan terakhir tidak tertutup',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_frame(dark: dark));
      await tester.pumpAndSettle();

      final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
      final navTop = tester.getTopLeft(find.byType(NavigationBar)).dy;

      // Kartu pertama dimulai di bawah header, tidak tertutup kaca.
      final first = tester.getTopLeft(find.text('Kartu 0')).dy;
      expect(first, greaterThan(appBarBottom - 1));

      // Setelah digulir habis, kartu terakhir berada di atas tab bawah.
      await tester.drag(find.byKey(const Key('list')), const Offset(0, -6000));
      await tester.pumpAndSettle();
      final last = tester.getBottomLeft(find.text('Kartu 11')).dy;
      expect(last, lessThan(navTop + 1));

      // Tombol melayang tidak menutupi tab bawah.
      final fabBottom =
          tester.getBottomLeft(find.byType(FloatingActionButton)).dy;
      expect(fabBottom, lessThan(navTop + 1));
    });
  }
}
