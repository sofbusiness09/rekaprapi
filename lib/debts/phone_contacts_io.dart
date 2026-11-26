import 'dart:io' show Platform;

import 'package:flutter_contacts/flutter_contacts.dart';

export 'phone_contacts_stub.dart' show PickedPhoneContact;
import 'phone_contacts_stub.dart' show PickedPhoneContact;

/// Buku kontak hanya ada di aplikasi ponsel.
bool get phoneContactsSupported => Platform.isAndroid || Platform.isIOS;

/// Membuka buku kontak HP dan mengembalikan satu kontak yang dipilih (nama dan
/// nomor), atau null bila dibatalkan. Izin baca kontak diminta agar nomornya ikut;
/// bila ditolak, hanya nama yang terisi. Hanya kontak yang dipilih yang dibaca.
Future<PickedPhoneContact?> pickPhoneContact() async {
  var withPhone = false;
  try {
    final status =
        await FlutterContacts.permissions.request(PermissionType.read);
    withPhone = status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
  } catch (_) {
    withPhone = false;
  }
  final contact = await FlutterContacts.native
      .showPicker(properties: withPhone ? {ContactProperty.phone} : null);
  if (contact == null) return null;
  final name = (contact.displayName ?? '').trim();
  final phones = contact.phones;
  final phone = phones.isEmpty ? null : phones.first.number.trim();
  if (name.isEmpty && (phone == null || phone.isEmpty)) return null;
  return PickedPhoneContact(name.isEmpty ? phone! : name, phone);
}
