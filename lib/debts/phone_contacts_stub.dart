/// Kontak yang dipilih dari buku kontak HP.
class PickedPhoneContact {
  const PickedPhoneContact(this.name, this.phone);

  final String name;
  final String? phone;
}

/// Web: buku kontak HP tidak tersedia.
bool get phoneContactsSupported => false;

Future<PickedPhoneContact?> pickPhoneContact() async => null;
