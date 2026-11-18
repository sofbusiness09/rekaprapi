import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/business/business.dart';
import 'package:rekap_rapi/common/calc_expression.dart';
import 'package:rekap_rapi/common/currency.dart';
import 'package:rekap_rapi/common/currency_picker.dart';
import 'package:rekap_rapi/common/format.dart';

void main() {
  tearDown(() => activeCurrency = currencyByCode('IDR'));

  test('daftar: kode unik, Rupiah pertama, Dirham UEA ada', () {
    final codes = [for (final c in currencies) c.code];
    expect(codes.toSet().length, codes.length);
    expect(codes.first, 'IDR');
    for (final c in ['AED', 'USD', 'EUR', 'SAR', 'MYR', 'QAR', 'PHP']) {
      expect(codes, contains(c));
    }
    expect(currencyByCode('AED').name, 'Dirham Uni Emirat Arab');
    expect(currencyByCode('aed').code, 'AED');
    expect(currencyByCode('XYZ').code, 'IDR');
    expect(currencyByCode(null).code, 'IDR');
  });

  test('format: simbol, pemisah ribuan per mata uang, dan spasi', () {
    expect(formatMoney(1250000, currencyByCode('IDR')), 'Rp 1.250.000');
    expect(formatMoney(1250000, currencyByCode('USD')), r'$1,250,000');
    expect(formatMoney(50000, currencyByCode('EUR')), '€50.000');
    expect(formatMoney(50000, currencyByCode('AED')), 'AED 50,000');
    expect(formatMoney(50000, currencyByCode('JPY')), 'JP¥50,000');
    expect(formatMoney(50000, currencyByCode('CNY')), 'CN¥50,000');
    expect(formatMoney(-7500, currencyByCode('MYR')), '-RM7,500');
    expect(formatMoney(999, currencyByCode('USD')), r'$999');
  });

  test('mata uang aktif dipakai rupiah(), thousands(), dan kalkulator', () {
    activeCurrency = currencyByCode('USD');
    expect(rupiah(1250000), r'$1,250,000');
    expect(thousands(25000), '25,000');
    expect(formatCalc('12×2500'), '12 × 2,500');
    // Kolom isian menerima kedua pemisah.
    expect(parseAmount('25,000'), 25000);
    final f = ThousandsFormatter().formatEditUpdate(
        TextEditingValue.empty, const TextEditingValue(text: '1250000'));
    expect(f.text, '1,250,000');

    activeCurrency = currencyByCode('IDR');
    expect(rupiah(1250000), 'Rp 1.250.000');
    expect(thousands(25000), '25.000');
  });

  test('model pembukuan menyimpan mata uang', () {
    const b = Business(id: '1', name: 'A', role: 'owner', currency: 'AED');
    expect(b.copyWith(name: 'B').currency, 'AED');
    expect(b.withPhoto('u').currency, 'AED');
    expect(b.copyWith(currency: 'USD').currency, 'USD');
    expect(const Business(id: '1', name: 'A', role: 'owner').currency, 'IDR');
  });

  testWidgets('pilihan mata uang: cari dengan nama atau kode', (tester) async {
    Currency? picked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                picked = await showCurrencyPicker(context, selected: 'IDR'),
            child: const Text('buka'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'dirham');
    await tester.pump();
    expect(find.text('Dirham Uni Emirat Arab'), findsOneWidget);
    expect(find.text('Rupiah Indonesia'), findsNothing);
    expect(find.text('AED · AED 50,000'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'sgd');
    await tester.pump();
    await tester.tap(find.text('Dolar Singapura'));
    await tester.pumpAndSettle();
    expect(picked!.code, 'SGD');
  });
}
