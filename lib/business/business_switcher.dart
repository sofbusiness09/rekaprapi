import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../common/dialogs.dart';
import '../common/widgets.dart';
import '../theme/app_theme.dart';
import 'business.dart';
import 'business_controller.dart';
import '../common/glass.dart';

const roleNames = {'owner': 'Pemilik', 'admin': 'Admin', 'staff': 'Staf'};

/// Menjalankan [action] dan menampilkan galat sebagai pesan, bukan membiarkannya diam.
Future<void> runWithToast(
  BuildContext context,
  Future<void> Function() action, {
  String? done,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
  } on PostgrestException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Gagal: $e')));
  }
}

Future<void> promptCreateBusiness(
    BuildContext context, BusinessController controller) async {
  final name = await askText(context, title: 'Usaha baru', label: 'Nama usaha');
  if (name == null || name.isEmpty || !context.mounted) return;
  await runWithToast(context, () => controller.create(name),
      done: 'Usaha dibuat.');
}

Future<void> promptJoinByCode(
    BuildContext context, BusinessController controller) async {
  final code = await askText(context,
      title: 'Gabung dengan kode', label: 'Kode undangan');
  if (code == null || code.isEmpty || !context.mounted) return;
  await runWithToast(context, () => controller.joinByCode(code),
      done: 'Berhasil bergabung.');
}

/// Lembar pindah usaha: daftar usaha, undangan, tambah usaha, dan gabung dengan kode.
/// Dibuka dari nama usaha di sidebar/bilah atas.
///
/// [onOpenSettings] menambahkan baris Pengaturan; dipakai di ponsel, tempat
/// Pengaturan tidak punya tab sendiri.
Future<void> showBusinessSwitcher(
  BuildContext context,
  BusinessController controller, {
  VoidCallback? onOpenSettings,
}) {
  return showGlassSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (sheetContext) => _SwitcherSheet(
      controller: controller,
      parentContext: context,
      onOpenSettings: onOpenSettings,
    ),
  );
}

class _SwitcherSheet extends StatelessWidget {
  const _SwitcherSheet({
    required this.controller,
    required this.parentContext,
    this.onOpenSettings,
  });

  final BusinessController controller;
  final VoidCallback? onOpenSettings;

  /// Konteks halaman di belakang lembar, dipakai untuk dialog dan pesan.
  final BuildContext parentContext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Usaha milik sendiri dipisah dari usaha yang dibagikan lewat undangan.
        final mine = [
          for (final b in controller.businesses)
            if (b.role == 'owner') b,
        ];
        final shared = [
          for (final b in controller.businesses)
            if (b.role != 'owner') b,
        ];
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Pindah usaha',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (mine.isNotEmpty) ...[
                  _SectionLabel('Usaha saya', muted),
                  for (final b in mine) _businessTile(context, theme, b),
                ],
                if (shared.isNotEmpty) ...[
                  _SectionLabel('Dibagikan kepada saya', muted),
                  for (final b in shared) _businessTile(context, theme, b),
                ],
                if (controller.invites.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('Undangan untuk Anda',
                        style:
                            theme.textTheme.labelLarge?.copyWith(color: muted)),
                  ),
                  for (final i in controller.invites)
                    ListTile(
                      leading: const IconBadge(Icons.mail_rounded,
                          color: Brand.info, size: 42),
                      title: Text(i.businessName,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('Sebagai ${roleNames[i.role] ?? i.role}'),
                      trailing: Wrap(spacing: 4, children: [
                        IconButton(
                          tooltip: 'Tolak',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => runWithToast(
                              parentContext, () => controller.decline(i.id)),
                        ),
                        IconButton(
                          tooltip: 'Terima',
                          icon: const Icon(Icons.check_rounded,
                              color: Brand.income),
                          onPressed: () {
                            Navigator.pop(context);
                            runWithToast(
                                parentContext, () => controller.accept(i.id),
                                done: 'Berhasil bergabung.');
                          },
                        ),
                      ]),
                    ),
                ],
                const Divider(height: 24),
                ListTile(
                  leading: const IconBadge(Icons.add_rounded,
                      color: Brand.income, size: 42),
                  title: const Text('Tambah usaha',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Catatan usaha Anda sendiri, terpisah dari usaha yang dibagikan. Maksimal 5.'),
                  onTap: () {
                    Navigator.pop(context);
                    promptCreateBusiness(parentContext, controller);
                  },
                ),
                ListTile(
                  leading: const IconBadge(Icons.vpn_key_rounded,
                      color: Brand.info, size: 42),
                  title: const Text('Gabung dengan kode',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Masuk ke usaha lain lewat undangan'),
                  onTap: () {
                    Navigator.pop(context);
                    promptJoinByCode(parentContext, controller);
                  },
                ),
                if (onOpenSettings != null) ...[
                  const Divider(height: 24),
                  ListTile(
                    leading: const IconBadge(Icons.settings_rounded,
                        color: Brand.profit, size: 42),
                    title: const Text('Pengaturan',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle:
                        const Text('Usaha, tim, kategori, tampilan, backup'),
                    onTap: () {
                      Navigator.pop(context);
                      onOpenSettings!();
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _businessTile(BuildContext context, ThemeData theme, Business b) {
    final selected = b.id == controller.current?.id;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      selected: selected,
      selectedTileColor:
          theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
      leading: InitialAvatar(b.name, size: 42),
      title: Text(b.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(roleNames[b.role] ?? b.role),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: Brand.income)
          : null,
      onTap: () {
        Navigator.pop(context);
        controller.select(b);
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text,
            style:
                Theme.of(context).textTheme.labelLarge?.copyWith(color: color)),
      );
}
