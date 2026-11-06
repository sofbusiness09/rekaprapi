import 'package:flutter/material.dart';

import 'widgets.dart';

/// Satu baris rincian: label di kiri, nilai di kanan. Dipakai di halaman detail
/// transaksi dan detail utang.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value,
      {super.key, this.color, this.bold = false});

  final String label;
  final String value;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 4,
          child: Text(label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 6,
          child: Text(value,
              textAlign: TextAlign.right,
              style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
                  color: color)),
        ),
      ]),
    );
  }
}

/// Kartu berisi baris-baris rincian yang dipisah garis tipis.
class DetailCard extends StatelessWidget {
  const DetailCard({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(),
          rows[i],
        ],
      ]),
    );
  }
}
