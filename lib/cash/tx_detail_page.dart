import 'package:flutter/material.dart';

import '../common/detail_rows.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../theme/app_theme.dart';
import 'cash_models.dart';

/// Rincian satu transaksi kas. Menutup dengan 'edit' atau 'delete' bila pengguna
/// memilih Ubah atau Hapus; pemanggil yang menjalankannya.
class TxDetailPage extends StatelessWidget {
  const TxDetailPage({
    super.key,
    required this.tx,
    required this.category,
    required this.recorder,
    required this.canEdit,
    this.showProfit = true,
  });

  final CashTx tx;
  final String? category;

  /// Nama pencatat, bila diketahui.
  final String? recorder;
  final bool canEdit;

  /// false untuk Staf dan Pembukuan Pribadi: modal dan keuntungan tidak ditampilkan.
  final bool showProfit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final tone = amountColor(tx.isIn);
    final sale = tx.isSale;
    final profit = tx.profit;

    return Scaffold(
      appBar: AppBar(title: const Text('Detail transaksi')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SoftCard(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconBadge(categoryIcon(category, income: tx.isIn), color: tone),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(category ?? 'Tanpa kategori',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('${tx.isIn ? '+' : '-'}${rupiah(tx.amount)}',
                    style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w600, color: tone, height: 1.1)),
              ),
              const SizedBox(height: 4),
              Text(tx.isIn ? 'Pemasukan · Lunas' : 'Pengeluaran · Lunas',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
            ]),
          ),
          const SizedBox(height: 12),
          DetailCard(rows: [
            if (sale) ...[
              DetailRow('Total penjualan', rupiah(tx.saleTotal)),
              if (tx.discountAmount > 0)
                DetailRow('Diskon', '-${rupiah(tx.discountAmount)}'),
              if (tx.extraFee > 0)
                DetailRow('Biaya tambahan', rupiah(tx.extraFee)),
              DetailRow('Pemasukan', rupiah(tx.amount)),
              if (showProfit) ...[
                DetailRow('Modal', rupiah(tx.costAmount), color: Brand.expense),
                DetailRow(profit >= 0 ? 'Keuntungan' : 'Kerugian',
                    rupiah(profit.abs()),
                    color: profit >= 0 ? profitColor(context) : Brand.expense,
                    bold: true),
              ],
            ] else
              DetailRow('Jumlah', rupiah(tx.amount), bold: true),
            DetailRow('Tanggal dan jam', dateTimeId(tx.date, tx.createdAt)),
            if (recorder != null) DetailRow('Dicatat oleh', recorder!),
            if (tx.note != null) DetailRow('Catatan', tx.note!),
          ]),
          if (tx.isAuto)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
              child: Text('Dibuat otomatis dari utang piutang.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ),
          if (canEdit) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'edit'),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Ubah'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Brand.expense,
                side: const BorderSide(color: Brand.expense),
              ),
              onPressed: () => Navigator.pop(context, 'delete'),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Hapus'),
            ),
          ],
        ],
      ),
    );
  }
}
