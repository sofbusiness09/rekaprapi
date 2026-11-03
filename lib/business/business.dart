class Business {
  const Business({required this.id, required this.name, required this.role});

  final String id;
  final String name;

  /// 'owner' | 'admin' | 'staff'
  final String role;

  bool get canManage => role == 'owner' || role == 'admin';
}
