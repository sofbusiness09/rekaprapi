import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/cash/cash_models.dart';
import 'package:rekap_rapi/settings/home_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

Activity _a({
  required String kind,
  required String flow,
  required String title,
  bool isAuto = false,
}) =>
    Activity(
      kind: kind,
      refId: 'x',
      date: DateTime(2026, 11, 3),
      flow: flow,
      amount: 1000,
      title: title,
      isAuto: isAuto,
      isSale: false,
    );

void main() {
  group('Activity.type', () {
    test('kas biasa masuk dan keluar', () {
      expect(_a(kind: 'cash', flow: 'in', title: 'Penjualan').type,
          ActivityType.cashIn);
      expect(_a(kind: 'cash', flow: 'out', title: 'Gaji').type,
          ActivityType.cashOut);
    });

    test('transaksi hutang', () {
      expect(_a(kind: 'credit', flow: 'in', title: 'Penjualan').type,
          ActivityType.credit);
      expect(_a(kind: 'credit', flow: 'out', title: 'Utang').type,
          ActivityType.credit);
    });

    test('pelunasan dan pembayaran', () {
      expect(
          _a(kind: 'cash', flow: 'in', title: 'Pelunasan Piutang', isAuto: true)
              .type,
          ActivityType.payment);
      expect(
          _a(kind: 'cash', flow: 'out', title: 'Pembayaran Utang', isAuto: true)
              .type,
          ActivityType.payment);
    });

    test('pemberian dan penerimaan utang berupa uang', () {
      expect(
          _a(
                  kind: 'cash',
                  flow: 'out',
                  title: 'Pemberian Piutang',
                  isAuto: true)
              .type,
          ActivityType.loan);
      expect(
          _a(kind: 'cash', flow: 'in', title: 'Penerimaan Utang', isAuto: true)
              .type,
          ActivityType.loan);
    });
  });

  group('HomePrefs', () {
    final all = [
      _a(kind: 'cash', flow: 'in', title: 'Penjualan'),
      _a(kind: 'cash', flow: 'out', title: 'Gaji'),
      _a(kind: 'credit', flow: 'in', title: 'Penjualan'),
      _a(kind: 'cash', flow: 'in', title: 'Pelunasan Piutang', isAuto: true),
      _a(kind: 'cash', flow: 'out', title: 'Pemberian Piutang', isAuto: true),
    ];

    test('bawaan menampilkan semuanya (sama seperti tampilan awal)', () {
      const p = HomePrefs();
      expect(p.showBalance && p.showFlow && p.showProfit, isTrue);
      expect(p.showQuickActions && p.showDebtCards && p.showActivity, isTrue);
      expect(p.activityCount, 8);
      expect(all.where(p.allows).length, all.length);
    });

    test('filter jenis aktivitas', () {
      const base = HomePrefs();
      expect(
          all
              .where(base
                  .copyWith(
                      actCashOut: false,
                      actCredit: false,
                      actPayments: false,
                      actLoans: false)
                  .allows)
              .map((a) => a.type),
          [ActivityType.cashIn]);

      expect(
          all
              .where(base.copyWith(actCashIn: false, actCashOut: false).allows)
              .length,
          3);
    });

    test('fokus keuntungan: saldo kas dimatikan, bagian lain tetap', () {
      final p = const HomePrefs().copyWith(showBalance: false);
      expect(p.showBalance, isFalse);
      expect(p.showHero, isTrue); // kas masuk/keluar bulan ini masih tampil
      expect(p.showProfit, isTrue);
      expect(p.copyWith(showFlow: false).showHero, isFalse);
    });

    test('anySection dan anyActivityType', () {
      const off = HomePrefs(
        showBalance: false,
        showFlow: false,
        showProfit: false,
        showQuickActions: false,
        showDebtCards: false,
        showActivity: false,
      );
      expect(off.anySection, isFalse);
      expect(off.copyWith(showProfit: true).anySection, isTrue);
      expect(
          const HomePrefs(
                  actCashIn: false,
                  actCashOut: false,
                  actCredit: false,
                  actPayments: false,
                  actLoans: false)
              .anyActivityType,
          isFalse);
    });

    test('JSON bolak-balik dan nilai rusak memakai bawaan', () {
      final p = const HomePrefs(showBalance: false, activityCount: 15)
          .copyWith(actLoans: false);
      final back = HomePrefs.fromJson(p.toJson());
      expect(back.showBalance, isFalse);
      expect(back.actLoans, isFalse);
      expect(back.activityCount, 15);

      final broken =
          HomePrefs.fromJson(const {'activityCount': 999, 'showFlow': 'x'});
      expect(broken.activityCount, 8);
      expect(broken.showFlow, isTrue);
      expect(HomePrefs.fromJson(const {}).showActivity, isTrue);
    });
  });

  group('HomePrefsController', () {
    test('menyimpan dan memuat per akun', () async {
      SharedPreferences.setMockInitialValues({});
      final c1 = HomePrefsController();
      await c1.load('user-a');
      await c1.update(c1.value.copyWith(showBalance: false, activityCount: 5));

      final again = HomePrefsController();
      await again.load('user-a');
      expect(again.value.showBalance, isFalse);
      expect(again.value.activityCount, 5);

      final other = HomePrefsController();
      await other.load('user-b');
      expect(other.value.showBalance, isTrue,
          reason: 'akun lain tidak ikut berubah');
    });

    test('reset mengembalikan bawaan dan data rusak diabaikan', () async {
      SharedPreferences.setMockInitialValues({'home_prefs_u': '{rusak'});
      final c = HomePrefsController();
      await c.load('u');
      expect(c.value.showBalance, isTrue);

      await c.update(c.value.copyWith(showProfit: false));
      await c.reset();
      final reloaded = HomePrefsController();
      await reloaded.load('u');
      expect(reloaded.value.showProfit, isTrue);
    });
  });
}
