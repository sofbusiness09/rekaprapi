import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'business.dart';

/// Undangan yang menunggu dijawab oleh pengguna ini.
class BusinessInvite {
  const BusinessInvite(this.id, this.businessName, this.role);

  final String id;
  final String businessName;

  /// 'admin' | 'staff'
  final String role;
}

/// Usaha milik/diikuti pengguna, usaha yang sedang aktif, dan undangan.
///
/// Usaha aktif diingat di `profiles.last_business_id`, sehingga setelah masuk
/// aplikasi langsung membuka usaha terakhir tanpa layar pilih usaha.
class BusinessController extends ChangeNotifier {
  SupabaseClient get _db => Supabase.instance.client;

  List<Business> businesses = [];
  List<BusinessInvite> invites = [];
  Business? current;

  /// true hanya selama pemuatan pertama.
  bool loading = true;
  Object? error;

  /// Memuat ulang daftar. Usaha aktif dipertahankan bila masih ada; jika tidak,
  /// dipakai [preferId], lalu usaha terakhir yang diingat, lalu yang pertama.
  Future<void> load({String? preferId}) async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) return;
      final email = (user.email ?? '').toLowerCase();

      final results = await Future.wait(<Future<dynamic>>[
        _db
            .from('business_members')
            .select('role, businesses(id, name)')
            .eq('user_id', user.id),
        _db
            .from('invitations')
            .select('id, business_name, role')
            .eq('email', email)
            .eq('status', 'pending')
            .gt('expires_at', DateTime.now().toUtc().toIso8601String()),
        _db
            .from('profiles')
            .select('last_business_id')
            .eq('id', user.id)
            .maybeSingle(),
      ]);

      final members = results[0] as List;
      final inviteRows = results[1] as List;
      final profile = results[2] as Map<String, dynamic>?;

      businesses = [
        for (final m in members)
          if (m['businesses'] != null)
            Business(
              id: m['businesses']['id'] as String,
              name: m['businesses']['name'] as String,
              role: m['role'] as String,
            ),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      invites = [
        for (final i in inviteRows)
          BusinessInvite(i['id'] as String, i['business_name'] as String,
              i['role'] as String),
      ];

      final wanted =
          preferId ?? current?.id ?? profile?['last_business_id'] as String?;
      current = businesses.where((b) => b.id == wanted).firstOrNull ??
          businesses.firstOrNull;
      error = null;
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Pindah ke usaha lain dan ingat pilihannya.
  Future<void> select(Business b) async {
    if (current?.id == b.id) return;
    current = b;
    notifyListeners();
    try {
      await _db.from('profiles').update({'last_business_id': b.id}).eq(
          'id', _db.auth.currentUser!.id);
    } catch (_) {
      // Gagal mengingat pilihan tidak menghalangi pemakaian.
    }
  }

  /// Membuat usaha baru dan langsung membukanya. Batas 5 usaha dijaga database.
  Future<void> create(String name) async {
    final id = await _db.rpc('create_business', params: {'p_name': name});
    await load(preferId: id as String);
  }

  Future<void> joinByCode(String code) async {
    final id =
        await _db.rpc('accept_invitation_by_code', params: {'p_code': code});
    await load(preferId: id as String);
  }

  Future<void> accept(String inviteId) async {
    final id =
        await _db.rpc('accept_invitation', params: {'p_invitation': inviteId});
    await load(preferId: id as String);
  }

  Future<void> decline(String inviteId) async {
    await _db.rpc('decline_invitation', params: {'p_invitation': inviteId});
    await load();
  }

  /// Nama usaha berubah di Pengaturan.
  void rename(String id, String name) {
    businesses = [
      for (final b in businesses)
        b.id == id ? Business(id: b.id, name: name, role: b.role) : b,
    ];
    if (current?.id == id) {
      current = businesses.firstWhere((b) => b.id == id);
    }
    notifyListeners();
  }

  /// Pengguna keluar dari / menghapus usaha aktif: pilih usaha lain bila ada.
  Future<void> afterLeft() async {
    current = null;
    await load();
  }
}
