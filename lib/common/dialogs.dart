import 'package:flutter/material.dart';

/// Dialog satu isian teks. Mengembalikan teks (sudah di-trim) atau null bila dibatalkan.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  bool obscure = false,
  TextInputType? keyboard,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextDialog(
        title: title,
        label: label,
        initial: initial,
        obscure: obscure,
        keyboard: keyboard),
  );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.obscure,
    required this.keyboard,
  });

  final String title;
  final String label;
  final String initial;
  final bool obscure;
  final TextInputType? keyboard;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        obscureText: widget.obscure,
        keyboardType: widget.keyboard,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (_) => Navigator.pop(context, _c.text.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _c.text.trim()),
            child: const Text('OK')),
      ],
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String okLabel = 'Ya',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(okLabel)),
      ],
    ),
  );
  return ok == true;
}
