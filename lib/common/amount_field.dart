import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'calc_expression.dart';
import 'format.dart';
import '../settings/input_prefs.dart';
import 'package:rekap_rapi/l10n/l10n.dart';

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
    // Di halaman catat, kalkulator menempel di bawah halaman (tidak menutupi
    // formulir dan tombol Simpan).
    final host = CalcHost.maybeOf(context);
    if (host != null) {
      host.attach(widget.controller, widget.title, widget.onChanged);
      // Kalkulator memperkecil ruang isian: geser kolom ini agar tetap terlihat.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(context,
            duration: const Duration(milliseconds: 200),
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      });
      return;
    }
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

class _CalcSheet extends StatelessWidget {
  const _CalcSheet({required this.title, required this.initial});

  final String title;
  final int? initial;

  @override
  Widget build(BuildContext context) => CalcKeypad(
        title: title,
        initial: initial,
        onDone: (v) => Navigator.pop(context, v),
      );
}

/// Keyboard kalkulator: angka, 00, 000, +, −, ×, =, hapus, dan Selesai.
/// [onDone] menerima hasil (bilangan bulat, tidak negatif). Bila [onChanged] diisi,
/// hasil sementara dikirim setiap tombol ditekan (dipakai kalkulator menempel).
/// [docked]: menempel di bawah halaman, tanpa judul dan tanpa layar besar.
class CalcKeypad extends StatefulWidget {
  const CalcKeypad({
    super.key,
    required this.title,
    required this.initial,
    required this.onDone,
    this.onChanged,
    this.docked = false,
  });

  final String title;
  final int? initial;
  final ValueChanged<int> onDone;
  final ValueChanged<int>? onChanged;
  final bool docked;

  @override
  State<CalcKeypad> createState() => _CalcKeypadState();
}

class _CalcKeypadState extends State<CalcKeypad> {
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

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    // Kalkulator menempel: kolom jumlah ikut berubah selama mengetik. Isi kosong
    // (setelah C atau menghapus angka terakhir) mengosongkan kolom.
    final onChanged = widget.onChanged;
    if (onChanged == null) return;
    if (_expr.isEmpty) {
      onChanged(0);
      return;
    }
    final v = _value;
    if (v != null && v >= BigInt.zero) onChanged(v.toInt());
  }

  void _equals() {
    final v = _value;
    if (v == null || v < BigInt.zero) return;
    setState(() => _expr = v == BigInt.zero ? '' : v.toString());
  }

  void _done() {
    if (_expr.isEmpty) {
      widget.onDone(0);
      return;
    }
    final v = _value;
    if (v == null || v < BigInt.zero) return;
    widget.onDone(v.toInt());
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
      preview = tr('Hasil terlalu besar');
    } else if (negative) {
      preview = tr('Hasil negatif');
    } else if (_hasOperator && value != null) {
      preview = '= ${thousands(value.toInt())}';
    } else {
      preview = ' ';
    }

    // Menempel: tombol lebih pendek agar kolom isian di atasnya tetap lega.
    final keyHeight = widget.docked ? 42.0 : 52.0;

    Widget key(String label,
        {VoidCallback? onTap,
        Widget? child,
        bool operator = false,
        int flex = 1}) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: EdgeInsets.all(widget.docked ? 3 : 4),
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(
              minimumSize: Size.fromHeight(keyHeight),
              padding: EdgeInsets.zero,
              // Tombol sudah rapat satu sama lain; tanpa bantalan sentuh tambahan
              // yang membuat tiap baris lebih tinggi dari tampilannya.
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

    final docked = widget.docked;
    return SafeArea(
      top: !docked,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            docked ? 5 : 12, 0, docked ? 5 : 12, docked ? 4 : 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!docked)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Row(children: [
                Text(widget.title,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
          // Menempel: kolom jumlah sudah menampilkan hasil; di sini cukup hitungannya.
          if (docked)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
              child: Row(children: [
                Text(widget.title,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const Spacer(),
                Flexible(
                  flex: 4,
                  child: Text(
                      _hasOperator ? '${formatCalc(_expr)}  $preview' : preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: negative || tooBig
                              ? scheme.error
                              : scheme.onSurfaceVariant)),
                ),
              ]),
            )
          else
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
          SizedBox(height: docked ? 2 : 8),
          // Empat baris, lima kolom: operator di dua kolom kanan. C di pojok kanan atas,
          // merah dan jauh dari Selesai agar tidak tertekan saat hendak menyimpan.
          Row(children: [
            numberKey('7'),
            numberKey('8'),
            numberKey('9'),
            key('',
                onTap: _backspace,
                child: const Icon(Icons.backspace_outlined, size: 22)),
            key('C',
                onTap: () => setState(() => _expr = ''),
                child: Text('C',
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700, color: scheme.error))),
          ]),
          Row(children: [
            numberKey('4'),
            numberKey('5'),
            numberKey('6'),
            opKey(calcMul),
            opKey(calcSub),
          ]),
          Row(children: [
            numberKey('1'),
            numberKey('2'),
            numberKey('3'),
            opKey(calcAdd),
            key('=', operator: true, onTap: _equals),
          ]),
          Row(children: [
            numberKey('0'),
            numberKey('00'),
            numberKey('000'),
            Expanded(
              flex: 2,
              child: Padding(
                padding: EdgeInsets.all(docked ? 3 : 4),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: Size.fromHeight(keyHeight),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: negative || tooBig ? null : _done,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_rounded, size: 22),
                      const SizedBox(width: 6),
                      Text(tr('Selesai')),
                    ]),
                  ),
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

/// Halaman dengan kalkulator yang menempel di bawah: isi halaman ([child]) bisa
/// digeser, [bottomBar] (tombol Simpan dan sejenisnya) selalu terlihat tepat di atas
/// kalkulator atau keyboard ponsel, dan kalkulator tampil saat kolom jumlah aktif.
/// Saat kolom teks biasa aktif, kalkulator turun dan keyboard ponsel yang tampil.
class CalcHost extends StatefulWidget {
  const CalcHost({super.key, required this.child, required this.bottomBar});

  final Widget child;
  final Widget bottomBar;

  /// Kalkulator menempel terdekat, atau null (mis. di layar tanpa CalcHost).
  static CalcHostState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<CalcHostState>();

  @override
  State<CalcHost> createState() => CalcHostState();
}

class CalcHostState extends State<CalcHost> {
  TextEditingController? _target;
  String _title = 'Jumlah';
  VoidCallback? _onChanged;

  /// Kolom yang sedang diisi lewat kalkulator.
  TextEditingController? get target => _target;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocus);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocus);
    super.dispose();
  }

  /// Kolom teks biasa aktif: kalkulator turun agar keyboard ponsel yang dipakai.
  void _onFocus() {
    if (_target == null) return;
    final ctx = FocusManager.instance.primaryFocus?.context;
    final editable = ctx?.findAncestorWidgetOfExactType<EditableText>();
    if (editable != null && !editable.readOnly) detach();
  }

  void attach(
      TextEditingController controller, String title, VoidCallback? onChanged) {
    setState(() {
      _target = controller;
      _title = title;
      _onChanged = onChanged;
    });
  }

  void detach() {
    if (_target == null) return;
    setState(() => _target = null);
  }

  void _set(int v) {
    final c = _target;
    if (c == null) return;
    final text = v > 0 ? thousands(v) : '';
    if (c.text != text) {
      c.text = text;
      _onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    return Column(children: [
      Expanded(
        // Menggeser isian ke atas/bawah menurunkan kalkulator, seperti keyboard
        // ponsel, agar kolom di bawah terlihat. Kotak Jumlah membukanya lagi.
        child: NotificationListener<ScrollStartNotification>(
          onNotification: (n) {
            if (n.dragDetails != null && n.metrics.axis == Axis.vertical) {
              detach();
            }
            return false;
          },
          child: widget.child,
        ),
      ),
      widget.bottomBar,
      if (target != null)
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: CalcKeypad(
            // Kunci per kolom: kalkulator mulai dari nilai kolom yang baru dipilih.
            key: ObjectKey(target),
            title: _title,
            initial: parseAmount(target.text),
            docked: true,
            onChanged: _set,
            onDone: (v) {
              _set(v);
              detach();
            },
          ),
        ),
    ]);
  }
}
