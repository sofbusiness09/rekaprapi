import 'package:flutter/material.dart';

import 'phone_contacts.dart';

/// Tombol "Dari kontak HP": mengisi nama dan nomor dari satu kontak yang dipilih.
/// Tidak tampil di web.
class PhoneContactButton extends StatelessWidget {
  const PhoneContactButton({super.key, required this.onPicked});

  final void Function(String name, String? phone) onPicked;

  @override
  Widget build(BuildContext context) {
    if (!phoneContactsSupported) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.contact_phone_outlined),
        label: const Text('Dari kontak HP'),
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            final c = await pickPhoneContact();
            if (c != null) onPicked(c.name, c.phone);
          } catch (e) {
            messenger.showSnackBar(
                SnackBar(content: Text('Kontak HP tidak bisa dibuka: $e')));
          }
        },
      ),
    );
  }
}
