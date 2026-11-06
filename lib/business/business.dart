/// Jenis pembukuan: usaha (fitur lengkap termasuk penjualan) atau pribadi.
enum BusinessKind {
  business,
  personal;

  static BusinessKind parse(String? v) =>
      v == 'personal' ? BusinessKind.personal : BusinessKind.business;

  String get apiValue => name;
  String get label => this == personal ? 'Pribadi' : 'Usaha';
}

class Business {
  const Business({
    required this.id,
    required this.name,
    required this.role,
    this.kind = BusinessKind.business,
  });

  final String id;
  final String name;

  /// 'owner' | 'admin' | 'staff'
  final String role;
  final BusinessKind kind;

  bool get canManage => role == 'owner' || role == 'admin';

  /// Pembukuan pribadi: tanpa penjualan, harga modal, dan keuntungan.
  bool get isPersonal => kind == BusinessKind.personal;

  /// Modal, keuntungan, dan laba hanya untuk Pemilik dan Admin di Pembukuan Usaha.
  /// (Staf tetap mengisi modal saat mencatat penjualan, tetapi tidak melihat hasilnya.)
  bool get canSeeProfit => canManage && !isPersonal;

  Business copyWith({String? name}) =>
      Business(id: id, name: name ?? this.name, role: role, kind: kind);
}
