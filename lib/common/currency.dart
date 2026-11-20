/// Mata uang pembukuan. Satu pembukuan memakai satu mata uang; jumlah selalu bulat
/// (tanpa sen). Mengganti mata uang hanya mengganti tampilan, bukan mengonversi nilai.
class Currency {
  const Currency(this.code, this.name, this.symbol,
      {this.separator = ',', this.spaced = false});

  /// Kode ISO 4217, mis. IDR.
  final String code;
  final String name;

  /// Simbol di depan angka.
  final String symbol;

  /// Pemisah ribuan: titik (IDR, EUR, ...) atau koma.
  final String separator;

  /// Ada spasi antara simbol dan angka (mis. "Rp 50.000", "AED 50,000").
  final bool spaced;

  /// Awalan pada kolom isian jumlah, mis. "Rp ".
  String get prefix => '$symbol ';

  String get label => '$name ($code)';
}

/// Rupiah lebih dulu, lalu mata uang yang paling banyak dipakai secara internasional
/// dan oleh pekerja atau usaha Indonesia di luar negeri.
const currencies = <Currency>[
  Currency('IDR', 'Rupiah Indonesia', 'Rp', separator: '.', spaced: true),
  Currency('USD', 'Dolar Amerika Serikat', r'$'),
  Currency('EUR', 'Euro', '€', separator: '.'),
  Currency('JPY', 'Yen Jepang', 'JP¥'),
  Currency('GBP', 'Pound Sterling Inggris', '£'),
  Currency('CNY', 'Yuan Tiongkok', 'CN¥'),
  Currency('AUD', 'Dolar Australia', r'A$'),
  Currency('CAD', 'Dolar Kanada', r'C$'),
  Currency('CHF', 'Franc Swiss', 'CHF', spaced: true),
  Currency('HKD', 'Dolar Hong Kong', r'HK$'),
  Currency('SGD', 'Dolar Singapura', r'S$'),
  Currency('MYR', 'Ringgit Malaysia', 'RM'),
  Currency('AED', 'Dirham Uni Emirat Arab', 'AED', spaced: true),
  Currency('SAR', 'Riyal Arab Saudi', 'SAR', spaced: true),
  Currency('KRW', 'Won Korea Selatan', '₩'),
  Currency('THB', 'Baht Thailand', '฿'),
  Currency('INR', 'Rupee India', '₹'),
  Currency('TWD', 'Dolar Taiwan', r'NT$'),
  Currency('QAR', 'Riyal Qatar', 'QAR', spaced: true),
  Currency('KWD', 'Dinar Kuwait', 'KWD', spaced: true),
  Currency('OMR', 'Rial Oman', 'OMR', spaced: true),
  Currency('BHD', 'Dinar Bahrain', 'BHD', spaced: true),
  Currency('TRY', 'Lira Turki', '₺', separator: '.'),
  Currency('PHP', 'Peso Filipina', '₱'),
  Currency('VND', 'Dong Vietnam', '₫', separator: '.'),
  Currency('BND', 'Dolar Brunei', r'B$'),
  Currency('NZD', 'Dolar Selandia Baru', r'NZ$'),
];

const defaultCurrency = 'IDR';

/// Mata uang dari kodenya; kode tidak dikenal atau kosong menjadi Rupiah.
Currency currencyByCode(String? code) =>
    currencies.firstWhere((c) => c.code == code?.toUpperCase(),
        orElse: () => currencies.first);

/// Mata uang pembukuan yang sedang dibuka. Diatur saat pembukuan dibuka atau mata
/// uangnya diganti; semua tampilan jumlah memakainya.
Currency activeCurrency = currencies.first;

/// Angka dengan pemisah ribuan mata uang [c] (bawaan: mata uang aktif).
String groupDigits(int n, [Currency? c]) {
  final sep = (c ?? activeCurrency).separator;
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(sep);
    b.write(s[i]);
  }
  return b.toString();
}

/// Jumlah lengkap dengan simbol: "Rp 1.250.000", "$1,250,000", "-AED 5,000".
String formatMoney(num n, [Currency? c]) {
  final cur = c ?? activeCurrency;
  final sign = n < 0 ? '-' : '';
  return '$sign${cur.symbol}${cur.spaced ? ' ' : ''}${groupDigits(n.abs().round(), cur)}';
}

/// Pengganti angka saat nominal disembunyikan: "Rp •••••", "AED •••••".
String maskedMoney([Currency? c]) {
  final cur = c ?? activeCurrency;
  return '${cur.symbol}${cur.spaced ? ' ' : ''}•••••';
}
