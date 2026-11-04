import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'calc_expression.dart';
import 'format.dart';
import '../settings/input_prefs.dart';

/// Perangkat sentuh (Android dan iPhone, termasuk web di ponsel).
bool get isMobilePlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Di ponsel kolom nominal membuka keyboard kalkulator (angka, 00, 000, +, −, ×
/// dan "="), kecuali pengguna mematikannya di Pengaturan sehingga keyboard bawaan
/// ponsel yang dipakai. Di komputer tetap kolom ketik biasa.
bool get useCalcKeypad => isMobilePlatform && inputPrefs.calcKeypad;

/// Kolom nominal rupiah. Isinya tetap teks berpemisah ribuan di [controller],
/// jadi dibaca dengan `parseAmount` seperti sebelumnya.
class AmountField extends StatefulWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.decoration = const InputDecoration(),
    this.style,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
    this.onChanged,
    this.title = 'Jumlah',
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final TextStyle? style;
  final TextAlign textAlign;

  /// Langsung membuka keyboard saat layar tampil.
  final bool autofocus;

  /// Dipanggil setelah nilai berubah.
  final VoidCallback? onChanged;

  /// Judul di atas keyboard kalkulator.
  final String title;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  @override
  void initState() {
    super.initState();
    if (widget.autofocus && useCalcKeypad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open();
      });
    }
  }

  Future<void> _open() async {
    FocusScope.of(context).unfocus();
    final result = await showCalcKeypad(
      context,
      title: widget.title,
      initial: parseAmount(widget.controller.text),
    );
    if (result == null || !mounted) return;
    widget.controller.text = result > 0 ? thousands(result) : '';
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: inputPrefs,
        builder: (context, _) => _field(),
      );

  Widget _field() {
    if (!useCalcKeypad) {
      return TextField(
        controller: widget.controller,
        autofocus: widget.autofocus,
        textAlign: widget.textAlign,
        keyboardType: TextInputType.number,
        onChanged: (_) => widget.onChanged?.call(),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          ThousandsFormatter(),
        ],
        style: widget.style,
        decoration: widget.decoration,
      );
    }
    return TextField(
      controller: widget.controller,
      readOnly: true,
      showCursor: false,
      enableInteractiveSelection: false,
      keyboardType: TextInputType.none,
      textAlign: widget.textAlign,
      onTap: _open,
      style: widget.style,
      decoration: widget.decoration,
    );
  }
}

/// Membuka keyboard kalkulator. Mengembalikan jumlah (bilangan bulat, tidak negatif)
/// atau null bila ditutup tanpa memilih.
Future<int?> showCalcKeypad(
  BuildContext context, {
  String title = 'Jumlah',
  int? initial,
}) {
  return showModalBottomSheet<int>(
    context: context,
    // Tanpa ini tinggi lembar dibatasi 9/16 layar dan tombol bawah terpotong.
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (_) => _CalcSheet(title: title, initial: initial),
  );
}

class _CalcSheet extends StatefulWidget {
  const _CalcSheet({required this.title, required this.initial});

  final String title;
  final int? initial;

  @override
  State<_CalcSheet> createState() => _CalcSheetState();
}

class _CalcSheetState extends State<_CalcSheet> {
  static const _maxLength = 24;

  late String _expr = (widget.initial ?? 0) > 0 ? '${widget.initial}' : '';

  String get _lastNumber {
    final m = RegExp(r'[0-9]*$').firstMatch(_expr);
    return m?.group(0) ?? '';
  }

  bool get _endsWithOperator =>
      _expr.isNotEmpty && isCalcOperator(_expr[_expr.length - 1]);

  bool get _hasOperator => _expr.split('').any(isCalcOperator);

  void _digits(String d) {
    if (_expr.length + d.length > _maxLength) return;
    final last = _lastNumber;
    setState(() {
      if (last.isEmpty || last == '0') {
        // Tidak ada angka nol di depan: "0" diganti angka baru, "00"/"000" diabaikan.
        if (d.replaceAll('0', '').isEmpty) {
          if (last.isEmpty) _expr += '0';
          return;
        }
        _expr = _expr.substring(0, _expr.length - last.length) + d;
      } else {
        _expr += d;
      }
    });
  }

  void _operator(String op) {
    if (_expr.isEmpty) return;
    setState(() {
      _expr = _endsWithOperator
          ? _expr.substring(0, _expr.length - 1) + op
          : _expr + op;
    });
  }

  void _backspace() {
    if (_expr.isEmpty) return;
    setState(() => _expr = _expr.substring(0, _expr.length - 1));
  }

  BigInt? get _value => evalCalc(_expr);

  void _equals() {
    final v = _value;
    if (v == null || v < BigInt.zero) return;
    setState(() => _expr = v == BigInt.zero ? '' : v.toString());
  }

  void _done() {
    if (_expr.isEmpty) {
      Navigator.pop(context, 0);
      return;
    }
    final v = _value;
    if (v == null || v < BigInt.zero) return;
    Navigator.pop(context, v.toInt());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = _value;
    final negative = value != null && value < BigInt.zero;
    final tooBig = _expr.isNotEmpty && value == null && !_endsWithOperatorOnly;

    String preview;
    if (_expr.isEmpty) {
      preview = ' ';
    } else if (tooBig) {
      preview = 'Hasil terlalu besar';
    } else if (negative) {
      preview = 'Hasil negatif';
    } else if (_hasOperator && value != null) {
      preview = '= ${thousands(value.toInt())}';
    } else {
      preview = ' ';
    }

    Widget key(String label,
        {VoidCallback? onTap,
        Widget? child,
        bool operator = false,
        int flex = 1}) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              padding: EdgeInsets.zero,
              backgroundColor: operator
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              foregroundColor:
                  operator ? scheme.onPrimaryContainer : scheme.onSurface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: onTap,
            child: child ??
                Text(label,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ),
      );
    }

    Widget numberKey(String d) => key(d, onTap: () => _digits(d));
    Widget opKey(String op) =>
        key(op, operator: true, onTap: () => _operator(op));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(children: [
              Text(widget.title,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  _expr.isEmpty ? '0' : formatCalc(_expr),
                  maxLines: 1,
                  style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _expr.isEmpty
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface),
                ),
              ),
              const SizedBox(height: 2),
              Text(preview,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: negative || tooBig
                          ? scheme.error
                          : scheme.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            numberKey('7'),
            numberKey('8'),
            numberKey('9'),
            key('',
                onTap: _backspace,
                child: const Icon(Icons.backspace_outlined, size: 22)),
          ]),
          Row(children: [
            numberKey('4'),
            numberKey('5'),
            numberKey('6'),
            opKey(calcMul),
          ]),
          Row(children: [
            numberKey('1'),
            numberKey('2'),
            numberKey('3'),
            opKey(calcSub),
          ]),
          Row(children: [
            numberKey('0'),
            numberKey('00'),
            numberKey('000'),
            opKey(calcAdd),
          ]),
          Row(children: [
            key('C', onTap: () => setState(() => _expr = '')),
            key('=', operator: true, onTap: _equals),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: negative || tooBig ? null : _done,
                  child: const Text('Selesai'),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  /// Hanya operator (mis. "×") tanpa angka: belum bisa dihitung, tetapi bukan "terlalu besar".
  bool get _endsWithOperatorOnly => !RegExp(r'[0-9]').hasMatch(_expr);
}
