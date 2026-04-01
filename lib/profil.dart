import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_cropper/image_cropper.dart'; // KIRPMA PAKETİ
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'giris_kayit.dart';
import 'shared_bottom_nav.dart';
import 'ilanlar.dart';
import 'konum_sec_sayfasi.dart';
import 'kullanici_profili.dart';

final supabase = Supabase.instance.client;

const String _PROFIL_FOTO_KOVA_ADI = 'profil_fotolari';

// --- SORGULAR ---
const String _KAYIP_ILAN_FIELDS = 'id, hayvan_adi, hayvan_turu, hayvan_rengi, hayvan_cinsiyeti, cipi_var_mi, ekstra_bilgi, created_at, konum, konum_text';
const String _BULUNAN_ILAN_FIELDS = 'id, hayvan_turu, hayvan_rengi, hayvan_cinsiyeti, ekstra_bilgi, created_at, konum, konum_text';
const String _SAHIPLENDIRME_ILAN_FIELDS = 'id, hayvan_adi, hayvan_turu, hayvan_rengi, hayvan_cinsiyeti, cipi_var_mi, kisir_mi, kisirlastirma_sarti, aliskanliklar, ekstra_bilgi, created_at, konum, konum_text';


Future<Map<String, String?>> _ilanFotograflariniGetir(List<String> ilanIdleri, String ilanTipi) async {
  if (ilanIdleri.isEmpty) return {};

  final List<dynamic> fotos = await supabase
      .from('ilan_fotograflari')
      .select('ilan_id, foto_url')
      .inFilter('ilan_id', ilanIdleri)
      .eq('ilan_tipi', ilanTipi);

  Map<String, String?> ilanIdToFoto = {};
  for (final f in fotos) {
    final String iid = f['ilan_id'] as String;
    ilanIdToFoto.putIfAbsent(iid, () => (f['foto_url'] as String?));
  }
  return ilanIdToFoto;
}

Future<String?> _profilFotoGuvenliUrlGetir(String? dosyaYolu) async {
  if (dosyaYolu == null || dosyaYolu.isEmpty) return null;

  try {
    final String guvenliUrl = await supabase.storage
        .from(_PROFIL_FOTO_KOVA_ADI)
        .createSignedUrl(dosyaYolu, 60);

    return guvenliUrl;

  } catch (e) {
    print('Profil fotoğrafı güvenli URL hatası: $e');
    return null;
  }
}

Future<void> ilanAsilariniGuncelle(String ilanId, List<String> yeniAsiIdleri, {bool isSahiplendirme = false}) async {
  try {
    final String tabloAdi = isSahiplendirme ? 'sahiplendirme_ilan_asilar' : 'kayip_ilan_asilar';
    final String kolonAdi = isSahiplendirme ? 'sahiplendirme_ilan_id' : 'kayip_ilan_id';

    await supabase
        .from(tabloAdi)
        .delete()
        .eq(kolonAdi, ilanId);

    if (yeniAsiIdleri.isNotEmpty) {
      final List<Map<String, String>> iliskiVerileri = yeniAsiIdleri.map((asiId) {
        return {
          kolonAdi: ilanId,
          'asi_id': asiId,
        };
      }).toList();

      await supabase
          .from(tabloAdi)
          .insert(iliskiVerileri);
    }
  } catch (e) {
    throw Exception('Aşı güncelleme hatası: $e');
  }
}

LatLng? _koordinatCozumle(String? data) {
  if (data == null) return null;
  final RegExp regex = RegExp(r'POINT\((.*) (.*)\)');
  final match = regex.firstMatch(data.toString());

  if (match != null) {
    try {
      double lng = double.parse(match.group(1)!);
      double lat = double.parse(match.group(2)!);
      return LatLng(lat, lng);
    } catch (e) {
      print("Koordinat parse hatası: $e");
      return null;
    }
  }
  return null;
}

class Profil extends StatefulWidget {
  const Profil({super.key});

  @override
  State<Profil> createState() => _ProfilState();
}

class _ProfilState extends State<Profil> with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = supabase;
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _profile;
  String? _profilFotoGuvenliUrl;
  bool _isSaving = false;
  bool _isEditing = false;
  late TabController _tabController;

  int _takipciSayisi = 0;
  int _takipEdilenSayisi = 0;

  final TextEditingController _adController = TextEditingController();
  final TextEditingController _telefonController = TextEditingController();

  List<Map<String, dynamic>> _ilanlarim = [];

  List<Map<String, dynamic>> _kayipIlanlarim = [];
  List<Map<String, dynamic>> _bulunanIlanlarim = [];
  List<Map<String, dynamic>> _sahiplendirmeIlanlarim = [];
  List<Map<String, dynamic>> _repostIlanlarim = [];

  int _ilanFilterIndex = 0;

  int get _toplamIlanSayisi =>
      _kayipIlanlarim.length + _bulunanIlanlarim.length + _sahiplendirmeIlanlarim.length + _repostIlanlarim.length;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadProfile();
    _loadIlanlarim();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _adController.dispose();
    _telefonController.dispose();
    super.dispose();
  }

  Future<void> _loadTakipSayilari(String userId) async {
    try {
      final List<dynamic> takipciList = await _supabase
          .from('takipler')
          .select('id')
          .eq('takip_edilen', userId);

      final List<dynamic> takipEdilenList = await _supabase
          .from('takipler')
          .select('id')
          .eq('takip_eden', userId);

      if (mounted) {
        setState(() {
          _takipciSayisi = takipciList.length;
          _takipEdilenSayisi = takipEdilenList.length;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _takipciSayisi = 0;
          _takipEdilenSayisi = 0;
        });
      }
    }
  }


  Future<void> _loadProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
          _error = 'Oturum bulunamadı. Lütfen giriş yapın.';
        });
        return;
      }

      await _loadTakipSayilari(user.id);

      final data = await _supabase
          .from('profiles')
          .select('id, tam_ad, email, telefon, created_at, profil_foto')
          .eq('id', user.id)
          .maybeSingle();

      final Map<String, dynamic>? profilData = data as Map<String, dynamic>?;

      String? fotoYolu = profilData?['profil_foto'] as String?;
      String? guvenliUrl;
      if (fotoYolu != null) {
        guvenliUrl = await _profilFotoGuvenliUrlGetir(fotoYolu);
      }

      setState(() {
        _profile = profilData;
        _adController.text = (_profile?['tam_ad'] ?? '').toString();
        _telefonController.text = (_profile?['telefon'] ?? '').toString();
        _profilFotoGuvenliUrl = guvenliUrl;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Profil yüklenemedi: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadIlanlarim({bool refresh = false}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      //  KAYIP İLANLARI YÜKLE
      final List<dynamic> kayip = await _supabase
          .from('kayip_ilanlar')
          .select(_KAYIP_ILAN_FIELDS)
          .eq('kullanici_id', user.id)
          .order('created_at', ascending: false);

      final List<String> kayipIdList = kayip.map((e) => (e['id'] as String)).toList();
      Map<String, String?> kayipIdToFoto = {};
      if (kayipIdList.isNotEmpty) {
        kayipIdToFoto = await _ilanFotograflariniGetir(kayipIdList, 'kayip');
      }

      final List<Map<String, dynamic>> normalizedKayip = kayip.map((e) {
        final Map<String, dynamic> ilanData = e as Map<String, dynamic>;
        final String id = ilanData['id'] as String;
        return {
          ...ilanData,
          'id': id,
          'foto_url': kayipIdToFoto[id],
          'tip': 'kayip',
          'repost': false,
        };
      }).toList();

      //  BULUNAN İLANLARI YÜKLE
      final List<dynamic> bulunan = await _supabase
          .from('bulunan_ilanlar')
          .select(_BULUNAN_ILAN_FIELDS)
          .eq('kullanici_id', user.id)
          .order('created_at', ascending: false);

      final List<String> bulunanIdList = bulunan.map((e) => (e['id'] as String)).toList();
      Map<String, String?> bulunanIdToFoto = {};
      if (bulunanIdList.isNotEmpty) {
        bulunanIdToFoto = await _ilanFotograflariniGetir(bulunanIdList, 'bulunan');
      }

      final List<Map<String, dynamic>> normalizedBulunan = bulunan.map((e) {
        final Map<String, dynamic> ilanData = e as Map<String, dynamic>;
        final String id = ilanData['id'] as String;
        return {
          ...ilanData,
          'id': id,
          'hayvan_adi': '',
          'cipi_var_mi': false,
          'foto_url': bulunanIdToFoto[id],
          'tip': 'bulunan',
          'repost': false,
        };
      }).toList();

      // SAHİPLENDİRME İLANLARINI YÜKLE
      final List<dynamic> sahiplendirme = await _supabase
          .from('sahiplendirme_ilanlar')
          .select(_SAHIPLENDIRME_ILAN_FIELDS)
          .eq('kullanici_id', user.id)
          .order('created_at', ascending: false);

      final List<String> sahiplendirmeIdList = sahiplendirme.map((e) => (e['id'] as String)).toList();
      Map<String, String?> sahiplendirmeIdToFoto = {};
      if (sahiplendirmeIdList.isNotEmpty) {
        sahiplendirmeIdToFoto = await _ilanFotograflariniGetir(sahiplendirmeIdList, 'sahiplendirme');
      }

      final List<Map<String, dynamic>> normalizedSahiplendirme = sahiplendirme.map((e) {
        final Map<String, dynamic> ilanData = e as Map<String, dynamic>;
        final String id = ilanData['id'] as String;
        return {
          ...ilanData,
          'id': id,
          'foto_url': sahiplendirmeIdToFoto[id],
          'tip': 'sahiplendirme',
          'repost': false,
        };
      }).toList();

      await _loadRepostIlanlarim(user.id);

      setState(() {
        _kayipIlanlarim = normalizedKayip;
        _bulunanIlanlarim = normalizedBulunan;
        _sahiplendirmeIlanlarim = normalizedSahiplendirme;

        // --- MÜHENDİSLİK DOKUNUŞU 1: if (!refresh) engeli kaldırıldı! --- ✅
        // Artık her sildiğimizde liste mutlaka güncellenecek.
        if (_ilanFilterIndex == 0) {
          _ilanlarim = _kayipIlanlarim;
        } else if (_ilanFilterIndex == 1) {
          _ilanlarim = _bulunanIlanlarim;
        } else if (_ilanFilterIndex == 2) {
          _ilanlarim = _sahiplendirmeIlanlarim;
        } else {
          _ilanlarim = _repostIlanlarim;
        }
      });
    } catch (e) {
      if (mounted) {
        print('İlan yükleme hatası (loadIlanlarim): $e');
      }
    }
  }


  Future<void> _loadRepostIlanlarim(String userId) async {
    try {
      final List<dynamic> repostKayitlari = await _supabase
          .from('repostlar')
          .select('ilan_id, ilan_tipi, created_at')
          .eq('kullanici_id', userId)
          .order('created_at', ascending: false);

      if (repostKayitlari.isEmpty) {
        setState(() {
          _repostIlanlarim = [];
        });
        return;
      }

      final List<String> kayipIdList = [];
      final List<String> bulunanIdList = [];
      final List<String> sahiplendirmeIdList = [];

      for (final repost in repostKayitlari) {
        final String ilanTipi = repost['ilan_tipi'] as String;
        final String ilanId = repost['ilan_id'] as String;
        if (ilanTipi == 'kayip') {
          kayipIdList.add(ilanId);
        } else if (ilanTipi == 'bulunan') {
          bulunanIdList.add(ilanId);
        } else if (ilanTipi == 'sahiplendirme') {
          sahiplendirmeIdList.add(ilanId);
        }
      }

      final List<dynamic> kayipIlanlar = kayipIdList.isEmpty ? [] : await _supabase.from('kayip_ilanlar').select(_KAYIP_ILAN_FIELDS).inFilter('id', kayipIdList);
      final List<dynamic> bulunanIlanlar = bulunanIdList.isEmpty ? [] : await _supabase.from('bulunan_ilanlar').select(_BULUNAN_ILAN_FIELDS).inFilter('id', bulunanIdList);
      final List<dynamic> sahiplendirmeIlanlar = sahiplendirmeIdList.isEmpty ? [] : await _supabase.from('sahiplendirme_ilanlar').select(_SAHIPLENDIRME_ILAN_FIELDS).inFilter('id', sahiplendirmeIdList);

      final Map<String, String?> fotoMap = {};
      fotoMap.addAll(await _ilanFotograflariniGetir(kayipIdList, 'kayip'));
      fotoMap.addAll(await _ilanFotograflariniGetir(bulunanIdList, 'bulunan'));
      fotoMap.addAll(await _ilanFotograflariniGetir(sahiplendirmeIdList, 'sahiplendirme'));

      final Map<String, Map<String, dynamic>> tumIlanDetaylari = {
        for (var ilan in kayipIlanlar) ilan['id'] as String: {...ilan as Map<String, dynamic>, 'tip': 'kayip'},
        for (var ilan in bulunanIlanlar) ilan['id'] as String: {...ilan as Map<String, dynamic>, 'tip': 'bulunan'},
        for (var ilan in sahiplendirmeIlanlar) ilan['id'] as String: {...ilan as Map<String, dynamic>, 'tip': 'sahiplendirme'},
      };

      List<Map<String, dynamic>> repostIlanlar = [];

      for (final repost in repostKayitlari) {
        final String ilanId = repost['ilan_id'] as String;
        final String ilanTipi = repost['ilan_tipi'] as String;
        final Map<String, dynamic>? ilanData = tumIlanDetaylari[ilanId];

        if (ilanData != null) {
          repostIlanlar.add({
            ...ilanData,
            'id': ilanId,
            'hayvan_adi': (ilanTipi == 'kayip' || ilanTipi == 'sahiplendirme') ? ilanData['hayvan_adi'] : '',
            'cipi_var_mi': (ilanTipi == 'kayip' || ilanTipi == 'sahiplendirme') ? ilanData['cipi_var_mi'] == true : false,
            'foto_url': fotoMap[ilanId],
            'tip': ilanTipi,
            'repost': true,
          });
        }
      }

      setState(() {
        _repostIlanlarim = repostIlanlar;
      });

    } catch (e) {
      setState(() {
        _repostIlanlarim = [];
      });
    }
  }

  Future<void> _onayliIlanSil(Map<String, dynamic> ilan) async {
    final bool isRepost = ilan['repost'] == true;

    if (isRepost) {
      await _sadeceRepostSil(ilan['id'] as String, ilan['tip'] as String);
      return;
    }

    final String ilanId = ilan['id'] as String;
    final String ilanTipi = ilan['tip'] as String;

    String ilanAdi = 'İlan';
    if (ilanTipi == 'kayip' || ilanTipi == 'sahiplendirme') {
      ilanAdi = ilan['hayvan_adi'] as String? ?? 'İlan';
    } else {
      ilanAdi = 'Bulunan Hayvan';
    }

    final bool onay = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İlanı Silmeyi Onayla'),
        content: Text('$ilanAdi ilanını silmek istediğinizden emin misiniz? Bu işlem geri alınamaz ve ilan ile ilişkili tüm veriler kalıcı olarak silinecektir.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İPTAL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('EVET, SİL', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;

    if (onay) {
      await _ilanVeIliskiliVerileriSil(ilanId, ilanTipi);
    }
  }

  // --- MÜHENDİSLİK DOKUNUŞU 2: ANINDA SİLİNME (OPTIMISTIC UI) --- ✅
  Future<void> _sadeceRepostSil(String ilanId, String ilanTipi) async {
    // İnterneti bile beklemeden ekrandan şak diye uçurur
    setState(() {
      _ilanlarim.removeWhere((i) => i['id'] == ilanId);
      _repostIlanlarim.removeWhere((i) => i['id'] == ilanId);
    });

    try {
      await _supabase
          .from('repostlar')
          .delete()
          .eq('ilan_id', ilanId)
          .eq('kullanici_id', _supabase.auth.currentUser!.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Yeniden paylaştığınız ilan kaldırıldı.'),
            backgroundColor: Color(0xFFFFB74D),
          ),
        );
      }
    } catch (e) {
      _loadIlanlarim(refresh: true); // Eğer hata verirse ilanı geri getirir
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Repost kaldırılamadı: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- MÜHENDİSLİK DOKUNUŞU 3: ANINDA SİLİNME (OPTIMISTIC UI) --- ✅
  Future<void> _ilanVeIliskiliVerileriSil(String ilanId, String ilanTipi) async {
    // Silme tuşuna basıldığı an, loading spinner bile göstermeden ekrandan uçar!
    setState(() {
      _ilanlarim.removeWhere((i) => i['id'] == ilanId);
      _kayipIlanlarim.removeWhere((i) => i['id'] == ilanId);
      _bulunanIlanlarim.removeWhere((i) => i['id'] == ilanId);
      _sahiplendirmeIlanlarim.removeWhere((i) => i['id'] == ilanId);
    });

    try {
      String tabloAdi = '';
      if (ilanTipi == 'kayip') tabloAdi = 'kayip_ilanlar';
      else if (ilanTipi == 'bulunan') tabloAdi = 'bulunan_ilanlar';
      else if (ilanTipi == 'sahiplendirme') tabloAdi = 'sahiplendirme_ilanlar';

      if (ilanTipi == 'kayip') {
        await _supabase.from('kayip_ilan_asilar').delete().eq('kayip_ilan_id', ilanId);
      } else if (ilanTipi == 'sahiplendirme') {
        await _supabase.from('sahiplendirme_ilan_asilar').delete().eq('sahiplendirme_ilan_id', ilanId);
      }

      await _supabase.from('repostlar').delete().eq('ilan_id', ilanId).eq('ilan_tipi', ilanTipi);
      await _supabase.from('begeniler').delete().eq('ilan_id', ilanId).eq('ilan_tipi', ilanTipi);
      await _supabase.from('yorumlar').delete().eq('ilan_id', ilanId).eq('ilan_tipi', ilanTipi);

      final List<dynamic> fotoKayitlari = await _supabase
          .from('ilan_fotograflari')
          .select('foto_url')
          .eq('ilan_id', ilanId)
          .eq('ilan_tipi', ilanTipi);

      final List<String> silinecekYollar = [];
      const String bucketAdi = 'hayvan_fotograflari';

      for(final foto in fotoKayitlari) {
        final String url = foto['foto_url'] as String;
        final String dosyaYolu = Uri.parse(url).pathSegments.sublist(2).join('/');
        silinecekYollar.add(dosyaYolu);
      }

      if(silinecekYollar.isNotEmpty) {
        await _supabase.storage.from(bucketAdi).remove(silinecekYollar);
      }

      await _supabase.from('ilan_fotograflari').delete().eq('ilan_id', ilanId).eq('ilan_tipi', ilanTipi);

      if (ilanTipi == 'kayip') {
        await _supabase.from('eslesmeler').delete().eq('kayip_ilan_id', ilanId);
      } else if (ilanTipi == 'bulunan') {
        await _supabase.from('eslesmeler').delete().eq('bulunan_ilan_id', ilanId);
      }

      await _supabase.from(tabloAdi).delete().eq('id', ilanId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$ilanTipi ilanı başarıyla silindi.'),
            backgroundColor: const Color(0xFF558B2F),
          ),
        );
      }

    } catch (e) {
      _loadIlanlarim(refresh: true); // Eğer Supabase hatası olursa listeyi geri yükle
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İlan silinirken hata oluştu: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _ilanDuzenleFormuGoster(Map<String, dynamic> ilan) {
    if (ilan['repost'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yeniden paylaştığınız ilanlar düzenlenemez, orijinal ilanı düzenleyin.'),
          backgroundColor: Color(0xFFFFB74D),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: _IlanDuzenleForm(
              ilanData: ilan,
              onIlanGuncellendi: () {
                Navigator.pop(context);
                _loadIlanlarim(refresh: true);
              },
            ),
          ),
        );
      },
    );
  }

  void _ilanDuzenle(Map<String, dynamic> ilan) {
    _ilanDuzenleFormuGoster(ilan);
  }

  String _wrapNameByWord(String name, {int maxLineLength = 16}) {
    final words = name.split(RegExp(r'\s+'));
    final StringBuffer wrappedText = StringBuffer();
    int currentLineLength = 0;

    for (final word in words) {
      if (word.length > maxLineLength) {
        if (wrappedText.isNotEmpty) {
          wrappedText.writeln();
        }
        wrappedText.write(word);
        wrappedText.writeln();
        currentLineLength = 0;
        continue;
      }

      if (currentLineLength + word.length + (currentLineLength > 0 ? 1 : 0) > maxLineLength) {
        wrappedText.writeln();
        wrappedText.write(word);
        currentLineLength = word.length;
      } else {
        if (wrappedText.isNotEmpty && currentLineLength > 0) {
          wrappedText.write(' ');
        }
        wrappedText.write(word);
        currentLineLength += word.length + (currentLineLength > 0 ? 1 : 0);
      }
    }
    return wrappedText.toString();
  }

  Future<void> _saveProfile() async {
    if (_profile == null) return;
    setState(() {
      _isSaving = true;
    });
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Oturum bulunamadı');

      final updates = {
        'tam_ad': _adController.text.trim(),
        'telefon': _telefonController.text.trim(),
      };

      await _supabase.from('profiles').update(updates).eq('id', user.id);

      setState(() {
        _profile = {
          ...?_profile,
          ...updates,
        };
        _isEditing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profil bilgileri güncellendi'),
            backgroundColor: Color(0xFF558B2F),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kaydetme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteProfilePhoto() async {
    if (_profile == null) return;
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Oturum bulunamadı');

      final String? eskiDosyaYolu = _profile!['profil_foto'] as String?;

      if (eskiDosyaYolu != null && eskiDosyaYolu.isNotEmpty) {
        await _supabase.storage.from(_PROFIL_FOTO_KOVA_ADI).remove([eskiDosyaYolu]);
      }

      await _supabase.from('profiles').update({'profil_foto': null}).eq('id', user.id);

      setState(() {
        _profile!['profil_foto'] = null;
        _profilFotoGuvenliUrl = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profil fotoğrafı başarıyla silindi.'),
            backgroundColor: Color(0xFFFFB74D),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotoğraf silinirken hata oluştu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<File?> _profilResmiYuvarlakKirp(File resimDosyasi) async {
    CroppedFile? kirpilmisDosya = await ImageCropper().cropImage(
      sourcePath: resimDosyasi.path,
      cropStyle: CropStyle.circle,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Profil Fotoğrafını Ayarla',
          toolbarColor: const Color(0xFF558B2F),
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          activeControlsWidgetColor: const Color(0xFFFFB74D),
        ),
        IOSUiSettings(
          title: 'Profil Fotoğrafını Ayarla',
        ),
      ],
    );

    if (kirpilmisDosya != null) {
      return File(kirpilmisDosya.path);
    }
    return null;
  }

  Future<void> _pickAndUploadPhoto() async {
    if (_profile == null) return;
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Oturum bulunamadı');

      final bool mevcutFotoVar = (_profile!['profil_foto'] as String?)?.isNotEmpty == true;

      final String? secim = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt, color: Color(0xFFFFB74D)),
                  title: const Text('Kamera ile çek'),
                  onTap: () => Navigator.pop(context, 'camera'),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library, color: Color(0xFF558B2F)),
                  title: const Text('Galeriden seç'),
                  onTap: () => Navigator.pop(context, 'gallery'),
                ),
                if (mevcutFotoVar)
                  ListTile(
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: const Text('Mevcut fotoğrafı sil'),
                    onTap: () => Navigator.pop(context, 'delete'),
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.cancel, color: Colors.grey),
                  title: const Text('İptal'),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          );
        },
      );

      if (secim == null) return;

      if (secim == 'delete') {
        await _deleteProfilePhoto();
        return;
      }

      final ImageSource source = secim == 'camera' ? ImageSource.camera : ImageSource.gallery;

      final picked = await _picker.pickImage(source: source, imageQuality: 80);
      if (picked == null) return;

      final File? kirpilmisFoto = await _profilResmiYuvarlakKirp(File(picked.path));
      if (kirpilmisFoto == null) return;
      final Uint8List fileBytes = await kirpilmisFoto.readAsBytes();
      final String ext = picked.name.split('.').last;

      final String dosyaYolu = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf işleniyor ve yükleniyor...')),
        );
      }

      await _supabase.storage.from(_PROFIL_FOTO_KOVA_ADI).uploadBinary(
        dosyaYolu,
        fileBytes,
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'image/jpeg',
        ),
      );

      await _supabase.from('profiles').update({'profil_foto': dosyaYolu}).eq('id', user.id);

      final String? yeniGuvenliUrl = await _profilFotoGuvenliUrlGetir(dosyaYolu);

      setState(() {
        _profile!['profil_foto'] = dosyaYolu;
        _profilFotoGuvenliUrl = yeniGuvenliUrl;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profil fotoğrafı yenilendi!'),
            backgroundColor: Color(0xFF558B2F),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotoğraf yüklenemedi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showFollowListModal(String type) async {
    final String baslik = type == 'followers' ? 'Takipçilerim' : 'Takip Ettiklerim';
    final String fromTable = 'takipler';
    final String selectField = type == 'followers' ? 'takip_eden(id, tam_ad, profil_foto)' : 'takip_edilen(id, tam_ad, profil_foto)';
    final String eqField = type == 'followers' ? 'takip_edilen' : 'takip_eden';
    final String currentUserId = _supabase.auth.currentUser!.id;

    final List<dynamic> takipData = await _supabase
        .from(fromTable)
        .select(selectField)
        .eq(eqField, currentUserId);

    final List<Map<String, dynamic>> users = takipData
        .map((item) => item[type == 'followers' ? 'takip_eden' : 'takip_edilen'] as Map<String, dynamic>)
        .toList();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      baslik,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF558B2F),
                      ),
                    ),
                  ),
                  const Divider(height: 1, thickness: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        return _FollowListTile(
                          kullaniciId: user['id'] as String,
                          ad: user['tam_ad'] as String? ?? 'Kullanıcı',
                          fotoYolu: user['profil_foto'] as String?,
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => KullaniciProfili(kullaniciId: user['id'] as String),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _logout() async {
    try {
      await _supabase.auth.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const GirisKayitSayfasi()),
              (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Çıkış yapılamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _toggleEditMode() {
    setState(() {
      _isEditing = !_isEditing;
      if (!_isEditing) {
        _adController.text = (_profile?['tam_ad'] ?? '').toString();
        _telefonController.text = (_profile?['telefon'] ?? '').toString();
      }
    });
  }

  String _formatDate(dynamic value) {
    try {
      if (value == null) return '-';
      final dt = DateTime.tryParse(value.toString());
      if (dt == null) return '-';
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {
      return '-';
    }
  }

  // --- MÜHENDİSLİK DOKUNUŞU 4: YÖNLENDİRME METODU SİNYAL DÖNDÜRÜYOR --- ✅
  Future<String?> _ilanDetayinaYonlendir(Map<String, dynamic> ilanData) async {
    final String ilanId = ilanData['id'] as String;
    final String ilanTipi = ilanData['tip'] as String;

    try {
      String tabloAdi = '';
      String selectQuery = '';

      if (ilanTipi == 'kayip') {
        tabloAdi = 'kayip_ilanlar';
        selectQuery = 'id, kullanici_id, hayvan_adi, hayvan_turu, hayvan_rengi, ekstra_bilgi, konum, konum_text, hayvan_cinsiyeti, cipi_var_mi, created_at, profiles(tam_ad, telefon)';
      } else if (ilanTipi == 'bulunan') {
        tabloAdi = 'bulunan_ilanlar';
        selectQuery = 'id, kullanici_id, hayvan_turu, hayvan_rengi, ekstra_bilgi, konum, konum_text, hayvan_cinsiyeti, created_at, profiles(tam_ad, telefon)';
      } else if (ilanTipi == 'sahiplendirme') {
        tabloAdi = 'sahiplendirme_ilanlar';
        selectQuery = 'id, kullanici_id, hayvan_adi, hayvan_turu, hayvan_rengi, ekstra_bilgi, konum, konum_text, hayvan_cinsiyeti, cipi_var_mi, kisir_mi, kisirlastirma_sarti, aliskanliklar, created_at, profiles(tam_ad, telefon)';
      }

      final ilanDetay = await _supabase
          .from(tabloAdi)
          .select(selectQuery)
          .eq('id', ilanId)
          .maybeSingle();

      if (ilanDetay == null || ilanDetay is! Map<String, dynamic>) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('İlan detayı bulunamadı.'), backgroundColor: Colors.red),
          );
        }
        return null;
      }

      final List<dynamic> fotos = await _supabase
          .from('ilan_fotograflari')
          .select('foto_url')
          .eq('ilan_id', ilanId)
          .eq('ilan_tipi', ilanTipi)
          .order('created_at', ascending: true);

      final List<String> fotoUrlListesi = fotos.map((e) => e['foto_url'] as String).toList();
      final Map<String, dynamic> detayData = ilanDetay;

      String adresGosterimi = "Konum Belirtilmemiş";

      if (detayData['konum_text'] != null && detayData['konum_text'].toString().isNotEmpty) {
        adresGosterimi = detayData['konum_text'].toString();
      } else {
        final LatLng? koordinat = _koordinatCozumle(detayData['konum']);
        if (koordinat != null) {
          try {
            List<Placemark> placemarks = await placemarkFromCoordinates(koordinat.latitude, koordinat.longitude);
            if (placemarks.isNotEmpty) {
              Placemark place = placemarks[0];
              adresGosterimi = "${place.administrativeArea ?? '?'} / ${place.subAdministrativeArea ?? '?'}";
            } else {
              adresGosterimi = "${koordinat.latitude.toStringAsFixed(4)}, ${koordinat.longitude.toStringAsFixed(4)}";
            }
          } catch (e) {
            adresGosterimi = "Konum Hatası (Lütfen Haritada Gör)";
          }
        }
      }

      detayData['konum'] = adresGosterimi;
      final profileData = detayData['profiles'] as Map<String, dynamic>?;

      final Ilan ilanNesnesi = Ilan.fromMap(
        data: detayData,
        tip: ilanTipi,
        fotoUrls: fotoUrlListesi,
        kullaniciTel: profileData?['telefon'] ?? 'Numara Yok',
        kullaniciAd: profileData?['tam_ad'] ?? 'Anonim Kullanıcı',
        isRepost: ilanData['repost'] == true,
      );

      if (mounted) {
        final sonuc = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => IlanDetaySayfasi(ilan: ilanNesnesi)),
        );
        return sonuc as String?;
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Yükleme hatası: $e'), backgroundColor: Colors.red));
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const Color arkaPlan = Color(0xFFF1F8E9);
    const Color beyaz = Colors.white;
    const Color gri = Color(0xFF9E9E9E);
    const Color turuncuPastel = Color(0xFFFFB74D);
    const Color zeytinYesili = Color(0xFF558B2F);

    return Scaffold(
      backgroundColor: arkaPlan,

      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: turuncuPastel))
          : _error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: gri),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loadProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: turuncuPastel,
                ),
                child: const Text('Tekrar Dene', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      )
          : _profile == null
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64, color: gri),
            const SizedBox(height: 16),
            const Text('Profil verisi bulunamadı.'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loadProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: turuncuPastel,
              ),
              child: const Text('Tekrar Dene', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      )
          : Column(
        children: [
          // Profil Header
          Stack(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: zeytinYesili,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: gri.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 50),
                          child: _ProfileAvatar(
                            url: _profilFotoGuvenliUrl,
                            ad: _profile!['tam_ad'],
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: beyaz,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: turuncuPastel, width: 2),
                            ),
                            child: IconButton(
                              icon: Icon(Icons.camera_alt, size: 18, color: turuncuPastel),
                              onPressed: _pickAndUploadPhoto,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            this._wrapNameByWord(_profile!['tam_ad'] ?? 'Kullanıcı', maxLineLength: 16),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white30),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.list_alt, size: 16, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                _toplamIlanSayisi.toString(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _profile!['email'] ?? '-',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),

                    _FollowStats(
                      takipciSayisi: _takipciSayisi,
                      takipEdilenSayisi: _takipEdilenSayisi,
                      onTapTakipci: () => _showFollowListModal('followers'),
                      onTapTakipEdilen: () => _showFollowListModal('following'),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),


              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white, size: 26),
                  onPressed: _toggleEditMode,
                  tooltip: 'Profili Düzenle',
                ),
              ),
            ],
          ),


          // Tab Bar
          Container(
            color: beyaz,
            child: TabBar(
              controller: _tabController,
              labelColor: zeytinYesili,
              unselectedLabelColor: gri,
              indicatorColor: turuncuPastel,
              indicatorWeight: 3,
              tabs: const [
                Tab(text: 'Bilgilerim'),
                Tab(text: 'İlanlarım'),
              ],
            ),
          ),

          // Tab Bar Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // BİLGİLERİM
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: beyaz,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: gri.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.person_outline, color: turuncuPastel),
                                SizedBox(width: 8),
                                Text(
                                  'Profil Bilgileri',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: zeytinYesili,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _EditableField(
                              icon: Icons.person,
                              label: 'Ad Soyad',
                              controller: _adController,
                              isEditing: _isEditing,
                              keyboardType: TextInputType.name,
                            ),
                            const SizedBox(height: 12),
                            _InfoField(
                              icon: Icons.email,
                              label: 'E-posta',
                              value: _profile!['email'] ?? '-',
                            ),
                            const SizedBox(height: 12),
                            _EditableField(
                              icon: Icons.phone,
                              label: 'Telefon',
                              controller: _telefonController,
                              isEditing: _isEditing,
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 12),
                            _InfoField(
                              icon: Icons.calendar_today,
                              label: 'Kayıt Tarihi',
                              value: this._formatDate(_profile!['created_at']),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (_isEditing) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: zeytinYesili,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'Değişiklikleri Kaydet',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton(
                            onPressed: _toggleEditMode,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: gri.withOpacity(0.5)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'İptal',
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton(
                            onPressed: _logout,
                            style: ElevatedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.logout, color: Colors.red),
                                SizedBox(width: 8),
                                Text(
                                  'Çıkış Yap',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ilanlarım kısmı
                Column(
                  children: [
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: _FilterChips(
                        selectedIndex: _ilanFilterIndex,
                        onChanged: (idx) {
                          setState(() {
                            _ilanFilterIndex = idx;
                            if (idx == 0) {
                              _ilanlarim = _kayipIlanlarim;
                            } else if (idx == 1) {
                              _ilanlarim = _bulunanIlanlarim;
                            } else if (idx == 2) {
                              _ilanlarim = _sahiplendirmeIlanlarim;
                            } else {
                              _ilanlarim = _repostIlanlarim;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _ilanlarim.isEmpty
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.list_alt, size: 64, color: gri),
                            const SizedBox(height: 16),
                            Text(
                              _ilanFilterIndex == 0 ? 'Henüz kayıp ilanınız bulunmuyor' :
                              _ilanFilterIndex == 1 ? 'Henüz bulunan ilanınız bulunmuyor' :
                              _ilanFilterIndex == 2 ? 'Henüz sahiplendirme ilanınız bulunmuyor' :
                              'Henüz yeniden paylaştığınız ilan bulunmuyor',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                          : RefreshIndicator(
                        onRefresh: () => _loadIlanlarim(refresh: true),
                        color: turuncuPastel,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _ilanlarim.length,
                          itemBuilder: (context, index) {
                            final ilan = _ilanlarim[index];
                            final bool isRepost = ilan['repost'] == true;
                            final String ilanTipi = ilan['tip'] as String;

                            final String baslik = (ilan['hayvan_adi'] as String?)?.isNotEmpty == true
                                ? ilan['hayvan_adi']
                                : (ilanTipi == 'kayip' ? 'Kayıp Hayvan' : (ilanTipi == 'sahiplendirme' ? 'Sahiplendirme' : 'Bulunan Hayvan'));

                            final String altSatir = (ilan['hayvan_turu'] ?? '').toString();

                            final String? fotoUrl = ilan['foto_url'] as String?;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: beyaz,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: gri.withOpacity(0.1),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ListTile(
                                leading: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: 50,
                                        height: 50,
                                        child: fotoUrl != null && fotoUrl.trim().isNotEmpty
                                            ? Image.network(fotoUrl, fit: BoxFit.cover, errorBuilder: (c,e,s) => Icon(Icons.error_outline, color: Colors.red.shade300))
                                            : Container(
                                          color: turuncuPastel.withOpacity(0.2),
                                          child: Icon(Icons.pets, color: turuncuPastel),
                                        ),
                                      ),
                                    ),
                                    if (isRepost)
                                      Positioned(
                                        top: 0,
                                        right: 0,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: zeytinYesili,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(Icons.repeat, size: 12, color: beyaz),
                                        ),
                                      ),
                                  ],
                                ),
                                title: Text(
                                  _wrapNameByWord(baslik.isNotEmpty ? baslik : 'İlan', maxLineLength: 25),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: altSatir.isNotEmpty
                                    ? Text(altSatir, style: TextStyle(color: gri))
                                    : Text(ilanTipi == 'kayıp' ? 'Kayıp İlanı' : (ilanTipi == 'sahiplendirme' ? 'Sahiplendirme İlanı' : 'Bulunan İlanı'), style: TextStyle(color: gri)),

                                trailing: PopupMenuButton<String>(
                                  onSelected: (String result) {
                                    if (result == 'sil') {
                                      _onayliIlanSil(ilan);
                                    } else if (result == 'duzenle') {
                                      _ilanDuzenle(ilan);
                                    }
                                  },
                                  itemBuilder: (BuildContext context) {
                                    if (isRepost) {
                                      return [
                                        const PopupMenuItem<String>(
                                          value: 'sil',
                                          child: Row(
                                            children: [
                                              Icon(Icons.repeat_one_on, color: Colors.red),
                                              SizedBox(width: 8),
                                              Text('Repostu Kaldır'),
                                            ],
                                          ),
                                        ),
                                      ];
                                    } else {
                                      return [
                                        const PopupMenuItem<String>(
                                          value: 'duzenle',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit, color: Color(0xFF558B2F)),
                                              SizedBox(width: 8),
                                              Text('Düzenle'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem<String>(
                                          value: 'sil',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete, color: Colors.red),
                                              SizedBox(width: 8),
                                              Text('Sil (Kalıcı)'),
                                            ],
                                          ),
                                        ),
                                      ];
                                    }
                                  },
                                  icon: Icon(Icons.more_vert, color: gri),
                                ),

                                // --- MÜHENDİSLİK DOKUNUŞU 5: İLAN SİLİNDİ / DÜZENLENDİ SİNYALİNİ YAKALAMA --- ✅
                                onTap: () async {
                                  final sonuc = await _ilanDetayinaYonlendir(ilan);

                                  if (sonuc == 'silindi') {
                                    setState(() {
                                      _kayipIlanlarim.removeWhere((i) => i['id'] == ilan['id']);
                                      _bulunanIlanlarim.removeWhere((i) => i['id'] == ilan['id']);
                                      _sahiplendirmeIlanlarim.removeWhere((i) => i['id'] == ilan['id']);
                                      _repostIlanlarim.removeWhere((i) => i['id'] == ilan['id']);
                                      _ilanlarim.removeWhere((i) => i['id'] == ilan['id']);
                                    });
                                  } else if (sonuc == 'duzenlendi') {
                                    _loadIlanlarim(refresh: true);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const SharedBottomNavBar(
        currentIndex: 4,
        turuncuPastel: turuncuPastel,
        gri: gri,
        beyaz: beyaz,
      ),
    );
  }
}

class _FollowStats extends StatelessWidget {
  final int takipciSayisi;
  final int takipEdilenSayisi;
  final VoidCallback onTapTakipci;
  final VoidCallback onTapTakipEdilen;

  const _FollowStats({
    required this.takipciSayisi,
    required this.takipEdilenSayisi,
    required this.onTapTakipci,
    required this.onTapTakipEdilen,
  });

  @override
  Widget build(BuildContext context) {
    const Color beyaz = Colors.white;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        GestureDetector(
          onTap: onTapTakipci,
          child: _StatItem(
            count: takipciSayisi,
            label: 'Takipçi',
            countColor: beyaz,
            labelColor: Colors.white70,
          ),
        ),
        Container(
          height: 30,
          width: 1,
          color: Colors.white54,
        ),
        GestureDetector(
          onTap: onTapTakipEdilen,
          child: _StatItem(
            count: takipEdilenSayisi,
            label: 'Takip Edilen',
            countColor: beyaz,
            labelColor: Colors.white70,
          ),
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final int count;
  final String label;
  final Color countColor;
  final Color labelColor;

  const _StatItem({
    required this.count,
    required this.label,
    required this.countColor,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            color: countColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _FollowListTile extends StatefulWidget {
  final String kullaniciId;
  final String ad;
  final String? fotoYolu;
  final VoidCallback onTap;

  const _FollowListTile({
    required this.kullaniciId,
    required this.ad,
    required this.fotoYolu,
    required this.onTap,
  });

  @override
  State<_FollowListTile> createState() => _FollowListTileState();
}

class _FollowListTileState extends State<_FollowListTile> {
  String? _guvenliFotoUrl;

  @override
  void initState() {
    super.initState();
    _loadFotoUrl();
  }

  Future<void> _loadFotoUrl() async {
    if (widget.fotoYolu != null && widget.fotoYolu!.isNotEmpty) {
      final url = await _profilFotoGuvenliUrlGetir(widget.fotoYolu);
      if (mounted) {
        setState(() {
          _guvenliFotoUrl = url;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color zeytinYesili = Color(0xFF558B2F);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: zeytinYesili.withOpacity(0.2),
        backgroundImage: _guvenliFotoUrl != null
            ? NetworkImage(_guvenliFotoUrl!) as ImageProvider
            : null,
        child: _guvenliFotoUrl == null
            ? Text(_initialsFromName(widget.ad), style: const TextStyle(color: zeytinYesili))
            : null,
      ),
      title: Text(
        widget.ad,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF9E9E9E)),
      onTap: widget.onTap,
    );
  }

  String _initialsFromName(String? name) {
    if (name == null || name.trim().isEmpty) return 'K';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

class _FilterChips extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _FilterChips({required this.selectedIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const Color zeytinYesili = Color(0xFF558B2F);
    const Color turuncuPastel = Color(0xFFFFB74D);
    const Color gri = Color(0xFF9E9E9E);

    final items = const [
      {'label': 'Kayıp', 'icon': Icons.pets},
      {'label': 'Bulunan', 'icon': Icons.search},
      {'label': 'Sahiplendir', 'icon': Icons.volunteer_activism},
      {'label': 'Yeniden', 'icon': Icons.repeat},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(items.length, (i) {
          final selected = i == selectedIndex;
          return GestureDetector(
            onTap: () => onChanged(i),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              margin: EdgeInsets.only(left: i == 0 ? 0 : 6, right: i == items.length - 1 ? 0 : 0),
              decoration: BoxDecoration(
                color: selected ? turuncuPastel : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? turuncuPastel : gri.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(items[i]['icon'] as IconData, size: 16, color: selected ? Colors.white : zeytinYesili),
                  const SizedBox(width: 4),
                  Text(
                    items[i]['label'] as String,
                    style: TextStyle(
                      color: selected ? Colors.white : zeytinYesili,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String? url;
  final String? ad;

  const _ProfileAvatar({required this.url, required this.ad});

  @override
  Widget build(BuildContext context) {
    final initials = _initialsFromName(ad);
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: CircleAvatar(
        radius: 46,
        backgroundColor: Colors.white.withOpacity(0.2),
        backgroundImage: (url != null && url!.trim().isNotEmpty) ? NetworkImage(url!) : null,
        child: (url == null || url!.trim().isEmpty)
            ? Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        )
            : null,
      ),
    );
  }

  String _initialsFromName(String? name) {
    if (name == null || name.trim().isEmpty) return 'KB';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

class _EditableField extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextEditingController controller;
  final bool isEditing;
  final TextInputType keyboardType;

  const _EditableField({
    required this.icon,
    required this.label,
    required this.controller,
    required this.isEditing,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    const Color gri = Color(0xFF9E9E9E);
    const Color turuncuPastel = Color(0xFFFFB74D);

    return Row(
      children: [
        Icon(icon, color: turuncuPastel, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: isEditing
              ? TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: gri),
              border: const UnderlineInputBorder(),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: turuncuPastel),
              ),
            ),
            style: const TextStyle(fontSize: 14),
          )
              : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: gri,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                controller.text.isNotEmpty ? controller.text : '-',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoField({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    const Color gri = Color(0xFF9E9E9E);
    const Color turuncuPastel = Color(0xFFFFB74D);

    return Row(
      children: [
        Icon(icon, color: turuncuPastel, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: gri,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// İLAN DÜZENLEME FORMU
class _IlanDuzenleForm extends StatefulWidget {
  final Map<String, dynamic> ilanData;
  final VoidCallback onIlanGuncellendi;

  const _IlanDuzenleForm({
    required this.ilanData,
    required this.onIlanGuncellendi,
  });

  @override
  State<_IlanDuzenleForm> createState() => _IlanDuzenleFormState();
}

class _IlanDuzenleFormState extends State<_IlanDuzenleForm> {
  final _formKey = GlobalKey<FormState>();
  final SupabaseClient _supabase = supabase;

  bool _yukleniyor = false;
  bool _fotografIsleniyor = false;

  final ImagePicker _picker = ImagePicker();

  late TextEditingController _hayvanAdController;
  late TextEditingController _ekstraBilgiController;
  late TextEditingController _konumController;
  late TextEditingController _digerHayvanController;
  late TextEditingController _aliskanlikController;

  LatLng? _guncelKoordinat;

  String? _secilenHayvanTuru;
  String? _secilenHayvanRengi;
  String _cinsiyet = 'Disi';
  bool _cipli = false;
  bool _kisirMi = false;
  bool _kisirlastirmaSarti = false;

  final Color turuncuPastel = const Color(0xFFFFB74D);
  final Color zeytinYesili = const Color(0xFF558B2F);
  final Color arkaPlan = const Color(0xFFF1F8E9);
  final Color gri = const Color(0xFF9E9E9E);
  final Color beyaz = Colors.white;

  List<Map<String, dynamic>> _tumAsiSecenekleri = [];
  List<String> _secilenAsiIdleri = [];
  bool _asilariYukleniyor = true;

  List<String> _mevcutFotograflar = [];
  List<XFile> _eklenecekYeniFotograflar = [];

  bool get _isKayip => widget.ilanData['tip'] == 'kayip';
  bool get _isSahiplendirme => widget.ilanData['tip'] == 'sahiplendirme';
  bool get _asiGereklidir => _secilenHayvanTuru == 'Kedi' || _secilenHayvanTuru == 'Köpek';

  final List<String> hayvanTurleri = const ['Kedi', 'Köpek', 'Kuş', 'Hamster', 'Diğer'];
  final Map<String, List<String>> renkSecenekleri = const {
    'Kedi': ['Sarman', 'Tekir', 'Smokin', 'Siyah', 'Beyaz', 'Gri', 'Kahverengi', 'Calico'],
    'Köpek': ['Sarı', 'Siyah', 'Beyaz', 'Gri', 'Kahverengi', 'Dalmaçyalı', 'Çok renkli'],
    'Kuş': ['Sarı', 'Yeşil', 'Mavi', 'Beyaz', 'Gri', 'Kırmızı', 'Mor', 'Çok renkli'],
    'Hamster': ['Sarı', 'Kahverengi', 'Beyaz', 'Gri', 'Siyah', 'Çok renkli'],
    'Diğer': ['Siyah', 'Beyaz', 'Gri', 'Kahverengi', 'Krem', 'Sarı', 'Turuncu', 'Kızıl', 'Altın', 'Mavi', 'Yeşil', 'Çok renkli'],
  };
  List<String> _mevcutRenkSecenekleri = [];


  @override
  void initState() {
    super.initState();
    _digerHayvanController = TextEditingController();
    _hayvanAdController = TextEditingController(text: widget.ilanData['hayvan_adi'] ?? '');
    _ekstraBilgiController = TextEditingController(text: widget.ilanData['ekstra_bilgi'] ?? '');
    _aliskanlikController = TextEditingController(text: widget.ilanData['aliskanliklar'] ?? '');

    _konumController = TextEditingController();

    _formuDoldur(widget.ilanData);
    _mevcutFotograflariCek();

    if (_isKayip || _isSahiplendirme) {
      _asilariVeMevcutSecimleriYukle();
    } else {
      _asilariYukleniyor = false;
    }

    _konumVerisiniIsle();
  }

  void _konumVerisiniIsle() {
    _guncelKoordinat = _koordinatCozumle(widget.ilanData['konum']);
    if (_guncelKoordinat != null) {
      _konumController.text = "Mevcut Konum Çözümleniyor...";
      _koordinatlariAdreseCevir(_guncelKoordinat!);
    } else {
      _konumController.text = "Konumu değiştirmek için tıklayınız";
    }
  }

  Future<void> _koordinatlariAdreseCevir(LatLng koordinat) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
          koordinat.latitude,
          koordinat.longitude
      );

      String adresGosterimi;
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        adresGosterimi = "Mevcut Konum: ${place.administrativeArea ?? '?'} / ${place.subAdministrativeArea ?? '?'}";
      } else {
        adresGosterimi = "Mevcut Koordinat: ${koordinat.latitude.toStringAsFixed(4)}, ${koordinat.longitude.toStringAsFixed(4)} (Adres bulunamadı)";
      }

      if (mounted) {
        setState(() {
          _konumController.text = adresGosterimi;
        });
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _konumController.text = "Hata: Adres çözümlenemedi. Koordinat: ${koordinat.latitude.toStringAsFixed(4)}, ${koordinat.longitude.toStringAsFixed(4)}";
        });
      }
      print("İlan Düzenle Formu Adres Çözümleme Hatası: $e");
    }
  }

  Future<void> _haritadanKonumGuncelle() async {
    final LatLng? yeniKonum = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => KonumSecSayfasi(
          baslangicKonumu: _guncelKoordinat,
        ),
      ),
    );

    if (yeniKonum != null) {
      setState(() {
        _guncelKoordinat = yeniKonum;
        _konumController.text = "Yeni Konum Seçildi ✅\n(${yeniKonum.latitude.toStringAsFixed(5)}, ${yeniKonum.longitude.toStringAsFixed(5)})";
      });
    }
  }

  Future<File?> _downloadFile(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/${DateTime.now().millisecondsSinceEpoch}_temp.jpg';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }
    } catch (e) {
      debugPrint("Fotoğraf indirme hatası: $e");
    }
    return null;
  }

  Future<XFile?> _resmiKirp(XFile dosya) async {
    CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: dosya.path,
      aspectRatioPresets: [
        CropAspectRatioPreset.square,
        CropAspectRatioPreset.ratio3x2,
        CropAspectRatioPreset.original,
        CropAspectRatioPreset.ratio4x3,
        CropAspectRatioPreset.ratio16x9
      ],
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Fotoğrafı Düzenle',
          toolbarColor: zeytinYesili,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          activeControlsWidgetColor: turuncuPastel,
        ),
        IOSUiSettings(
          title: 'Fotoğrafı Düzenle',
        ),
      ],
    );

    if (croppedFile != null) {
      return XFile(croppedFile.path);
    }
    return null;
  }

  Future<void> _mevcutFotografiKirp(String url, int index) async {
    setState(() => _fotografIsleniyor = true);

    File? tempFile = await _downloadFile(url);

    if (tempFile != null && mounted) {
      XFile? croppedFile = await _resmiKirp(XFile(tempFile.path));

      if (croppedFile != null && mounted) {
        await _mevcutFotografiSil(url, index);

        setState(() {
          _eklenecekYeniFotograflar.add(croppedFile);
        });

        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text('Fotoğraf kırpıldı. Kaydetmeyi unutmayın!'), backgroundColor: zeytinYesili)
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf indirilemedi.'), backgroundColor: Colors.red)
      );
    }

    if(mounted) setState(() => _fotografIsleniyor = false);
  }

  Future<void> _mevcutFotograflariCek() async {
    try {
      final List<dynamic> fotos = await _supabase
          .from('ilan_fotograflari')
          .select('foto_url')
          .eq('ilan_id', widget.ilanData['id'])
          .eq('ilan_tipi', widget.ilanData['tip'])
          .order('created_at', ascending: true);

      setState(() {
        _mevcutFotograflar = fotos.map((e) => e['foto_url'] as String).toList();
      });
    } catch (e) {
      print('Mevcut fotoğraflar çekilemedi: $e');
    }
  }

  Future<void> _asilariVeMevcutSecimleriYukle() async {
    try {
      final List<dynamic>? tumVeriler = await _supabase
          .from('asilistesi')
          .select('id, asi_adi, hayvan_turu');

      String tabloAdi = _isSahiplendirme ? 'sahiplendirme_ilan_asilar' : 'kayip_ilan_asilar';
      String kolonAdi = _isSahiplendirme ? 'sahiplendirme_ilan_id' : 'kayip_ilan_id';

      final List<dynamic>? mevcutVeriler = await _supabase
          .from(tabloAdi)
          .select('asi_id')
          .eq(kolonAdi, widget.ilanData['id']);

      final List<String> mevcutAsiIdleri =
          mevcutVeriler?.map((e) => e['asi_id'] as String).toList() ?? [];

      if (mounted) {
        setState(() {
          _tumAsiSecenekleri = tumVeriler?.cast<Map<String, dynamic>>() ?? [];
          _secilenAsiIdleri = mevcutAsiIdleri;
          _asilariYukleniyor = false;
        });
      }
    } catch (e) {
      print('Aşı ve mevcut seçimler yüklenirken hata: $e');
      if (mounted) {
        setState(() { _asilariYukleniyor = false; });
      }
    }
  }


  @override
  void dispose() {
    _hayvanAdController.dispose();
    _ekstraBilgiController.dispose();
    _konumController.dispose();
    _digerHayvanController.dispose();
    _aliskanlikController.dispose();
    super.dispose();
  }


  void _formuDoldur(Map<String, dynamic> ilan) {
    if (_isKayip || _isSahiplendirme) {
      _cinsiyet = ilan['hayvan_cinsiyeti'] ?? 'Disi';
      _cipli = ilan['cipi_var_mi'] ?? false;
    }

    if (_isSahiplendirme) {
      _kisirMi = ilan['kisir_mi'] ?? false;
      _kisirlastirmaSarti = ilan['kisirlastirma_sarti'] ?? false;
    }

    String? tur = ilan['hayvan_turu'];

    if (tur != null && hayvanTurleri.contains(tur)) {
      _secilenHayvanTuru = tur;
      _mevcutRenkSecenekleri = List.of(renkSecenekleri[tur] ?? []);
    } else if (tur != null) {
      _secilenHayvanTuru = 'Diğer';
      _digerHayvanController.text = tur;
      _mevcutRenkSecenekleri = List.of(renkSecenekleri['Diğer']!);
    } else {
      _secilenHayvanTuru = null;
      _mevcutRenkSecenekleri = List.of(renkSecenekleri['Diğer']!);
    }

    String? renk = ilan['hayvan_rengi'];
    if (renk != null && _mevcutRenkSecenekleri.contains(renk)) {
      _secilenHayvanRengi = renk;
    } else if (renk != null) {
      _mevcutRenkSecenekleri.add(renk);
      _secilenHayvanRengi = renk;
    }
  }

  void _hayvanTuruDegisti(String? yeniTur) {
    setState(() {
      _secilenHayvanTuru = yeniTur;
      _digerHayvanController.clear();
      _secilenHayvanRengi = null;
      _secilenAsiIdleri.clear();

      if (yeniTur != null && renkSecenekleri.containsKey(yeniTur)) {
        _mevcutRenkSecenekleri = List.of(renkSecenekleri[yeniTur]!);
      } else {
        _mevcutRenkSecenekleri = List.of(renkSecenekleri['Diğer']!);
      }

      if (_isKayip || _isSahiplendirme) {
        _asilariYukleniyor = true;
        _asilariVeMevcutSecimleriYukle();
      }
    });
  }


  Future<void> _fotoCekVeyaSec() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: beyaz,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF007bff)),
                title: const Text('Kamera ile çek'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFF007bff)),
                title: const Text('Galeriden seç (Çoklu)'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    if (source == ImageSource.gallery) {
      final List<XFile>? fotolar = await _picker.pickMultiImage(imageQuality: 85);
      if (fotolar != null) {
        for (var foto in fotolar) {
          XFile? kirpilmisFoto = await _resmiKirp(foto);
          if (kirpilmisFoto != null) {
            setState(() => _eklenecekYeniFotograflar.add(kirpilmisFoto));
          }
        }
      }
    } else {
      final XFile? foto = await _picker.pickImage(source: source, imageQuality: 85);
      if (foto != null) {
        XFile? kirpilmisFoto = await _resmiKirp(foto);
        if (kirpilmisFoto != null) {
          setState(() => _eklenecekYeniFotograflar.add(kirpilmisFoto));
        }
      }
    }
  }

  Future<void> _mevcutFotografiSil(String url, int index) async {
    if (_yukleniyor || _fotografIsleniyor) return;

    setState(() => _yukleniyor = true);

    try {
      const String bucketAdi = 'hayvan_fotograflari';
      final Uri uri = Uri.parse(url);
      final String dosyaYolu = uri.pathSegments.sublist(2).join('/');

      await _supabase.storage.from(bucketAdi).remove([dosyaYolu]);
      await _supabase.from('ilan_fotograflari').delete().eq('foto_url', url);

      if (mounted) {
        setState(() {
          _mevcutFotograflar.removeAt(index);
          _yukleniyor = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _yukleniyor = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Silme hatası: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _yeniFotografiSil(int index) {
    setState(() {
      _eklenecekYeniFotograflar.removeAt(index);
    });
  }

  Future<void> _yeniFotograflariYukle(String ilanId, String ilanTipi) async {
    for (int i = 0; i < _eklenecekYeniFotograflar.length; i++) {
      final XFile foto = _eklenecekYeniFotograflar[i];

      try {
        final bytes = await File(foto.path).readAsBytes();
        final String ext = foto.name.split('.').last.toLowerCase().replaceAll('jpg', 'jpeg');

        const String bucketAdi = 'hayvan_fotograflari';

        String tipPath = 'diger';
        if (ilanTipi == 'kayip') tipPath = 'kayip';
        else if (ilanTipi == 'bulunan') tipPath = 'bulunan';
        else if (ilanTipi == 'sahiplendirme') tipPath = 'sahiplendirme';

        final String dosyaYolu = '$tipPath/$ilanId/yenieklenen_${DateTime.now().millisecondsSinceEpoch}_$i.$ext';

        await _supabase.storage.from(bucketAdi).uploadBinary(
          dosyaYolu,
          bytes,
          fileOptions: const FileOptions(upsert: false, contentType: 'image/jpeg'),
        );

        final String publicUrl = _supabase.storage.from(bucketAdi).getPublicUrl(dosyaYolu);

        await _supabase.from('ilan_fotograflari').insert({
          'ilan_id': ilanId,
          'ilan_tipi': ilanTipi,
          'foto_url': publicUrl,
        });

        setState(() => _mevcutFotograflar.add(publicUrl));

      } catch (e) {
        print('Yeni fotoğraf yüklenemedi: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Fotoğraf $i yüklenirken hata oluştu.'), backgroundColor: Colors.red));
        }
      }
    }
    setState(() => _eklenecekYeniFotograflar.clear());
  }


  Future<void> _ilanGuncelle() async {
    if (!_formKey.currentState!.validate() || _yukleniyor || _fotografIsleniyor) return;

    final String ilanId = widget.ilanData['id'];
    final String ilanTipi = widget.ilanData['tip'];

    if (_mevcutFotograflar.isEmpty && _eklenecekYeniFotograflar.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('İlanda en az bir fotoğraf olmalıdır!'), backgroundColor: Colors.red));
      return;
    }

    setState(() { _yukleniyor = true; });

    try {
      final String? finalHayvanTuru = (_secilenHayvanTuru == 'Diğer' && _digerHayvanController.text.trim().isNotEmpty)
          ? _digerHayvanController.text.trim()
          : _secilenHayvanTuru;

      final Map<String, dynamic> params = {
        'p_ilan_id': ilanId,
        'p_hayvan_turu': finalHayvanTuru,
        'p_hayvan_rengi': _secilenHayvanRengi,
        'p_aciklama': _ekstraBilgiController.text.trim().isNotEmpty ? _ekstraBilgiController.text.trim() : null,
        'p_lat': _guncelKoordinat?.latitude,
        'p_lng': _guncelKoordinat?.longitude,
      };

      if (_isKayip) {
        params['p_hayvan_adi'] = _hayvanAdController.text.trim().isNotEmpty ? _hayvanAdController.text.trim() : null;
        params['p_hayvan_cinsiyeti'] = _cinsiyet;
        params['p_cipi_var_mi'] = _cipli;
        await _supabase.rpc('kayip_ilan_guncelle', params: params);

      } else if (_isSahiplendirme) {
        await _supabase.from('sahiplendirme_ilanlar').update({
          'hayvan_adi': _hayvanAdController.text.trim().isNotEmpty ? _hayvanAdController.text.trim() : "İsimsiz",
          'hayvan_turu': finalHayvanTuru,
          'hayvan_rengi': _secilenHayvanRengi,
          'ekstra_bilgi': _ekstraBilgiController.text.trim(),
          'hayvan_cinsiyeti': _cinsiyet,
          'cipi_var_mi': _cipli,
          'kisir_mi': _kisirMi,
          'kisirlastirma_sarti': _kisirlastirmaSarti,
          'aliskanliklar': _aliskanlikController.text.trim(),
          if (_guncelKoordinat != null)
            'konum': 'POINT(${_guncelKoordinat!.longitude} ${_guncelKoordinat!.latitude})',
        }).eq('id', ilanId);

      } else {
        await _supabase.rpc('bulunan_ilan_guncelle', params: params);
      }

      if ((_isKayip || _isSahiplendirme) && _asiGereklidir) {
        await ilanAsilariniGuncelle(ilanId, _secilenAsiIdleri, isSahiplendirme: _isSahiplendirme);
      }

      if (_eklenecekYeniFotograflar.isNotEmpty) {
        await _yeniFotograflariYukle(ilanId, ilanTipi);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İlanınız başarıyla güncellendi!'),
            backgroundColor: Color(0xFF558B2F),
          ),
        );
      }

      widget.onIlanGuncellendi();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İlan güncellenemedi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _yukleniyor = false; });
      }
    }
  }


  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData icon = Icons.edit,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: gri),
          prefixIcon: Icon(icon, color: turuncuPastel),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: arkaPlan,
        ),
        validator: required ? (v) => v!.trim().isEmpty ? '$label alanı zorunludur.' : null : null,
      ),
    );
  }

  Widget _buildLocationField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        controller: _konumController,
        readOnly: true,
        onTap: _haritadanKonumGuncelle,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: 'Konumu Düzenle (Haritadan Seç)',
          labelStyle: TextStyle(color: gri),
          prefixIcon: const Icon(Icons.map, color: Color(0xFFFFB74D)),
          suffixIcon: const Icon(Icons.chevron_right),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: arkaPlan,
        ),
      ),
    );
  }


  Widget _buildDropdown({
    required String? value,
    required String label,
    required List<String> items,
    required Function(String?) onChanged,
    bool required = false,
  }) {

    List<String> uniqueItems = items.toSet().toList();

    if (value != null && !uniqueItems.contains(value)) {
      uniqueItems.add(value);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(Icons.category, color: turuncuPastel),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: arkaPlan,
        ),
        isExpanded: true,
        items: uniqueItems.map((e) => DropdownMenuItem(
          value: e,
          child: Text(e, overflow: TextOverflow.ellipsis),
        )).toList(),
        onChanged: onChanged,
        validator: required ? (v) => v == null || v.isEmpty ? '$label alanı zorunludur.' : null : null,
      ),
    );
  }

  Widget _buildAsiDuzenlemeAlani() {
    if (!_isKayip && !_isSahiplendirme) return const SizedBox.shrink();

    if (!_asiGereklidir) {
      final String tur = _secilenHayvanTuru ?? widget.ilanData['hayvan_turu'] ?? 'Hayvan';
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: arkaPlan,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: gri.withOpacity(0.3)),
          ),
          child: Text(
            '$tur için aşı bilgisi düzenlemesi gerekmemektedir.',
            style: TextStyle(color: gri),
          ),
        ),
      );
    }

    if (_asilariYukleniyor) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: Center(child: CircularProgressIndicator(color: zeytinYesili)),
      );
    }

    final List<Map<String, dynamic>> ilgiliAsilar = _tumAsiSecenekleri
        .where((asi) {
      final String? asiTuru = asi['hayvan_turu'] as String?;
      return asiTuru == _secilenHayvanTuru;
    })
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Aşı Bilgilerini Düzenle',
            style: TextStyle(fontWeight: FontWeight.bold, color: zeytinYesili),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: arkaPlan,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: gri.withOpacity(0.3)),
          ),
          child: Column(
            children: ilgiliAsilar.map((asi) {
              final String asiAdi = asi['asi_adi'] as String;
              final String asiId = asi['id'] as String;
              final bool seciliMi = _secilenAsiIdleri.contains(asiId);

              return CheckboxListTile(
                title: Text(asiAdi, style: TextStyle(color: zeytinYesili)),
                value: seciliMi,
                onChanged: (bool? yeniDeger) {
                  setState(() {
                    if (yeniDeger == true) {
                      _secilenAsiIdleri.add(asiId);
                    } else {
                      _secilenAsiIdleri.remove(asiId);
                    }
                  });
                },
                activeColor: turuncuPastel,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildFotoDuzenlemeAlani() {
    final int toplamFoto = _mevcutFotograflar.length + _eklenecekYeniFotograflar.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Fotoğrafları Düzenle (${toplamFoto} Adet)',
            style: TextStyle(fontWeight: FontWeight.bold, color: zeytinYesili),
          ),
        ),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _mevcutFotograflar.length + _eklenecekYeniFotograflar.length + 1,
            itemBuilder: (context, index) {

              //  FOTO EKLE BUTONU
              if (index == _mevcutFotograflar.length + _eklenecekYeniFotograflar.length) {
                return GestureDetector(
                  onTap: _fotoCekVeyaSec,
                  child: Container(
                    width: 100,
                    height: 100,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: arkaPlan,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: turuncuPastel),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo, color: turuncuPastel),
                        const SizedBox(height: 4),
                        Text('Ekle', style: TextStyle(color: turuncuPastel, fontSize: 12)),
                      ],
                    ),
                  ),
                );
              }

              // MEVCUT (SUNUCUDAKİ) FOTOĞRAFLAR
              if (index < _mevcutFotograflar.length) {
                final url = _mevcutFotograflar[index];
                return Stack(
                  children: [
                    GestureDetector(
                      onTap: (_yukleniyor || _fotografIsleniyor) ? null : () => _mevcutFotografiKirp(url, index),
                      child: Container(
                        width: 100,
                        height: 100,
                        margin: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(url, fit: BoxFit.cover, loadingBuilder: (c,w,p) => p == null ? w : Center(child: CircularProgressIndicator(color: turuncuPastel, strokeWidth: 2))),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4, right: 12,
                      child: GestureDetector(
                        onTap: (_yukleniyor || _fotografIsleniyor) ? null : () => _mevcutFotografiSil(url, index),
                        child: CircleAvatar(
                          radius: 12, backgroundColor: Colors.red,
                          child: Icon(Icons.close, size: 16, color: beyaz),
                        ),
                      ),
                    ),
                    // Düzenle İkonu
                    Positioned(
                      bottom: 4, right: 12,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                        child: const Icon(Icons.crop, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                );
              }

              // YENİ EKLENEN (YEREL) FOTOĞRAFLAR
              final yeniIndex = index - _mevcutFotograflar.length;
              final XFile file = _eklenecekYeniFotograflar[yeniIndex];
              return Stack(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    margin: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(file.path), fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    top: 4, right: 12,
                    child: GestureDetector(
                      onTap: () => _yeniFotografiSil(yeniIndex),
                      child: CircleAvatar(
                        radius: 12, backgroundColor: Colors.orange,
                        child: Icon(Icons.close, size: 16, color: beyaz),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    // Başlık belirleme
    String baslik = 'İlanı Düzenle';
    if (_isKayip) baslik = 'Kayıp İlanı Düzenle';
    else if (_isSahiplendirme) baslik = 'Sahiplendirme İlanı Düzenle';
    else baslik = 'Bulunan İlanı Düzenle';

    return Container(
      decoration: BoxDecoration(
        color: beyaz,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.all(20),
      child: Stack(
        children: [
          Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  baslik,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: zeytinYesili),
                ),
                const Divider(),
                const SizedBox(height: 10),

                _buildFotoDuzenlemeAlani(),

                if (_isKayip || _isSahiplendirme)
                  _buildTextField(
                    controller: _hayvanAdController,
                    label: 'Hayvan Adı',
                    icon: Icons.pets,
                    required: true,
                  ),

                _buildDropdown(
                  value: _secilenHayvanTuru,
                  label: 'Hayvan Türü',
                  items: hayvanTurleri,
                  onChanged: _hayvanTuruDegisti,
                  required: true,
                ),

                if (_secilenHayvanTuru == 'Diğer')
                  _buildTextField(
                    controller: _digerHayvanController,
                    label: 'Lütfen hayvan türünü belirtin',
                    icon: Icons.edit,
                    required: true,
                  ),

                _buildDropdown(
                  value: _secilenHayvanRengi,
                  label: 'Hayvan Rengi',
                  items: _mevcutRenkSecenekleri,
                  onChanged: (val) => setState(() => _secilenHayvanRengi = val),
                  required: true,
                ),

                if (_isKayip || _isSahiplendirme)
                  _buildAsiDuzenlemeAlani(),

                _buildLocationField(),

                _buildTextField(
                  controller: _ekstraBilgiController,
                  label: 'Ekstra Bilgi/Açıklama',
                  icon: Icons.info,
                ),

                if (_isSahiplendirme) ...[
                  _buildTextField(
                    controller: _aliskanlikController,
                    label: 'Hayvanın Alışkanlıkları',
                    icon: Icons.psychology,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          title: const Text('Kısırlaştırılmış mı?'),
                          value: _kisirMi,
                          onChanged: (v) => setState(() => _kisirMi = v!),
                          activeColor: turuncuPastel,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          title: const Text('Kısırlaştırma Şartı'),
                          value: _kisirlastirmaSarti,
                          onChanged: (v) => setState(() => _kisirlastirmaSarti = v!),
                          activeColor: turuncuPastel,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],

                if (_isKayip || _isSahiplendirme) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: _buildDropdown(
                            value: _cinsiyet,
                            label: 'Cinsiyet',
                            items: const ['Dişi', 'Erkek'],
                            onChanged: (val) => setState(() => _cinsiyet = val ?? 'Dişi'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Row(
                            children: [
                              Switch(
                                value: _cipli,
                                onChanged: (val) => setState(() => _cipli = val),
                                activeColor: turuncuPastel,
                              ),
                              const Text('Çipli Mi?'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_yukleniyor || _fotografIsleniyor) ? null : _ilanGuncelle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: zeytinYesili,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _yukleniyor
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : const Text(
                      'Değişiklikleri Kaydet',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),

          if (_fotografIsleniyor)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text("Fotoğraf hazırlanıyor...", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}