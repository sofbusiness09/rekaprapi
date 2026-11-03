import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../common/dialogs.dart';
import '../common/widgets.dart';
import '../theme/app_theme.dart';
import 'business_controller.dart';

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
Future<void> showBusinessSwitcher(
    BuildContext context, BusinessController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (sheetContext) =>
        _SwitcherSheet(controller: controller, parentContext: context),
  );
}

class _SwitcherSheet extends StatelessWidget {
  const _SwitcherSheet({required this.controller, required this.parentContext});

  final BusinessController controller;

  /// Konteks halaman di belakang lembar, dipakai untuk dialog dan pesan.
  final BuildContext parentContext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => SafeArea(
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
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              for (final b in controller.businesses)
                ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  selected: b.id == controller.current?.id,
                  selectedTileColor:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  leading: InitialAvatar(b.name, size: 42),
                  title: Text(b.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(roleNames[b.role] ?? b.role),
                  trailing: b.id == controller.current?.id
                      ? const Icon(Icons.check_circle_rounded,
                          color: Brand.income)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    controller.select(b);
                  },
                ),
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
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Maksimal 5 usaha milik Anda'),
                onTap: () {
                  Navigator.pop(context);
                  promptCreateBusiness(parentContext, controller);
                },
              ),
              ListTile(
                leading: const IconBadge(Icons.vpn_key_rounded,
                    color: Brand.info, size: 42),
                title: const Text('Gabung dengan kode',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Masuk ke usaha lain lewat undangan'),
                onTap: () {
                  Navigator.pop(context);
                  promptJoinByCode(parentContext, controller);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
