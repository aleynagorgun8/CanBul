import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';

// Proje dosyaları
import 'ilanlar.dart';
import 'shared_bottom_nav.dart';
import 'profil.dart';
import 'mesajlar.dart';

final supabase = Supabase.instance.client;

const String _PROFIL_FOTO_KOVA_ADI = 'profil_fotolari';

// --- SORGULAR ---
const String _KAYIP_ILAN_FIELDS = 'id, hayvan_adi, hayvan_turu, hayvan_rengi, hayvan_cinsiyeti, cipi_var_mi, ekstra_bilgi, created_at, konum, konum_text';
const String _BULUNAN_ILAN_FIELDS = 'id, hayvan_turu, hayvan_rengi, hayvan_cinsiyeti, ekstra_bilgi, created_at, konum, konum_text';
const String _SAHIPLENDIRME_ILAN_FIELDS = 'id, hayvan_adi, hayvan_turu, hayvan_rengi, hayvan_cinsiyeti, cipi_var_mi, kisir_mi, kisirlastirma_sarti, aliskanliklar, ekstra_bilgi, created_at, konum, konum_text';

// Profil fotoğrafı için güvenli URL alma
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

// Fotoğraf URL'lerini çek
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

// POINT(x y) verisini LatLng nesnesine çevirir
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


// Kullanıcı Profil Sayfası
class KullaniciProfili extends StatefulWidget {
  final String kullaniciId; // Görüntülenen profilin ID'si

  const KullaniciProfili({super.key, required this.kullaniciId});

  @override
  State<KullaniciProfili> createState() => _KullaniciProfiliState();
}

class _KullaniciProfiliState extends State<KullaniciProfili> with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = supabase;

  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _profile;
  String? _profilFotoGuvenliUrl;
  bool _takipEdiliyorMi = false;
  late TabController _tabController;

  // Takip Sayıları
  int _takipciSayisi = 0;
  int _takipEdilenSayisi = 0;

  List<Map<String, dynamic>> _ilanlar = [];

  // İlan Listeleri
  List<Map<String, dynamic>> _kayipIlanlar = [];
  List<Map<String, dynamic>> _bulunanIlanlar = [];
  List<Map<String, dynamic>> _sahiplendirmeIlanlar = [];
  List<Map<String, dynamic>> _repostIlanlar = [];

  int _ilanFilterIndex = 0;

  int get _toplamIlanSayisi =>
      _kayipIlanlar.length + _bulunanIlanlar.length + _sahiplendirmeIlanlar.length + _repostIlanlar.length;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadProfile();
    _loadTakipSayilari(); // Takip sayılarını yükle
    _checkTakipDurumu();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  Future<void> _loadProfile() async {
    try {
      final data = await _supabase
          .from('profiles')
          .select('id, tam_ad, email, telefon, created_at, profil_foto')
          .eq('id', widget.kullaniciId)
          .maybeSingle();

      final Map<String, dynamic>? profilData = data as Map<String, dynamic>?;

      String? fotoYolu = profilData?['profil_foto'] as String?;
      String? guvenliUrl;
      if (fotoYolu != null) {
        guvenliUrl = await _profilFotoGuvenliUrlGetir(fotoYolu);
      }

      setState(() {
        _profile = profilData;
        _profilFotoGuvenliUrl = guvenliUrl;
        _isLoading = false;
      });

      if (_profile != null) {
        _loadIlanlar();
      }
    } catch (e) {
      setState(() {
        _error = 'Profil yüklenemedi: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTakipSayilari() async {
    try {
      final List<dynamic> takipciList = await _supabase
          .from('takipler')
          .select('id')
          .eq('takip_edilen', widget.kullaniciId);

      final List<dynamic> takipEdilenList = await _supabase
          .from('takipler')
          .select('id')
          .eq('takip_eden', widget.kullaniciId);

      if (mounted) {
        setState(() {
          _takipciSayisi = takipciList.length;
          _takipEdilenSayisi = takipEdilenList.length;
        });
      }
    } catch (e) {
      print('Takip sayıları yüklenemedi: $e');
    }
  }

  Future<void> _checkTakipDurumu() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) return;

      final result = await _supabase
          .from('takipler')
          .select('id')
          .eq('takip_eden', currentUser.id)
          .eq('takip_edilen', widget.kullaniciId)
          .maybeSingle();

      setState(() {
        _takipEdiliyorMi = result != null;
      });
    } catch (e) {
      print('Takip durumu kontrol edilemedi: $e');
    }
  }

  // --- İLAN YÜKLEME FONKSİYONLARI ---
  Future<void> _loadIlanlar() async {
    try {
      //  Kayıp
      final List<dynamic> kayip = await _supabase
          .from('kayip_ilanlar')
          .select(_KAYIP_ILAN_FIELDS)
          .eq('kullanici_id', widget.kullaniciId)
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
        };
      }).toList();

      //  Bulunan
      final List<dynamic> bulunan = await _supabase
          .from('bulunan_ilanlar')
          .select(_BULUNAN_ILAN_FIELDS)
          .eq('kullanici_id', widget.kullaniciId)
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
        };
      }).toList();

      // Sahiplendirme
      final List<dynamic> sahiplendirme = await _supabase
          .from('sahiplendirme_ilanlar')
          .select(_SAHIPLENDIRME_ILAN_FIELDS)
          .eq('kullanici_id', widget.kullaniciId)
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
        };
      }).toList();

      await _loadRepostIlanlar();

      setState(() {
        _kayipIlanlar = normalizedKayip;
        _bulunanIlanlar = normalizedBulunan;
        _sahiplendirmeIlanlar = normalizedSahiplendirme;
        _ilanlar = _kayipIlanlar;
      });
    } catch (e) {
      print('İlanlar yüklenemedi: $e');
    }
  }

  Future<void> _loadRepostIlanlar() async {
    try {
      final List<dynamic> repostKayitlari = await _supabase
          .from('repostlar')
          .select('ilan_id, ilan_tipi, created_at')
          .eq('kullanici_id', widget.kullaniciId)
          .order('created_at', ascending: false);

      if (repostKayitlari.isEmpty) {
        setState(() {
          _repostIlanlar = [];
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
        _repostIlanlar = repostIlanlar;
      });

    } catch (e) {
      print('Repost ilanlar yüklenirken hata: $e');
      setState(() {
        _repostIlanlar = [];
      });
    }
  }

  Future<void> _toggleTakip() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Takip etmek için giriş yapmalısınız.'), backgroundColor: Colors.red),
        );
        return;
      }

      if (currentUser.id == widget.kullaniciId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kendinizi takip edemezsiniz.'), backgroundColor: Colors.orange),
        );
        return;
      }

      if (_takipEdiliyorMi) {
        await _supabase
            .from('takipler')
            .delete()
            .eq('takip_eden', currentUser.id)
            .eq('takip_edilen', widget.kullaniciId);

        setState(() {
          _takipEdiliyorMi = false;
          _takipciSayisi = (_takipciSayisi - 1).clamp(0, 999999);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${_profile!['tam_ad']} takip listesinden çıkarıldı.'), backgroundColor: const Color(0xFFFFB74D)),
          );
        }
      } else {
        await _supabase.from('takipler').insert({
          'takip_eden': currentUser.id,
          'takip_edilen': widget.kullaniciId,
        });

        setState(() {
          _takipEdiliyorMi = true;
          _takipciSayisi++;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${_profile!['tam_ad']} takip ediliyor.'), backgroundColor: const Color(0xFF558B2F)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Takip işlemi başarısız: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

// MESAJ GÖNDERME
  void _sohbetBaslatVeGit() {
    final currentUser = _supabase.auth.currentUser;

    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mesaj göndermek için giriş yapmalısınız.'))
      );
      return;
    }

    if (currentUser.id == widget.kullaniciId) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kendinize mesaj gönderemezsiniz.'))
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SohbetEkrani(
          aliciId: widget.kullaniciId,
          aliciAd: _profile?['tam_ad'] ?? 'Kullanıcı',
          aliciFotoUrl: _profilFotoGuvenliUrl,
        ),
      ),
    );
  }

  Future<void> _showFollowListModal(String type) async {
    final String baslik = type == 'followers' ? 'Takipçiler' : 'Takip Ettikleri';
    final String fromTable = 'takipler';
    final String selectField = type == 'followers'
        ? 'takip_eden(id, tam_ad, profil_foto)'
        : 'takip_edilen(id, tam_ad, profil_foto)';
    final String eqField = type == 'followers' ? 'takip_edilen' : 'takip_eden';

    showDialog(context: context, builder: (c) => const Center(child: CircularProgressIndicator()));

    try {
      final List<dynamic> takipData = await _supabase
          .from(fromTable)
          .select(selectField)
          .eq(eqField, widget.kullaniciId);

      if (mounted) Navigator.pop(context);

      final List<Map<String, dynamic>> users = takipData
          .map((item) => item[type == 'followers' ? 'takip_eden' : 'takip_edilen'] as Map<String, dynamic>)
          .toList();

      if (!mounted) return;

      final currentUserId = _supabase.auth.currentUser?.id;

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
                      child: Text(baslik, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF558B2F))),
                    ),
                    const Divider(height: 1, thickness: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final user = users[index];
                          final String userId = user['id'] as String;
                          return _FollowListTile(
                            ad: user['tam_ad'] as String? ?? 'Kullanıcı',
                            fotoYolu: user['profil_foto'] as String?,
                            onTap: () {
                              Navigator.pop(context);
                              if (currentUserId != null && userId == currentUserId) {
                                Navigator.push(context, MaterialPageRoute(builder: (context) => const Profil()));
                              } else {
                                Navigator.push(context, MaterialPageRoute(builder: (context) => KullaniciProfili(kullaniciId: userId)));
                              }
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
    } catch (e) {
      if(mounted && Navigator.canPop(context)) Navigator.pop(context);
      print("Liste getirme hatası: $e");
    }
  }


  String _wrapNameByWord(String name, {int maxLineLength = 16}) {
    final words = name.split(RegExp(r'\s+'));
    final StringBuffer wrappedText = StringBuffer();
    int currentLineLength = 0;
    for (final word in words) {
      if (word.length > maxLineLength) {
        if (wrappedText.isNotEmpty) wrappedText.writeln();
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
        if (wrappedText.isNotEmpty && currentLineLength > 0) wrappedText.write(' ');
        wrappedText.write(word);
        currentLineLength += word.length + (currentLineLength > 0 ? 1 : 0);
      }
    }
    return wrappedText.toString();
  }

  Future<void> _ilanDetayinaYonlendir(Map<String, dynamic> ilanData) async {
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

      final ilanDetay = await _supabase.from(tabloAdi).select(selectQuery).eq('id', ilanId).maybeSingle();

      if (ilanDetay == null || ilanDetay is! Map<String, dynamic>) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İlan detayı bulunamadı.'), backgroundColor: Colors.red));
        return;
      }

      final List<dynamic> fotos = await _supabase
          .from('ilan_fotograflari')
          .select('foto_url')
          .eq('ilan_id', ilanId)
          .eq('ilan_tipi', ilanTipi)
          .order('created_at', ascending: true);

      final List<String> fotoUrlListesi = fotos.map((e) => e['foto_url'] as String).toList();
      final Map<String, dynamic> detayData = ilanDetay;
      final profileData = detayData['profiles'] as Map<String, dynamic>?;

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
            adresGosterimi = "Konum Hatası";
            print("Adres çözümleme hatası: $e");
          }
        }
      }
      detayData['konum'] = adresGosterimi;

      final Ilan ilanNesnesi = Ilan.fromMap(
        data: detayData,
        tip: ilanTipi,
        fotoUrls: fotoUrlListesi,
        kullaniciTel: profileData?['telefon'] ?? 'Numara Yok',
        kullaniciAd: profileData?['tam_ad'] ?? 'Anonim Kullanıcı',
        isRepost: ilanData.containsKey('repost') ? ilanData['repost'] == true : false,
      );

      if (mounted) Navigator.push(context, MaterialPageRoute(builder: (context) => IlanDetaySayfasi(ilan: ilanNesnesi)));

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color arkaPlan = Color(0xFFF1F8E9);
    const Color beyaz = Colors.white;
    const Color gri = Color(0xFF9E9E9E);
    const Color turuncuPastel = Color(0xFFFFB74D);
    const Color zeytinYesili = Color(0xFF558B2F);

    const Color mesajButonRengi = Color(0xFF495E71);

    return Scaffold(
      backgroundColor: arkaPlan,
      appBar: AppBar(
        backgroundColor: zeytinYesili,
        foregroundColor: beyaz,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_profile?['tam_ad'] ?? 'Profil', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: turuncuPastel))
          : _error != null
          ? Center(child: Text(_error!))
          : _profile == null
          ? const Center(child: Text('Profil bulunamadı'))
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
                    BoxShadow(color: gri.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  children: [
                    _ProfileAvatar(
                      url: _profilFotoGuvenliUrl,
                      ad: _profile!['tam_ad'],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            _wrapNameByWord(_profile!['tam_ad'] ?? 'Kullanıcı', maxLineLength: 16),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
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
                    Text(_profile!['email'] ?? '-', style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 16),

                    _FollowStats(
                      takipciSayisi: _takipciSayisi,
                      takipEdilenSayisi: _takipEdilenSayisi,
                      onTapTakipci: () => _showFollowListModal('followers'),
                      onTapTakipEdilen: () => _showFollowListModal('following'),
                    ),
                    const SizedBox(height: 16),

                    // --- BUTONLAR ---
                    Row(
                      children: [
                        // TAKİP ET BUTONU
                        Expanded(
                          child: SizedBox(
                            height: 45,
                            child: ElevatedButton(
                              onPressed: _toggleTakip,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _takipEdiliyorMi ? Colors.grey : turuncuPastel,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(_takipEdiliyorMi ? Icons.check : Icons.person_add, color: beyaz, size: 20),
                                  const SizedBox(width: 6),
                                  Text(
                                    _takipEdiliyorMi ? 'Takipte' : 'Takip Et',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // MESAJ GÖNDER BUTONU
                        Expanded(
                          child: SizedBox(
                            height: 45,
                            child: ElevatedButton(
                              onPressed: _sohbetBaslatVeGit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: mesajButonRengi,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.message, color: beyaz, size: 20),
                                  SizedBox(width: 6),
                                  Text(
                                    'Mesaj Gönder',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ],
                              ),
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
                Tab(text: 'Bilgiler'),
                Tab(text: 'İlanları'),
              ],
            ),
          ),

          // Tab Bar Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // BİLGİLER
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: beyaz,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: gri.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.person_outline, color: Color(0xFFFFB74D)),
                            SizedBox(width: 8),
                            Text('Profil Bilgileri', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF558B2F))),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _InfoField(icon: Icons.person, label: 'Ad Soyad', value: _profile!['tam_ad'] ?? '-'),
                        const SizedBox(height: 12),
                        _InfoField(icon: Icons.email, label: 'E-posta', value: _profile!['email'] ?? '-'),
                        const SizedBox(height: 12),
                        _InfoField(icon: Icons.phone, label: 'Telefon', value: _profile!['telefon'] ?? '-'),
                        const SizedBox(height: 12),
                        _InfoField(icon: Icons.calendar_today, label: 'Kayıt Tarihi', value: _formatDate(_profile!['created_at'])),
                      ],
                    ),
                  ),
                ),

                // İLANLAR
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
                              _ilanlar = _kayipIlanlar;
                            } else if (idx == 1) {
                              _ilanlar = _bulunanIlanlar;
                            } else if (idx == 2) {
                              _ilanlar = _sahiplendirmeIlanlar;
                            } else {
                              _ilanlar = _repostIlanlar;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _ilanlar.isEmpty
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.list_alt, size: 64, color: gri),
                            const SizedBox(height: 16),
                            Text(
                              _ilanFilterIndex == 0
                                  ? 'Henüz kayıp ilanı bulunmuyor'
                                  : _ilanFilterIndex == 1
                                  ? 'Henüz bulunan ilanı bulunmuyor'
                                  : _ilanFilterIndex == 2
                                  ? 'Henüz sahiplendirme ilanı bulunmuyor'
                                  : 'Henüz yeniden paylaşılan ilan bulunmuyor',
                              style: const TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                          : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _ilanlar.length,
                        itemBuilder: (context, index) {
                          final ilan = _ilanlar[index];
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
                              leading: ClipRRect(
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
                              title: Text(_wrapNameByWord(baslik.isNotEmpty ? baslik : 'İlan', maxLineLength: 25), style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: altSatir.isNotEmpty
                                  ? Text(altSatir, style: TextStyle(color: gri))
                                  : Text(ilanTipi == 'kayip' ? 'Kayıp İlanı' : (ilanTipi == 'sahiplendirme' ? 'Sahiplendirme İlanı' : 'Bulunan İlanı'), style: TextStyle(color: gri)),
                              trailing: Icon(Icons.arrow_forward_ios, size: 16, color: gri),
                              onTap: () => _ilanDetayinaYonlendir(ilan),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const SizedBox.shrink(),
    );
  }
}

// YARDIMCI WIDGET'LAR
class _FollowStats extends StatelessWidget {
  final int takipciSayisi;
  final int takipEdilenSayisi;
  final VoidCallback onTapTakipci;
  final VoidCallback onTapTakipEdilen;

  const _FollowStats({required this.takipciSayisi, required this.takipEdilenSayisi, required this.onTapTakipci, required this.onTapTakipEdilen});

  @override
  Widget build(BuildContext context) {
    const Color beyaz = Colors.white;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        GestureDetector(
          onTap: onTapTakipci,
          child: _StatItem(count: takipciSayisi, label: 'Takipçi', countColor: beyaz, labelColor: Colors.white70),
        ),
        Container(height: 30, width: 1, color: Colors.white54),
        GestureDetector(
          onTap: onTapTakipEdilen,
          child: _StatItem(count: takipEdilenSayisi, label: 'Takip Edilen', countColor: beyaz, labelColor: Colors.white70),
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
  const _StatItem({required this.count, required this.label, required this.countColor, required this.labelColor});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(count.toString(), style: TextStyle(color: countColor, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: labelColor, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _FollowListTile extends StatefulWidget {
  final String ad;
  final String? fotoYolu;
  final VoidCallback onTap;
  const _FollowListTile({required this.ad, required this.fotoYolu, required this.onTap});
  @override
  State<_FollowListTile> createState() => _FollowListTileState();
}

class _FollowListTileState extends State<_FollowListTile> {
  String? _guvenliFotoUrl;
  @override
  void initState() { super.initState(); _loadFotoUrl(); }
  Future<void> _loadFotoUrl() async {
    if (widget.fotoYolu != null && widget.fotoYolu!.isNotEmpty) {
      final url = await _profilFotoGuvenliUrlGetir(widget.fotoYolu);
      if (mounted) setState(() { _guvenliFotoUrl = url; });
    }
  }
  @override
  Widget build(BuildContext context) {
    const Color zeytinYesili = Color(0xFF558B2F);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: zeytinYesili.withOpacity(0.2),
        backgroundImage: _guvenliFotoUrl != null ? NetworkImage(_guvenliFotoUrl!) as ImageProvider : null,
        child: _guvenliFotoUrl == null ? Text(_initialsFromName(widget.ad), style: const TextStyle(color: zeytinYesili)) : null,
      ),
      title: Text(widget.ad, style: const TextStyle(fontWeight: FontWeight.w600)),
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

class _ProfileAvatar extends StatelessWidget {
  final String? url;
  final String? ad;
  const _ProfileAvatar({required this.url, required this.ad});
  @override
  Widget build(BuildContext context) {
    final initials = _initialsFromName(ad);
    return Container(
      width: 100, height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: CircleAvatar(
        radius: 46, backgroundColor: Colors.white.withOpacity(0.2),
        backgroundImage: (url != null && url!.trim().isNotEmpty) ? NetworkImage(url!) : null,
        child: (url == null || url!.trim().isEmpty)
            ? Text(initials, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)) : null,
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

class _InfoField extends StatelessWidget {
  final IconData icon; final String label; final String value;
  const _InfoField({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    const Color gri = Color(0xFF9E9E9E); const Color turuncuPastel = Color(0xFFFFB74D);
    return Row(children: [
      Icon(icon, color: turuncuPastel, size: 20), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, color: gri)), const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      ])),
    ]);
  }
}

class _FilterChips extends StatelessWidget {
  final int selectedIndex; final ValueChanged<int> onChanged;
  const _FilterChips({required this.selectedIndex, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    const Color zeytinYesili = Color(0xFF558B2F); const Color turuncuPastel = Color(0xFFFFB74D); const Color gri = Color(0xFF9E9E9E);
    final items = const [{'label': 'Kayıp', 'icon': Icons.pets}, {'label': 'Bulunan', 'icon': Icons.search}, {'label': 'Sahiplendir', 'icon': Icons.volunteer_activism}, {'label': 'Yeniden', 'icon': Icons.repeat}];
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: List.generate(items.length, (i) {
      final selected = i == selectedIndex;
      return GestureDetector(onTap: () => onChanged(i), child: Container(
        height: 36, padding: const EdgeInsets.symmetric(horizontal: 12), margin: EdgeInsets.only(left: i == 0 ? 0 : 6, right: i == items.length - 1 ? 0 : 0),
        decoration: BoxDecoration(color: selected ? turuncuPastel : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: selected ? turuncuPastel : gri.withOpacity(0.3))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(items[i]['icon'] as IconData, size: 16, color: selected ? Colors.white : zeytinYesili), const SizedBox(width: 4),
          Text(items[i]['label'] as String, style: TextStyle(color: selected ? Colors.white : zeytinYesili, fontWeight: FontWeight.w600, fontSize: 11), textAlign: TextAlign.center),
        ]),
      ));
    })));
  }
}