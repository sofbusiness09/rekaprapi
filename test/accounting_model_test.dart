import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/business/business.dart';
import 'package:rekap_rapi/cash/cash_models.dart';
import 'package:rekap_rapi/debts/debt_models.dart';
import 'package:rekap_rapi/settings/home_prefs.dart';

void main() {
  group('Summary: pemasukan, pengeluaran, laba', () {
    test('dibaca dari ringkasan server', () {
      final s = Summary.fromMap({
        'total_in': 8000000,
        'total_out': 2000000,
        'balance': 6000000,
        'receivable_open': 900000,
        'payable_open': 200000,
        'income_sales': 6000000,
        'income_other': 100000,
        'income_total': 6100000,
        'expense_cost': 3850000,
        'expense_other': 1450000,
        'expense_credit': 200000,
        'expense_total': 5300000,
        'net': 800000,
        'sales_total': 6000000,
        'profit': 2150000,
      });
      expect(s.incomeTotal, 6100000);
      expect(s.expenseTotal, 5300000);
      expect(s.net, 800000);
      expect(s.incomeTotal - s.expenseTotal, s.net);
      expect(s.expenseCost + s.expenseOther, s.expenseTotal);
      expect(s.incomeSales + s.incomeOther, s.incomeTotal);
      expect(s.profit, 2150000,
          reason: 'keuntungan penjualan = penjualan - modal');
    });

    test('server lama tanpa kolom baru: semuanya 0, tidak error', () {
      final s = Summary.fromMap({
        'total_in': 1,
        'total_out': 2,
        'balance': 3,
        'receivable_open': 0,
        'payable_open': 0,
      });
      expect(s.net, 0);
      expect(s.incomeTotal, 0);
      expect(s.expenseTotal, 0);
    });
  });

  group('Keuntungan per penjualan = uang diterima - modal', () {
    test('kas: biaya tambahan ikut sebagai pemasukan', () {
      // Total 100.000, diskon 10.000, biaya tambahan 5.000 => diterima 95.000.
      final tx = CashTx(
        id: '1',
        type: 'in',
        amount: 95000,
        date: DateTime(2026, 11, 6),
        isSale: true,
        costAmount: 60000,
        discountAmount: 10000,
        extraFee: 5000,
      );
      expect(tx.saleTotal, 100000);
      expect(tx.profit, 35000);
    });

    test('utang: sama dengan penjualan lunas', () {
      final d = Debt(
        id: 'd',
        contactId: 'c',
        kind: 'receivable',
        amount: 50000,
        cashMoved: false,
        debtDate: DateTime(2026, 11, 6),
        paid: 0,
        remaining: 50000,
        createdAt: DateTime(2026, 11, 6, 10),
        isSale: true,
        costAmount: 20000,
        extraFee: 2000,
      );
      expect(d.profit, 30000);
    });

    test('rugi bila modal lebih besar dari uang diterima', () {
      final tx = CashTx(
        id: '2',
        type: 'in',
        amount: 10000,
        date: DateTime(2026, 11, 6),
        isSale: true,
        costAmount: 12000,
      );
      expect(tx.profit, -2000);
    });
  });

  group('Hak melihat laba', () {
    const owner = Business(id: '1', name: 'U', role: 'owner');
    const admin = Business(id: '1', name: 'U', role: 'admin');
    const staff = Business(id: '1', name: 'U', role: 'staff');
    const personal = Business(
        id: '2', name: 'P', role: 'owner', kind: BusinessKind.personal);

    test('Pemilik dan Admin melihat; Staf dan pembukuan pribadi tidak', () {
      expect(owner.canSeeProfit, isTrue);
      expect(admin.canSeeProfit, isTrue);
      expect(staff.canSeeProfit, isFalse);
      expect(personal.canSeeProfit, isFalse);
    });
  });

  group('Saldo kas disembunyikan secara bawaan', () {
    test('bawaan mati, bisa dihidupkan dan tersimpan', () {
      expect(const HomePrefs().showCashBalance, isFalse);
      final on = const HomePrefs().copyWith(showCashBalance: true);
      expect(HomePrefs.fromJson(on.toJson()).showCashBalance, isTrue);
      expect(HomePrefs.fromJson(const {}).showCashBalance, isFalse,
          reason: 'pengaturan lama tanpa kunci ikut bawaan baru');
    });
  });
}
