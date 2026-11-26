import 'package:flutter/material.dart';

import 'currency.dart';
import 'package:rekap_rapi/l10n/l10n.dart';

/// Lembar pilihan mata uang dengan kotak cari (nama, kode, atau simbol).
/// Mengembalikan mata uang yang dipilih, atau null bila ditutup.
Future<Currency?> showCurrencyPicker(BuildContext context,
    {String? selected, String title = 'Mata uang'}) {
  return showModalBottomSheet<Currency>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => _CurrencySheet(selected: selected, title: title),
  );
}

class _CurrencySheet extends StatefulWidget {
  const _CurrencySheet({required this.selected, required this.title});

  final String? selected;
  final String title;

  @override
  State<_CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends State<_CurrencySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final items = [
      for (final c in currencies)
        if (q.isEmpty ||
            c.name.toLowerCase().contains(q) ||
            c.localName.toLowerCase().contains(q) ||
            c.code.toLowerCase().contains(q) ||
            c.symbol.toLowerCase() == q)
          c,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.title,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: tr('Cari nama atau kode, mis. Dirham atau AED'),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(tr('Mata uang tidak ditemukan.'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final c = items[i];
                        final picked = c.code == widget.selected;
                        return ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          selected: picked,
                          leading: SizedBox(
                            width: 48,
                            child: Text(c.symbol,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                          title: Text(c.localName),
                          subtitle:
                              Text('${c.code} · ${formatMoney(50000, c)}'),
                          trailing: picked
                              ? Icon(Icons.check_circle_rounded,
                                  color: theme.colorScheme.primary)
                              : null,
                          onTap: () => Navigator.pop(context, c),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
