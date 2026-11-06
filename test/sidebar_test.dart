import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/business/app_sidebar.dart';

void main() {
  testWidgets('sidebar membuka dan menutup tanpa meluap', (tester) async {
    var extended = true;
    var selected = 0;
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: Row(children: [
            AppSidebar(
              extended: extended,
              onToggle: () => setState(() => extended = !extended),
              businessName: 'Toko Rahmart',
              roleLabel: 'Pemilik',
              onOpenSwitcher: () {},
              accent: const Color(0xFF0E9F6E),
              items: const [
                SidebarItem(
                    Icons.bar_chart_outlined, Icons.bar_chart, 'Rekapan'),
                SidebarItem(Icons.receipt_long_outlined, Icons.receipt_long,
                    'Transaksi'),
              ],
              selected: selected,
              onSelected: (i) => setState(() => selected = i),
            ),
            const Expanded(child: SizedBox()),
          ]),
        ),
      ),
    ));
    expect(tester.getSize(find.byType(AppSidebar)).width, 236);
    expect(find.text('Rekapan'), findsOneWidget);

    await tester.tap(find.byTooltip('Ciutkan menu'));
    await tester.pump(const Duration(milliseconds: 130));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppSidebar)).width, 76);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Perluas menu'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppSidebar)).width, 236);
    await tester.tap(find.text('Transaksi'));
    await tester.pump();
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });
}
