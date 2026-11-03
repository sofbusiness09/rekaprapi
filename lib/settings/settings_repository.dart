import 'package:supabase_flutter/supabase_flutter.dart';

import '../cash/cash_models.dart';

class Member {
  const Member(this.userId, this.name, this.email, this.role);

  final String userId;
  final String name;
  final String? email;

  /// 'owner' | 'admin' | 'staff'
  final String role;
}

class PendingInvite {
  const PendingInvite(
      this.id, this.email, this.role, this.code, this.expiresAt);

  final String id;
  final String email;
  final String role;
  final String code;
  final DateTime expiresAt;
}

class ActivityEntry {
  const ActivityEntry(this.who, this.action, this.entity, this.detail, this.at);

  final String who;
  final String action;
  final String entity;
  final Map<String, dynamic> detail;
  final DateTime at;
}

const roleLabel = {'owner': 'Pemilik', 'admin': 'Admin', 'staff': 'Staf'};

/// Pengaturan usaha, anggota, undangan, kategori, dan riwayat aktivitas.
/// Perubahan anggota/undangan lewat fungsi database; hak akses ditegakkan di sana.
class SettingsRepository {
  SettingsRepository(this.businessId);

  final String businessId;
  SupabaseClient get _db => Supabase.instance.client;

  // --- Usaha ---

  Future<Map<String, dynamic>> business() async {
    return await _db
        .from('businesses')
        .select('name, address, phone')
        .eq('id', businessId)
        .single();
  }

  Future<void> updateBusiness(
      String name, String? address, String? phone) async {
    final rows = await _db
        .from('businesses')
        .update({
          'name': name.trim(),
          'address': _clean(address),
          'phone': _clean(phone)
        })
        .eq('id', businessId)
        .select('id');
    if (rows.isEmpty) {
      throw const PostgrestException(
          message: 'Anda tidak berhak mengubah profil usaha.');
    }
  }

  Future<void> deleteBusiness() =>
      _db.rpc('delete_business', params: {'p_business': businessId});

  Future<void> leaveBusiness() =>
      _db.rpc('leave_business', params: {'p_business': businessId});

  // --- Anggota dan undangan ---

  Future<List<Member>> members() async {
    final rows = await _db
        .from('business_members')
        .select('user_id, role')
        .eq('business_id', businessId);
    final profiles =
        await _db.from('profiles').select('id, display_name, email');
    final byId = {for (final p in profiles) p['id'] as String: p};
    final list = [
      for (final r in rows)
        Member(
          r['user_id'] as String,
          (byId[r['user_id']]?['display_name'] ??
              byId[r['user_id']]?['email'] ??
              'Anggota') as String,
          byId[r['user_id']]?['email'] as String?,
          r['role'] as String,
        ),
    ];
    const order = {'owner': 0, 'admin': 1, 'staff': 2};
    list.sort((a, b) {
      final c = order[a.role]!.compareTo(order[b.role]!);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  /// Hanya terlihat oleh Pemilik/Admin (RLS).
  Future<List<PendingInvite>> pendingInvites() async {
    final rows = await _db
        .from('invitations')
        .select('id, email, role, code, expires_at')
        .eq('business_id', businessId)
        .eq('status', 'pending')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: false);
    return [
      for (final r in rows)
        PendingInvite(
          r['id'] as String,
          r['email'] as String,
          r['role'] as String,
          r['code'] as String,
          DateTime.parse(r['expires_at'] as String).toLocal(),
        ),
    ];
  }

  /// Mengembalikan kode undangan.
  Future<String> invite(String email, String role) async {
    final res = await _db.rpc('create_invitation',
        params: {'p_business': businessId, 'p_email': email, 'p_role': role});
    return (res as Map)['code'] as String;
  }

  Future<void> cancelInvite(String id) =>
      _db.rpc('cancel_invitation', params: {'p_invitation': id});

  Future<void> changeRole(String userId, String role) =>
      _db.rpc('change_member_role',
          params: {'p_business': businessId, 'p_user': userId, 'p_role': role});

  Future<void> removeMember(String userId) => _db.rpc('remove_member',
      params: {'p_business': businessId, 'p_user': userId});

  Future<void> transferOwnership(String userId) => _db.rpc('transfer_ownership',
      params: {'p_business': businessId, 'p_new_owner': userId});

  // --- Kategori ---

  Future<List<Category>> categories() async {
    final rows = await _db
        .from('categories')
        .select('id, name, type, is_system')
        .eq('business_id', businessId)
        .order('name');
    return rows.map(Category.fromMap).toList();
  }

  Future<void> addCategory(String name, String type) async {
    await _db
        .from('categories')
        .insert({'business_id': businessId, 'name': name.trim(), 'type': type});
  }

  Future<void> renameCategory(String id, String name) async {
    final rows = await _db
        .from('categories')
        .update({'name': name.trim()})
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) {
      throw const PostgrestException(
          message: 'Kategori ini tidak dapat diubah.');
    }
  }

  /// Gagal bila kategori masih dipakai transaksi.
  Future<void> deleteCategory(String id) async {
    try {
      final rows =
          await _db.from('categories').delete().eq('id', id).select('id');
      if (rows.isEmpty) {
        throw const PostgrestException(
            message: 'Kategori ini tidak dapat dihapus.');
      }
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw const PostgrestException(
            message: 'Kategori masih dipakai transaksi. Ubah namanya saja.');
      }
      rethrow;
    }
  }

  // --- Riwayat aktivitas (Pemilik/Admin) ---

  Future<List<ActivityEntry>> activity() async {
    final rows = await _db
        .from('activity_log')
        .select('user_id, action, entity, detail, at')
        .eq('business_id', businessId)
        .order('at', ascending: false)
        .limit(100);
    final profiles =
        await _db.from('profiles').select('id, display_name, email');
    final names = {
      for (final p in profiles)
        p['id'] as String:
            (p['display_name'] ?? p['email'] ?? 'Anggota') as String,
    };
    return [
      for (final r in rows)
        ActivityEntry(
          names[r['user_id']] ?? 'Seseorang',
          r['action'] as String,
          r['entity'] as String,
          Map<String, dynamic>.from((r['detail'] ?? {}) as Map),
          DateTime.parse(r['at'] as String).toLocal(),
        ),
    ];
  }

  // --- Akun ---

  Future<void> updateDisplayName(String name) async {
    await _db.from('profiles').update({'display_name': name.trim()}).eq(
        'id', _db.auth.currentUser!.id);
  }

  Future<void> changePassword(String password) async {
    await _db.auth.updateUser(UserAttributes(password: password));
  }

  String? _clean(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
