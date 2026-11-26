import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../common/dialogs.dart';
import '../common/widgets.dart';
import '../theme/app_theme.dart';

/// Wadah foto profil pembukuan di Supabase Storage.
const businessPhotoBucket = 'business-photos';

/// Sisi terpanjang foto setelah dikecilkan, dan batas ukuran berkas.
const businessPhotoSize = 256.0;
const businessPhotoMaxBytes = 300 * 1024;

/// Gambar yang dipilih pengguna, sudah dikecilkan.
class PickedPhoto {
  const PickedPhoto(this.bytes, this.mimeType);

  final Uint8List bytes;
  final String mimeType;

  String get extension => switch (mimeType) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };
}

/// Jenis berkas dari nama atau jenis yang dilaporkan pemilih gambar.
/// Hanya JPEG, PNG, dan WebP yang diterima wadah foto.
String? photoMimeType(String? reported, String name) {
  const allowed = {'image/jpeg', 'image/png', 'image/webp'};
  if (reported != null && allowed.contains(reported)) return reported;
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  return null;
}

/// Menyimpan dan menghapus foto profil satu pembukuan. Dapat diganti tiruan saat diuji.
class BusinessPhotoRepository {
  BusinessPhotoRepository(this.businessId);

  final String businessId;
  SupabaseClient get _db => Supabase.instance.client;

  /// Mengunggah foto baru, menyimpan alamatnya, lalu membuang berkas lama agar
  /// penyimpanan tidak menumpuk. Mengembalikan alamat foto.
  Future<String> upload(PickedPhoto photo) async {
    final storage = _db.storage.from(businessPhotoBucket);
    // Nama acak: alamat lama yang tersimpan di perangkat tidak menampilkan foto usang.
    // Batas ditulis sebagai angka biasa, bukan geser bit: di web (JavaScript)
    // `1 << 32` bernilai 0 dan membuat pembuat angka acak gagal.
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final path =
        '$businessId/${DateTime.now().millisecondsSinceEpoch}$random.${photo.extension}';
    await storage.uploadBinary(
      path,
      photo.bytes,
      fileOptions: FileOptions(
          contentType: photo.mimeType, cacheControl: '31536000', upsert: false),
    );
    final url = storage.getPublicUrl(path);
    await _setUrl(url);
    await _removeExcept(path);
    return url;
  }

  Future<void> remove() async {
    await _setUrl(null);
    await _removeExcept(null);
  }

  Future<void> _setUrl(String? url) async {
    final rows = await _db
        .from('businesses')
        .update({'photo_url': url})
        .eq('id', businessId)
        .select('id');
    if (rows.isEmpty) {
      throw const PostgrestException(
          message: 'Hanya Pemilik dan Admin yang bisa mengganti foto.');
    }
  }

  /// Membuang berkas selain [keep]. Gagal membersihkan tidak membatalkan penggantian.
  Future<void> _removeExcept(String? keep) async {
    try {
      final storage = _db.storage.from(businessPhotoBucket);
      final files = await storage.list(path: businessId);
      final old = [
        for (final f in files)
          if ('$businessId/${f.name}' != keep) '$businessId/${f.name}',
      ];
      if (old.isNotEmpty) await storage.remove(old);
    } catch (_) {
      // Berkas lama tersisa hanya memakai sedikit ruang; dibersihkan pada penggantian berikutnya.
    }
  }
}

/// Memilih gambar dari galeri atau berkas dan mengecilkannya.
/// Mengembalikan null bila pengguna batal; melempar [FormatException] bila tidak cocok.
Future<PickedPhoto?> pickBusinessPhoto() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: businessPhotoSize,
    maxHeight: businessPhotoSize,
    imageQuality: 85,
  );
  if (file == null) return null;
  final mime = photoMimeType(file.mimeType, file.name);
  if (mime == null) {
    throw const FormatException('Pakai gambar JPG, PNG, atau WebP.');
  }
  final bytes = await file.readAsBytes();
  if (bytes.length > businessPhotoMaxBytes) {
    throw const FormatException(
        'Gambar terlalu besar. Pilih gambar lain yang lebih kecil.');
  }
  return PickedPhoto(bytes, mime);
}

/// Pengaturan > Profil pembukuan: foto (ganti atau hapus), nama, alamat, dan nomor
/// telepon dalam satu halaman (Pemilik dan Admin). Tanpa [loadProfile] hanya foto.
class BusinessPhotoPage extends StatefulWidget {
  const BusinessPhotoPage({
    super.key,
    required this.businessId,
    required this.businessName,
    required this.photoUrl,
    required this.onChanged,
    this.loadProfile,
    this.saveProfile,
    BusinessPhotoRepository? repo,
    Future<PickedPhoto?> Function()? picker,
  })  : _repo = repo,
        _picker = picker;

  /// Membaca nama, alamat, dan telepon pembukuan.
  final Future<Map<String, dynamic>> Function()? loadProfile;

  /// Menyimpan nama, alamat, dan telepon.
  final Future<void> Function(String name, String address, String phone)?
      saveProfile;

  final String businessId;
  final String businessName;
  final String? photoUrl;

  /// Dipanggil dengan alamat baru, atau null setelah foto dihapus.
  final ValueChanged<String?> onChanged;

  final BusinessPhotoRepository? _repo;
  final Future<PickedPhoto?> Function()? _picker;

  @override
  State<BusinessPhotoPage> createState() => _BusinessPhotoPageState();
}

class _BusinessPhotoPageState extends State<BusinessPhotoPage> {
  late final BusinessPhotoRepository _repo =
      widget._repo ?? BusinessPhotoRepository(widget.businessId);
  late String? _url = widget.photoUrl;
  bool _busy = false;
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  bool _loaded = false;

  bool get _withProfile => widget.loadProfile != null;

  @override
  void initState() {
    super.initState();
    _name.text = widget.businessName;
    final load = widget.loadProfile;
    if (load != null) {
      load().then((d) {
        if (!mounted) return;
        setState(() {
          _name.text = (d['name'] as String?) ?? widget.businessName;
          _address.text = (d['address'] as String?) ?? '';
          _phone.text = (d['phone'] as String?) ?? '';
          _loaded = true;
        });
      }).catchError((Object e) {
        if (mounted) setState(() => _loaded = true);
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final save = widget.saveProfile;
    if (save == null) return;
    if (_name.text.trim().isEmpty) {
      _toast('Nama pembukuan wajib diisi.');
      return;
    }
    setState(() => _busy = true);
    try {
      await save(_name.text, _address.text, _phone.text);
      if (mounted) _toast('Profil pembukuan disimpan.');
    } on PostgrestException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _change() async {
    setState(() => _busy = true);
    try {
      final photo = await (widget._picker ?? pickBusinessPhoto)();
      if (photo == null) return;
      final url = await _repo.upload(photo);
      if (!mounted) return;
      setState(() => _url = url);
      widget.onChanged(url);
      _toast('Foto profil diganti.');
    } on FormatException catch (e) {
      if (mounted) _toast(e.message);
    } on StorageException catch (e) {
      if (mounted) _toast('Gagal mengunggah: ${e.message}');
    } on PostgrestException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('Gagal mengganti foto: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final ok = await confirmDialog(context,
        title: 'Hapus foto profil?',
        body: 'Pembukuan akan kembali memakai inisial nama.',
        okLabel: 'Hapus');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _repo.remove();
      if (!mounted) return;
      setState(() => _url = null);
      widget.onChanged(null);
      _toast('Foto profil dihapus.');
    } on PostgrestException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('Gagal menghapus foto: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
          title: Text(_withProfile ? 'Profil pembukuan' : 'Foto profil')),
      body: ContentWidth(
        maxWidth: 480,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
          children: [
            Center(
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _busy ? null : _change,
                child: InitialAvatar(widget.businessName,
                    size: 112, photoUrl: _url),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
              TextButton.icon(
                onPressed: _busy ? null : _change,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(_url == null ? 'Pilih foto' : 'Ganti foto'),
              ),
              if (_url != null)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Brand.expense),
                  onPressed: _busy ? null : _remove,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Hapus foto'),
                ),
            ]),
            if (_busy) const LinearProgressIndicator(),
            if (_withProfile) ...[
              const SizedBox(height: 16),
              if (!_loaded)
                const Center(child: CircularProgressIndicator())
              else ...[
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      const InputDecoration(labelText: 'Nama pembukuan'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Alamat'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'No. telepon'),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _saveProfile,
                  child: const Text('Simpan'),
                ),
              ],
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: Text(widget.businessName,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
