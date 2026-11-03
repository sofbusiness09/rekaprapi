import 'package:flutter/material.dart';

import '../common/format.dart';
import 'settings_repository.dart';

const _verbs = {
  'create': 'menambah',
  'update': 'mengubah',
  'delete': 'menghapus',
  'remove': 'mengeluarkan',
};

const _nouns = {
  'cash_transactions': 'transaksi kas',
  'debts': 'catatan utang piutang',
  'debt_payments': 'pembayaran utang piutang',
  'business_members': 'anggota',
};

class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key, required this.repo});

  final SettingsRepository repo;

  String _describe(ActivityEntry e) {
    final amount = e.detail['amount'];
    final kind = e.detail['kind'];
    final type = e.detail['type'];
    final parts = <String>[
      '${e.who} ${_verbs[e.action] ?? e.action} ${_nouns[e.entity] ?? e.entity}',
      if (kind == 'receivable') '(piutang)',
      if (kind == 'payable') '(utang)',
      if (type == 'in') '(masuk)',
      if (type == 'out') '(keluar)',
      if (amount is num) rupiah(amount),
    ];
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat aktivitas')),
      body: FutureBuilder<List<ActivityEntry>>(
        future: repo.activity(),
        builder: (context, snap) {
          if (snap.hasError)
            return Center(child: Text('Gagal memuat: ${snap.error}'));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty)
            return const Center(child: Text('Belum ada aktivitas.'));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => ListTile(
              title: Text(_describe(items[i])),
              subtitle: Text(timeId(items[i].at)),
            ),
          );
        },
      ),
    );
  }
}
