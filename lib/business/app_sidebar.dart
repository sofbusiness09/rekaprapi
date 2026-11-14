import 'package:flutter/material.dart';

import '../common/widgets.dart';
import '../theme/theme_picker.dart';

/// Satu menu di bilah samping.
class SidebarItem {
  const SidebarItem(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _openWidth = 236.0;
const _closedWidth = 76.0;
const _anim = Duration(milliseconds: 260);

/// Bilah samping layar lebar, gelap, dengan menu berikon. Saat menutup, seluruh isi
/// menyempit dari kanan ke kiri (ikon tetap di tempatnya); saat membuka, nama menu
/// muncul dari kiri ke kanan. Menekan avatar membuka atau menutupnya.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.extended,
    required this.onToggle,
    required this.businessName,
    this.photoUrl,
    required this.roleLabel,
    required this.onOpenSwitcher,
    required this.items,
    required this.selected,
    required this.onSelected,
    required this.accent,
    this.backupButton,
  });

  final bool extended;
  final VoidCallback onToggle;
  final String businessName;
  final String? photoUrl;
  final String roleLabel;
  final VoidCallback onOpenSwitcher;
  final List<SidebarItem> items;
  final int selected;
  final ValueChanged<int> onSelected;
  final Color accent;
  final Widget? backupButton;

  @override
  Widget build(BuildContext context) {
    // Warna dasar gelap yang diambil dari aksen, seperti pada tema desain.
    final hsl = HSLColor.fromColor(accent);
    final base = hsl.withLightness(0.11).withSaturation(0.45).toColor();
    final dark = Theme.of(context).copyWith(
      brightness: Brightness.dark,
      colorScheme:
          ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark),
    );

    return Theme(
      data: dark,
      child: AnimatedContainer(
        duration: _anim,
        curve: Curves.easeInOutCubic,
        width: extended ? _openWidth : _closedWidth,
        color: base,
        child: ClipRect(
          child: SafeArea(
            right: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
              child: Column(children: [
                _Header(
                  extended: extended,
                  onToggle: onToggle,
                  name: businessName,
                  photoUrl: photoUrl,
                  role: roleLabel,
                  onSwitch: onOpenSwitcher,
                ),
                const SizedBox(height: 24),
                for (var i = 0; i < items.length; i++) ...[
                  _Entry(
                    item: items[i],
                    selected: i == selected,
                    extended: extended,
                    accent: accent,
                    onTap: () => onSelected(i),
                  ),
                  const SizedBox(height: 6),
                ],
                const Spacer(),
                if (backupButton != null) backupButton!,
                const SizedBox(height: 8),
                _Reveal(
                  extended: extended,
                  width: 150,
                  collapsed: const ThemeModeColumn(),
                  child: const ThemeModePicker(compact: true),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Teks yang terbuka dari kiri ke kanan mengikuti lebar yang tersedia dan
/// memudar, tanpa pernah membungkus atau meluap.
class _Label extends StatelessWidget {
  const _Label({required this.extended, required this.child, this.width = 150});

  final bool extended;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: 0,
          maxWidth: width,
          child: AnimatedOpacity(
            duration: _anim,
            curve: Curves.easeOut,
            opacity: extended ? 1 : 0,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Ganti isi antara bentuk lebar (mendatar) dan ciut (tersusun) tanpa meluap.
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.extended,
    required this.child,
    required this.collapsed,
    required this.width,
  });

  final bool extended;
  final Widget child;
  final Widget collapsed;
  final double width;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: extended
          ? SizedBox(
              key: const ValueKey('open'),
              width: double.infinity,
              height: 44,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.center,
                  minWidth: 0,
                  maxWidth: width + 40,
                  child: child,
                ),
              ),
            )
          : SizedBox(key: const ValueKey('closed'), child: collapsed),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.extended,
    required this.onToggle,
    required this.name,
    required this.role,
    required this.onSwitch,
    this.photoUrl,
  });

  final String? photoUrl;

  final bool extended;
  final VoidCallback onToggle;
  final String name;
  final String role;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
        height: 52,
        child: Row(children: [
          Tooltip(
            message: extended ? 'Ciutkan menu' : 'Perluas menu',
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onToggle,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                    child: InitialAvatar(name, size: 44, photoUrl: photoUrl)),
              ),
            ),
          ),
          _Label(
            extended: extended,
            width: 170,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: extended ? onSwitch : null,
              child: Padding(
                padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
                child: Row(children: [
                  SizedBox(
                    width: 118,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                          Text(role,
                              maxLines: 1,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.6))),
                        ]),
                  ),
                  Icon(Icons.unfold_more_rounded,
                      size: 20, color: Colors.white.withValues(alpha: 0.6)),
                ]),
              ),
            ),
          ),
        ]));
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.item,
    required this.selected,
    required this.extended,
    required this.accent,
    required this.onTap,
  });

  final SidebarItem item;
  final bool selected;
  final bool extended;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? Colors.white : Colors.white.withValues(alpha: 0.7);
    return Tooltip(
      message: extended ? '' : item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: _anim,
            curve: Curves.easeOut,
            height: 48,
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.28)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected
                      ? accent.withValues(alpha: 0.9)
                      : Colors.transparent,
                  width: 1.2),
            ),
            child: Row(children: [
              SizedBox(
                width: 44,
                child: Icon(selected ? item.selectedIcon : item.icon,
                    size: 22, color: fg),
              ),
              _Label(
                extended: extended,
                child: Text(item.label,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
