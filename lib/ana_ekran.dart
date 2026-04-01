import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import 'shared_bottom_nav.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'konum_sec_sayfasi.dart';
import 'bildirimler.dart';
import 'package:http/http.dart' as http;
import 'yapay_zeka_servisi.dart';
import 'dart:convert';
import 'EslesmeDetaySayfasi.dart';
import 'tutorial_yardimcisi.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

final supabase = Supabase.instance.client;

enum IlanTipi { kayip, bulunan, sahiplendirme }

const List<String> hayvanTurleri = ['Kedi', 'Köpek'];
const List<String> tumRenkler = ['Siyah', 'Beyaz', 'Gri', 'Kahverengi', 'Sarı', 'Çok Renkli'];
const Map<String, List<String>> renkSecenekleri = {
  'Kedi': ['Sarman', 'Tekir', 'Smokin', 'Siyah', 'Beyaz', 'Gri', 'Kahverengi', 'Calico'],
  'Köpek': ['Sarı', 'Siyah', 'Beyaz', 'Gri', 'Kahverengi', 'Dalmaçyalı', 'Çok renkli'],
};

class AnaEkran extends StatefulWidget {
  final String kullaniciAdi;
  static String? _cachedKullaniciAdi;
  const AnaEkran({super.key, required this.kullaniciAdi});
  @override
  State<AnaEkran> createState() => _AnaEkranState();
}

class _AnaEkranState extends State<AnaEkran> {
  SupabaseClient get _supabase => supabase;
  IlanTipi _secilenIlanTipi = IlanTipi.kayip;
  List<XFile> secilenFotograflar = [];
  final ImagePicker _picker = ImagePicker();
  bool _yukleniyor = false;
  final ScrollController _formScrollController = ScrollController();

  final TextEditingController hayvanAdController = TextEditingController();
  final TextEditingController ekstraBilgiController = TextEditingController();
  final TextEditingController ekstraBilgiBulduController = TextEditingController();
  final TextEditingController aliskanlikController = TextEditingController();
  final TextEditingController kayipKonumController = TextEditingController();
  final TextEditingController bulunanKonumController = TextEditingController();
  final TextEditingController sahiplendirmeKonumController = TextEditingController();

  LatLng? _secilenKayipKoordinat;
  LatLng? _secilenBulunanKoordinat;
  LatLng? _secilenSahiplendirmeKoordinat;

  String? _secilenHayvanTuru;
  String? _secilenHayvanRengi;
  String cinsiyet = 'Dişi';
  bool cipli = false;
  bool kisirMi = false;
  bool kisirlastirmaSarti = false;

  List<String> _mevcutRenkSecenekleri = [];
  List<Map<String, dynamic>> _mevcutAsiSecenekleri = [];
  List<String> _secilenAsiIdleri = [];
  String _gosterilecekAd = "";

  final Color turuncuPastel = const Color(0xFFFFB74D);
  final Color zeytinYesili = const Color(0xFF558B2F);
  final Color arkaPlan = const Color(0xFFF1F8E9);
  final Color beyaz = Colors.white;
  final Color gri = const Color(0xFF9E9E9E);
  final Color koyuMavi = const Color(0xFF002D72);

  // --- EĞİTİM HEDEFLERİ (KEYS) --- ✅
  final GlobalKey _keyBaslik = GlobalKey();
  final GlobalKey _keyBilgiButonu = GlobalKey();
  final GlobalKey _keyBildirimler = GlobalKey();
  final GlobalKey _keySekmeler = GlobalKey();
  final GlobalKey _keyFotoYukleme = GlobalKey();
  final GlobalKey _keyKonum = GlobalKey();
  final GlobalKey _keyEkstraBilgi = GlobalKey();

  // Navbar Parçaları İçin Hedefler
  final GlobalKey _keyNavAkis = GlobalKey();
  final GlobalKey _keyNavHarita = GlobalKey();
  final GlobalKey _keyNavIlanlar = GlobalKey();
  final GlobalKey _keyNavProfil = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ismiBelirleVeGuncelle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _egitimiBaslat();
    });
  }

  Future<void> _konumAlaninaKaydir() async {
    if (!_formScrollController.hasClients || _keyKonum.currentContext == null) return;
    await Scrollable.ensureVisible(
      _keyKonum.currentContext!,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
      alignment: 0.2,
    );
  }

  void _egitimiBaslat({bool zorla = false}) {
    TutorialYardimcisi.egitimiGoster(
      context: context,
      sayfaAnahtari: 'ana_ekran_egitim_final_kutu',
      zorlaGoster: zorla,
      kaydetTamamlandi: false,
      onFinish: () async {
        if (!mounted) return;
        await _konumAlaninaKaydir();
        if (!mounted) return;
        _egitimiTamamla(zorla: true);
      },
      hedefler: [
        TargetFocus(
          identify: "bilgi_butonu",
          keyTarget: _keyBilgiButonu,
          alignSkip: Alignment.bottomLeft,
          shape: ShapeLightFocus.Circle,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) => Container(
                margin: const EdgeInsets.only(top: 30.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: const [
                    Text("Rehber Hep Burada! ℹ️", textAlign: TextAlign.right, style: TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.bold, fontSize: 24)),
                    SizedBox(height: 30),
                    Text("Bu sayfada ne yapacağını unutursan, bu ikona tıklayarak eğitimi tekrar başlatabilirsin.", textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4)),
                  ],
                ),
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: "bildirimler",
          keyTarget: _keyBildirimler,
          alignSkip: Alignment.bottomLeft,
          shape: ShapeLightFocus.Circle,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) => Container(
                margin: const EdgeInsets.only(top: 30.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: const [
                    Text("Tüm Bildirimler Tek Yerde 🔔", textAlign: TextAlign.right, style: TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.bold, fontSize: 24)),
                    SizedBox(height: 12),
                    Text("Hem diğer kullanıcılardan gelen sosyal bildirimleri (beğeni, yorum) hem de yapay zekanın bulduğu eşleşme bildirimlerini anlık görüntüleyebilirsin.", textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4)),
                  ],
                ),
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: "sekmeler",
          keyTarget: _keySekmeler,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) => Container(
                margin: const EdgeInsets.only(top: 30.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text("İlan Türünü Seç 🐾", style: TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.bold, fontSize: 24)),
                    SizedBox(height: 12),
                    Text("Kayıp aramak, bulduğun bir canı bildirmek veya sahiplendirmek için önce buradan doğru sekmeyi seçmelisin.", style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4)),
                  ],
                ),
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: "foto_yukleme",
          keyTarget: _keyFotoYukleme,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (context, controller) => Container(
                margin: const EdgeInsets.only(bottom: 30.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text("Yapay Zeka Seni Bekliyor 🧬", style: TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.bold, fontSize: 24)),
                    SizedBox(height: 12),
                    Text("Hayvanın yüzünün net göründüğü fotoğraflar yüklemek, akıllı analiz sistemimizin eşleşme bulma ihtimalini inanılmaz artırır!", style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _egitimiTamamla({bool zorla = false}) {
    TutorialYardimcisi.egitimiGoster(
      context: context,
      sayfaAnahtari: 'ana_ekran_egitim_final_kutu',
      kaydetTamamlandi: false,
      onFinish: () {
        if (!mounted) return;
        _egitimiVeda(zorla: true);
      },
      zorlaGoster: zorla,
      hedefler: [
        TargetFocus(
          identify: "konum",
          keyTarget: _keyKonum,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (context, controller) => Container(
                margin: const EdgeInsets.only(bottom: 30.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text("Konum Çok Kritik! 📍", style: TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.bold, fontSize: 24)),
                    SizedBox(height: 12),
                    Text("Haritadan doğru konumu seçmen çok önemli. Sistemin o bölgedeki insanlara bildirim gönderebilmesi için isabetli konum belirlemelisin.", style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4)),
                  ],
                ),
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: "ekstra_bilgi",
          keyTarget: _keyEkstraBilgi,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (context, controller) => Container(
                margin: const EdgeInsets.only(bottom: 30.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text("Ayırt Edici Özellikler 📝", style: TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.bold, fontSize: 24)),
                    SizedBox(height: 12),
                    Text("Bu alan zorunlu değil. Ancak hayvanın tasması, yara izi veya karakteri gibi ayırt edici başka şeylerin eklenmesi bulunmasını hızlandırır.", style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4)),
                  ],
                ),
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: "nav_akis",
          keyTarget: _keyNavAkis,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (context, controller) => Container(
                margin: const EdgeInsets.only(bottom: 30.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text("Akış Sayfası 📱", style: TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.bold, fontSize: 24)),
                    SizedBox(height: 12),
                    Text("Burası sosyal alandır. İlanları paylaşarak ulaşılabilirliği artırabilir ve mesajlaşma işlevini bu sayfadan yürütebilirsin.", style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4)),
                  ],
                ),
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: "nav_harita",
          keyTarget: _keyNavHarita,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (context, controller) => Container(
                margin: const EdgeInsets.only(bottom: 30.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text("Harita Görünümü 🗺️", style: TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.bold, fontSize: 24)),
                    SizedBox(height: 12),
                    Text("İlanları harita üzerinde konum bazlı görüntüleyebilir; ek olarak çevrendeki veteriner ve petshopları bulabilirsin.", style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4)),
                  ],
                ),
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: "nav_ilanlar",
          keyTarget: _keyNavIlanlar,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (context, controller) => Container(
                margin: const EdgeInsets.only(bottom: 30.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text("Tüm İlanlar 📋", style: TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.bold, fontSize: 24)),
                    SizedBox(height: 12),
                    Text("Sistemdeki tüm ilanların listelendiği alandır. Gelişmiş filtrelerle ilanları tüm detaylarıyla burada görüntüleyebilirsin.", style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4)),
                  ],
                ),
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: "nav_profil",
          keyTarget: _keyNavProfil,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (context, controller) => Container(
                margin: const EdgeInsets.only(bottom: 30.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: const [
                    Text("Profil Yönetimi 👤", textAlign: TextAlign.right, style: TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.bold, fontSize: 24)),
                    SizedBox(height: 12),
                    Text("Kendi profilini görüntüleyerek kişisel bilgilerini düzenleyebilir ve kendi paylaştığın ilanları buradan yönetebilirsin.", textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _egitimiVeda({bool zorla = false}) {
    TutorialYardimcisi.egitimiGoster(
      context: context,
      sayfaAnahtari: 'ana_ekran_egitim_final_kutu',
      zorlaGoster: zorla,
      skipGoster: false,
      hedefler: [
        TargetFocus(
          identify: "veda",
          keyTarget: _keyBaslik,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) => Container(
                margin: const EdgeInsets.only(top: 40.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text("Eğitim Tamamlandı! 🎉", style: TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.bold, fontSize: 24)),
                    SizedBox(height: 12),
                    Text("Uygulamayı kullanmaya tamamen hazırsın. Dilediğin zaman ℹ️ ikonundan bu rehberi açabilirsin. Sevimli dostlarımıza umarız çok yardımcı olursun!", style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _ismiBelirleVeGuncelle() {
    if (widget.kullaniciAdi.isNotEmpty && widget.kullaniciAdi != 'Kullanıcı') {
      _gosterilecekAd = widget.kullaniciAdi;
      AnaEkran._cachedKullaniciAdi = widget.kullaniciAdi;
    } else if (AnaEkran._cachedKullaniciAdi != null) {
      _gosterilecekAd = AnaEkran._cachedKullaniciAdi!;
    } else {
      final user = _supabase.auth.currentUser;
      final metaName = user?.userMetadata?['tam_ad'];
      _gosterilecekAd = metaName ?? "Kullanıcı";
    }
    _kullaniciAdiniVeritabanindanGuncelle();
  }

  Future<void> _kullaniciAdiniVeritabanindanGuncelle() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        final data = await _supabase.from('profiles').select('tam_ad').eq('id', user.id).maybeSingle();
        if (data != null && mounted) {
          final yeniAd = data['tam_ad'] ?? "Kullanıcı";
          if (_gosterilecekAd != yeniAd) {
            setState(() => _gosterilecekAd = yeniAd);
            AnaEkran._cachedKullaniciAdi = yeniAd;
          }
        }
      } catch (e) {}
    }
  }

  @override
  void dispose() {
    _formScrollController.dispose();
    hayvanAdController.dispose();
    ekstraBilgiController.dispose();
    ekstraBilgiBulduController.dispose();
    aliskanlikController.dispose();
    kayipKonumController.dispose();
    bulunanKonumController.dispose();
    sahiplendirmeKonumController.dispose();
    super.dispose();
  }

  Future<void> _asiListesiniGetir(String hayvanTuru) async {
    if (hayvanTuru != 'Kedi' && hayvanTuru != 'Köpek') {
      setState(() => _mevcutAsiSecenekleri = []);
      return;
    }
    try {
      final List<Map<String, dynamic>>? veriler = await _supabase
          .from('asilistesi')
          .select('id, asi_adi')
          .eq('hayvan_turu', hayvanTuru)
          .order('asi_adi', ascending: true);
      if (mounted) setState(() => _mevcutAsiSecenekleri = veriler ?? []);
    } catch (e) {}
  }

  void _hayvanTuruDegisti(String? yeniTur) {
    setState(() {
      _secilenHayvanTuru = yeniTur;
      _secilenAsiIdleri.clear();
      _mevcutRenkSecenekleri = (yeniTur != null && renkSecenekleri.containsKey(yeniTur))
          ? renkSecenekleri[yeniTur]!
          : [];
      _secilenHayvanRengi = null;
      if (yeniTur != null) {
        _asiListesiniGetir(yeniTur);
      } else {
        _mevcutAsiSecenekleri = [];
      }
    });
  }

  String getFormattedUserName() {
    if (_gosterilecekAd.isEmpty) return "Kullanıcı";
    List<String> adParts = _gosterilecekAd.split(' ');
    return adParts.length <= 1 ? _gosterilecekAd : adParts.sublist(0, adParts.length - 1).join(' ');
  }

  Future<XFile?> _resmiKirp(XFile dosya) async {
    CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: dosya.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Fotoğrafı Düzenle',
          toolbarColor: zeytinYesili,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: turuncuPastel,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: 'Fotoğrafı Düzenle'),
      ],
    );
    if (croppedFile != null) return XFile(croppedFile.path);
    return null;
  }

  Future<void> _fotoCekVeyaSec() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: beyaz,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.camera_alt, color: Color(0xFF007bff)), title: const Text('Kamera ile çek'), onTap: () => Navigator.pop(context, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library, color: Color(0xFF007bff)), title: const Text('Galeriden seç'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
          ],
        ),
      ),
    );
    if (source == null) return;

    if (source == ImageSource.gallery) {
      final List<XFile>? fotolar = await _picker.pickMultiImage(imageQuality: 85);
      if (fotolar != null) {
        for (var foto in fotolar) {
          XFile? kirpilmisFoto = await _resmiKirp(foto);
          if (kirpilmisFoto != null) setState(() => secilenFotograflar.add(kirpilmisFoto));
        }
      }
    } else {
      final XFile? foto = await _picker.pickImage(source: source, imageQuality: 85);
      if (foto != null) {
        XFile? kirpilmisFoto = await _resmiKirp(foto);
        if (kirpilmisFoto != null) setState(() => secilenFotograflar.add(kirpilmisFoto));
      }
    }
  }

  Future<void> _cihazUzerindeAnalizYap(List<double> yeniVektor, String tip, LatLng suAnkiKonum, String yeniIlanId) async {
    final aiServisi = YapayZekaServisi();
    final String hedefTip = (tip == 'kayip') ? 'bulunan' : 'kayip';
    final String hedefTablo = (tip == 'kayip') ? 'bulunan_ilanlar' : 'kayip_ilanlar';

    try {
      final List<dynamic> veriler = await _supabase.from('ilan_fotograflari').select('ilan_id, yuz_vektoru').eq('ilan_tipi', hedefTip);
      List<Map<String, dynamic>> adaylar = [];
      for (var kayit in veriler) {
        if (kayit['yuz_vektoru'] == null) continue;
        try {
          List<double> karsiVektor = [];
          var data = kayit['yuz_vektoru'];
          if (data is List) {
            karsiVektor = data.map((e) => double.parse(e.toString())).toList();
          } else {
            String s = data.toString().replaceAll(RegExp(r'[\[\]{}]'), '');
            karsiVektor = s.split(',').map((e) => double.parse(e.trim())).toList();
          }

          if (karsiVektor.length == 4096) {
            double skor = aiServisi.kosinusBenzerligiHesapla(yeniVektor, karsiVektor);
            adaylar.add({'ilan_id': kayit['ilan_id'], 'skor': skor});
          }
        } catch (e) { continue; }
      }

      adaylar.sort((a, b) => b['skor'].compareTo(a['skor']));
      var enYakin5 = adaylar.take(5).toList();

      for (var aday in enYakin5) {
        try {
          final ilanDetay = await _supabase.from(hedefTablo).select('konum_text').eq('id', aday['ilan_id']).single();
          String? rawPoint = ilanDetay['konum_text'];
          double ilanLat = 0, ilanLng = 0;

          if (rawPoint != null && rawPoint.contains('POINT')) {
            String clean = rawPoint.replaceAll('POINT(', '').replaceAll(')', '').trim();
            List<String> parcalar = clean.split(' ');
            ilanLng = double.parse(parcalar[0]);
            ilanLat = double.parse(parcalar[1]);
          }

          double mesafe = (ilanLat != 0) ? Geolocator.distanceBetween(suAnkiKonum.latitude, suAnkiKonum.longitude, ilanLat, ilanLng) / 1000 : 0.0;
          if (mesafe <= 300) {
            await _supabase.from('eslesmeler').insert({
              'kayip_ilan_id': tip == 'kayip' ? yeniIlanId : aday['ilan_id'],
              'bulunan_ilan_id': tip == 'bulunan' ? yeniIlanId : aday['ilan_id'],
              'eslesme_skoru': double.parse(aday['skor'].toStringAsFixed(4)),
              'mesafe_km': double.parse(mesafe.toStringAsFixed(1)),
            });
          }
        } catch (e) {}
      }

      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const BildirimlerSayfasi(varsayilanTab: 1)));
      }
    } catch (e) {}
  }

  Future<List<double>?> _fotograflariYukle(String ilanId, String tabloAdi) async {
    List<double>? ilkVektor;
    String klasor = (tabloAdi == 'kayip_ilanlar') ? 'kayip' : (tabloAdi == 'bulunan_ilanlar') ? 'bulunan' : 'sahiplendirme';
    String ilanTipi = (tabloAdi == 'kayip_ilanlar') ? 'kayip' : (tabloAdi == 'bulunan_ilanlar') ? 'bulunan' : 'sahiplendirme';

    for (int i = 0; i < secilenFotograflar.length; i++) {
      try {
        final foto = secilenFotograflar[i];
        final dosya = File(foto.path);
        final aiServisi = YapayZekaServisi();
        List<double> vektor = await aiServisi.fotografiVektoreDonustur(dosya);
        if (i == 0) ilkVektor = vektor;

        final bytes = await dosya.readAsBytes();
        String ext = foto.name.split('.').last.toLowerCase();
        if (ext == 'jpg') ext = 'jpeg';

        final dosyaYolu = '$klasor/$ilanId/${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
        await _supabase.storage.from('hayvan_fotograflari').uploadBinary(dosyaYolu, bytes, fileOptions: FileOptions(upsert: false, contentType: 'image/$ext'));
        final publicUrl = _supabase.storage.from('hayvan_fotograflari').getPublicUrl(dosyaYolu);

        await _supabase.from('ilan_fotograflari').insert({
          'ilan_id': ilanId, 'ilan_tipi': ilanTipi, 'foto_url': publicUrl, 'yuz_vektoru': vektor,
        });
      } catch (e) {}
    }
    return ilkVektor;
  }

  Future<void> _haritadanKonumSec(IlanTipi tip) async {
    final LatLng? result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const KonumSecSayfasi()));
    if (result != null) {
      setState(() {
        final text = "Haritadan Seçildi ✅\n(${result.latitude.toStringAsFixed(5)}, ${result.longitude.toStringAsFixed(5)})";
        if (tip == IlanTipi.kayip) { _secilenKayipKoordinat = result; kayipKonumController.text = text; }
        else if (tip == IlanTipi.bulunan) { _secilenBulunanKoordinat = result; bulunanKonumController.text = text; }
        else { _secilenSahiplendirmeKoordinat = result; sahiplendirmeKonumController.text = text; }
      });
    }
  }

  bool _temelKontroller(LatLng? konum) {
    if (secilenFotograflar.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen en az bir fotoğraf yükleyin.'), backgroundColor: Colors.orange)); return false; }
    if (_secilenHayvanTuru == null || _secilenHayvanRengi == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen hayvan türünü ve rengini seçin.'), backgroundColor: Colors.orange)); return false; }
    if (konum == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen haritadan konumu seçin.'), backgroundColor: Colors.orange)); return false; }
    if (_supabase.auth.currentUser == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Giriş yapmalısınız.'), backgroundColor: Colors.red)); return false; }
    return true;
  }

  Future<void> _ilanKaydetKayip() async {
    if (!_temelKontroller(_secilenKayipKoordinat)) return;
    setState(() => _yukleniyor = true);
    try {
      final kullanici = _supabase.auth.currentUser!;
      await _supabase.rpc('kayip_ilan_ekle', params: {
        'p_kullanici_id': kullanici.id, 'p_hayvan_adi': hayvanAdController.text.trim().isNotEmpty ? hayvanAdController.text.trim() : "İsimsiz",
        'p_hayvan_turu': _secilenHayvanTuru, 'p_hayvan_rengi': _secilenHayvanRengi, 'p_hayvan_cinsiyeti': cinsiyet, 'p_cipi_var_mi': cipli,
        'p_aciklama': ekstraBilgiController.text.trim().isNotEmpty ? ekstraBilgiController.text.trim() : null,
        'p_lat': _secilenKayipKoordinat!.latitude, 'p_lng': _secilenKayipKoordinat!.longitude,
      });

      final sonuc = await _supabase.from('kayip_ilanlar').select('id').eq('kullanici_id', kullanici.id).order('created_at', ascending: false).limit(1).single();
      final String ilanId = sonuc['id'].toString();
      List<double>? vektor = await _fotograflariYukle(ilanId, 'kayip_ilanlar');

      if (_secilenAsiIdleri.isNotEmpty) {
        final asilar = _secilenAsiIdleri.map((asiId) => {'kayip_ilan_id': ilanId, 'asi_id': asiId}).toList();
        await _supabase.from('kayip_ilan_asilar').insert(asilar);
      }

      if (vektor != null && _secilenKayipKoordinat != null) await _cihazUzerindeAnalizYap(vektor, 'kayip', _secilenKayipKoordinat!, ilanId);
      _analizBilgilendirmeGoster();
      _formTemizle();
    } catch (e) { _hataMesaji(); } finally { setState(() => _yukleniyor = false); }
  }

  Future<void> _ilanKaydetBulunan() async {
    if (!_temelKontroller(_secilenBulunanKoordinat)) return;
    setState(() => _yukleniyor = true);
    try {
      final kullanici = _supabase.auth.currentUser!;
      await _supabase.rpc('bulunan_ilan_ekle', params: {
        'p_kullanici_id': kullanici.id, 'p_hayvan_turu': _secilenHayvanTuru, 'p_hayvan_rengi': _secilenHayvanRengi,
        'p_aciklama': ekstraBilgiBulduController.text.trim().isNotEmpty ? ekstraBilgiBulduController.text.trim() : null,
        'p_lat': _secilenBulunanKoordinat!.latitude, 'p_lng': _secilenBulunanKoordinat!.longitude,
      });

      final sonuc = await _supabase.from('bulunan_ilanlar').select('id').eq('kullanici_id', kullanici.id).order('created_at', ascending: false).limit(1).single();
      final String ilanId = sonuc['id'].toString();
      List<double>? vektor = await _fotograflariYukle(ilanId, 'bulunan_ilanlar');

      if (vektor != null && _secilenBulunanKoordinat != null) await _cihazUzerindeAnalizYap(vektor, 'bulunan', _secilenBulunanKoordinat!, ilanId);
      _analizBilgilendirmeGoster();
      _formTemizle();
    } catch (e) { _hataMesaji(); } finally { setState(() => _yukleniyor = false); }
  }

  Future<void> _ilanKaydetSahiplendirme() async {
    if (!_temelKontroller(_secilenSahiplendirmeKoordinat)) return;
    setState(() => _yukleniyor = true);
    try {
      final user = _supabase.auth.currentUser!;
      await _supabase.rpc('sahiplendirme_ilan_ekle', params: {
        'p_kullanici_id': user.id, 'p_hayvan_adi': hayvanAdController.text.trim().isNotEmpty ? hayvanAdController.text.trim() : "İsimsiz",
        'p_hayvan_turu': _secilenHayvanTuru, 'p_hayvan_rengi': _secilenHayvanRengi, 'p_hayvan_cinsiyeti': cinsiyet, 'p_cipi_var_mi': cipli,
        'p_kisir_mi': kisirMi, 'p_kisirlastirma_sarti': kisirlastirmaSarti, 'p_aliskanliklar': aliskanlikController.text.trim(),
        'p_aciklama': ekstraBilgiController.text.trim(), 'p_lat': _secilenSahiplendirmeKoordinat!.latitude, 'p_lng': _secilenSahiplendirmeKoordinat!.longitude,
      });
      final inserted = await _supabase.from('sahiplendirme_ilanlar').select('id').eq('kullanici_id', user.id).order('created_at', ascending: false).limit(1).single();
      final ilanId = inserted['id'];
      if (_secilenAsiIdleri.isNotEmpty) {
        final asilar = _secilenAsiIdleri.map((id) => { 'sahiplendirme_ilan_id': ilanId, 'asi_id': id }).toList();
        await _supabase.from('sahiplendirme_ilan_asilar').insert(asilar);
      }
      await _fotograflariYukle(ilanId, 'sahiplendirme_ilanlar');
      _analizBilgilendirmeGoster();
      _formTemizle();
    } catch (e) { _hataMesaji(); } finally { if (mounted) setState(() => _yukleniyor = false); }
  }

  void _hataMesaji() { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hata oluştu.'), backgroundColor: Colors.red)); }

  void _analizBilgilendirmeGoster() {
    String mesajIcerigi = "";
    if (_secilenIlanTipi == IlanTipi.kayip) {
      mesajIcerigi = "İlanınız yüklendi. Yapay zeka analizimiz tamamlandığında uygun eşleşmeleri 'Bildirimler' sayfasından görüntüleyebilirsiniz.";
    } else if (_secilenIlanTipi == IlanTipi.bulunan) {
      mesajIcerigi = "İlanınız yüklendi. Bulduğunuz hayvanı sistemdeki bir kayıp ilanı ile eşleştirdiğimizde, bu bildirim doğrudan kayıp ilan sahibine gönderilecektir. İlan sahibi sizinle arama veya mesaj yoluyla iletişime geçebilir.";
    } else {
      mesajIcerigi = "İlanınız başarıyla kaydedildi.";
    }
    showDialog(context: context, builder: (BuildContext context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Yapay Zeka Analizi 🧬", style: TextStyle(color: Color(0xFF002D72), fontWeight: FontWeight.bold)),
        content: Text(mesajIcerigi, style: const TextStyle(fontSize: 14)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("TAMAM", style: TextStyle(color: Color(0xFF002D72), fontWeight: FontWeight.bold)))],
      );
    });
  }

  void _formTemizle({bool resetAll = true}) {
    hayvanAdController.clear(); ekstraBilgiController.clear(); ekstraBilgiBulduController.clear(); aliskanlikController.clear(); kayipKonumController.clear(); bulunanKonumController.clear(); sahiplendirmeKonumController.clear();
    if (resetAll) {
      setState(() {
        _secilenHayvanTuru = null; _secilenHayvanRengi = null; _secilenKayipKoordinat = null; _secilenBulunanKoordinat = null; _secilenSahiplendirmeKoordinat = null; cinsiyet = 'Dişi'; cipli = false; kisirMi = false; kisirlastirmaSarti = false; secilenFotograflar.clear(); _mevcutAsiSecenekleri = []; _secilenAsiIdleri.clear();
      });
    }
  }

  Widget _buildPhotoTipMessage() {
    if (_secilenIlanTipi == IlanTipi.sahiplendirme) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(top: 15, bottom: 5), decoration: BoxDecoration(color: zeytinYesili.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: zeytinYesili)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.lightbulb_outline, color: zeytinYesili, size: 24), const SizedBox(width: 8), Expanded(child: Text('Hayvanın farklı açılardan ve belirgin özelliklerinin olduğu fotoğraflarını yüklemek, yapay zeka destekli arama sisteminde bulunma ihtimalini önemli ölçüde artırır. Yüzünün net göründüğü fotoğraflar tercih edilmelidir.', style: TextStyle(fontSize: 13, color: gri.withOpacity(0.8), height: 1.3)))]),
    );
  }

  @override
  Widget build(BuildContext context) {
    String altMetin; String butonMetni;
    switch (_secilenIlanTipi) {
      case IlanTipi.kayip: altMetin = 'Kayıp ilanı oluştur ve sevimli dostumuzu bulalım'; butonMetni = 'İlanı Paylaş'; break;
      case IlanTipi.bulunan: altMetin = 'Bulduğun hayvanı ilan et ve sahibine kavuştur'; butonMetni = 'Bulduğumu Bildir'; break;
      case IlanTipi.sahiplendirme: altMetin = 'Yeni bir yuva arayan dostumuz için ilan oluştur'; butonMetni = 'Sahiplendir'; break;
    }

    return Scaffold(
      backgroundColor: arkaPlan,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
              decoration: BoxDecoration(color: zeytinYesili, borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          key: _keyBaslik,
                          child: Text('Hoşgeldin ${getFormattedUserName()} 🐾', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                        const SizedBox(height: 8),
                        Text(altMetin, style: const TextStyle(fontSize: 13, color: Colors.white70)),
                      ],
                    ),
                  ),
                  // --- MÜHENDİSLİK DOKUNUŞU: İKONLAR KESİN SINIRLARLA İZOLE EDİLDİ --- ✅
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        key: _keyBilgiButonu,
                        width: 45,
                        height: 45,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.info_outline, color: Colors.white, size: 28),
                          onPressed: () => _egitimiBaslat(zorla: true),
                        ),
                      ),
                      const SizedBox(width: 12), // Fiziksel ve aşılmaz bir duvar!
                      if (Supabase.instance.client.auth.currentUser != null)
                        Container(
                          key: _keyBildirimler,
                          width: 45,
                          height: 45,
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                          child: StreamBuilder<List<Map<String, dynamic>>>(
                            stream: Supabase.instance.client.from('bildirimler').stream(primaryKey: ['id']).eq('kullanici_id', Supabase.instance.client.auth.currentUser!.id),
                            builder: (context, sosyalSnapshot) {
                              return StreamBuilder<List<Map<String, dynamic>>>(
                                stream: Supabase.instance.client.from('eslesmeler').stream(primaryKey: ['id']).eq('kontrol_edildi', false).asyncMap((tumEslesmeler) async {
                                  final benimIlanlarim = await Supabase.instance.client.from('kayip_ilanlar').select('id').eq('kullanici_id', Supabase.instance.client.auth.currentUser!.id);
                                  final benimIdSetim = benimIlanlarim.map((e) => e['id'].toString()).toSet();
                                  return tumEslesmeler.where((e) => benimIdSetim.contains(e['kayip_ilan_id'].toString())).toList();
                                }),
                                builder: (context, eslesmeSnapshot) {
                                  int toplamBildirim = 0;
                                  if (sosyalSnapshot.hasData) toplamBildirim += sosyalSnapshot.data!.where((b) => b['goruldu'] == false).length;
                                  if (eslesmeSnapshot.hasData) {
                                    final okunmamisEslesmeler = eslesmeSnapshot.data!;
                                    final benzersizBasliklar = okunmamisEslesmeler.map((e) => e['kayip_ilan_id'].toString()).toSet();
                                    toplamBildirim += benzersizBasliklar.length;
                                  }
                                  return Stack(
                                    clipBehavior: Clip.none,
                                    alignment: Alignment.center,
                                    children: [
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.notifications_active_outlined, color: Colors.white, size: 26),
                                        onPressed: () async {
                                          await Navigator.push(context, MaterialPageRoute(builder: (context) => const BildirimlerSayfasi(varsayilanTab: 0)));
                                          if (mounted) setState(() {});
                                        },
                                      ),
                                      if (toplamBildirim > 0)
                                        Positioned(
                                          right: -2, top: -2,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(color: turuncuPastel, shape: BoxShape.circle),
                                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                            child: Center(child: Text(toplamBildirim > 9 ? '9+' : '$toplamBildirim', style: TextStyle(color: koyuMavi, fontSize: 10, fontWeight: FontWeight.bold))),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              key: _keySekmeler,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Container(
                decoration: BoxDecoration(color: beyaz, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: gri.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 2))]),
                child: Row(
                  children: [
                    _buildTabButton('Kayıp', Icons.pets, IlanTipi.kayip),
                    Container(width: 1, height: 30, color: gri.withOpacity(0.3)),
                    _buildTabButton('Bulunan', Icons.search, IlanTipi.bulunan),
                    Container(width: 1, height: 30, color: gri.withOpacity(0.3)),
                    _buildTabButton('Sahiplendir', Icons.volunteer_activism, IlanTipi.sahiplendirme),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(color: beyaz, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: gri.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 2))]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SingleChildScrollView(
                    controller: _formScrollController,
                    padding: const EdgeInsets.all(20),
                    child: _buildFormContent(butonMetni),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
      bottomNavigationBar: Stack(
        clipBehavior: Clip.none,
        children: [
          SharedBottomNavBar(currentIndex: 2, turuncuPastel: turuncuPastel, gri: gri, beyaz: beyaz),
          Positioned.fill(
            child: IgnorePointer(
              child: Row(
                children: [
                  Expanded(child: Container(key: _keyNavAkis, color: Colors.transparent)),
                  Expanded(child: Container(key: _keyNavHarita, color: Colors.transparent)),
                  Expanded(child: Container(color: Colors.transparent)), // Ana Ekran
                  Expanded(child: Container(key: _keyNavIlanlar, color: Colors.transparent)),
                  Expanded(child: Container(key: _keyNavProfil, color: Colors.transparent)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String text, IconData icon, IlanTipi tip) {
    final bool isSelected = _secilenIlanTipi == tip;
    return Expanded(
      child: InkWell(
        onTap: () { setState(() { _secilenIlanTipi = tip; _formTemizle(resetAll: true); }); },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(color: isSelected ? turuncuPastel : beyaz, borderRadius: BorderRadius.circular(20)),
          child: Column(children: [Icon(icon, color: isSelected ? beyaz : gri, size: 24), const SizedBox(height: 4), Text(text, style: TextStyle(color: isSelected ? beyaz : zeytinYesili, fontWeight: FontWeight.bold, fontSize: 11))]),
        ),
      ),
    );
  }

  Widget _buildFormContent(String butonMetni) {
    switch (_secilenIlanTipi) {
      case IlanTipi.kayip: return buildKayipIlanForm(butonMetni);
      case IlanTipi.bulunan: return buildBulunanForm(butonMetni);
      case IlanTipi.sahiplendirme: return buildSahiplendirmeForm(butonMetni);
    }
  }

  Widget buildKayipIlanForm(String butonMetni) {
    return Column(children: [
      _buildTextField(controller: hayvanAdController, label: 'Hayvan Adı', icon: Icons.pets),
      const SizedBox(height: 15),
      Container(key: _keyFotoYukleme, child: _buildPhotoUploadSection()),
      const SizedBox(height: 15),
      _buildHayvanTuruSection(),
      const SizedBox(height: 15),
      _buildHayvanRengiSection(),
      const SizedBox(height: 15),
      _buildAsiBilgileriSection(),
      const SizedBox(height: 15),
      _buildLocationField(controller: kayipKonumController, tip: IlanTipi.kayip, fieldKey: _keyKonum),
      const SizedBox(height: 15),
      Row(children: [
        Expanded(child: _buildChoiceChip(label: 'Cinsiyet', options: ['Dişi', 'Erkek'], selected: cinsiyet, onSelected: (val) => setState(() => cinsiyet = val))),
        const SizedBox(width: 15),
        Expanded(child: _buildSwitchOption(label: 'Çipli mi?', value: cipli, onChanged: (val) => setState(() => cipli = val))),
      ]),
      const SizedBox(height: 15),
      _buildTextField(controller: ekstraBilgiController, label: 'Ekstra Bilgi', icon: Icons.info, maxLines: 3, fieldKey: _keyEkstraBilgi),
      const SizedBox(height: 25),
      _buildActionButton(text: _yukleniyor ? 'Yükleniyor...' : butonMetni, onPressed: _yukleniyor ? null : _ilanKaydetKayip),
    ]);
  }

  Widget buildBulunanForm(String butonMetni) {
    return Column(children: [
      Container(key: _keyFotoYukleme, child: _buildPhotoUploadSection()),
      const SizedBox(height: 15),
      _buildHayvanTuruSection(),
      const SizedBox(height: 15),
      _buildHayvanRengiSection(),
      const SizedBox(height: 15),
      _buildLocationField(controller: bulunanKonumController, tip: IlanTipi.bulunan, fieldKey: _keyKonum),
      const SizedBox(height: 15),
      _buildTextField(controller: ekstraBilgiBulduController, label: 'Ekstra Bilgi', icon: Icons.info, maxLines: 3, fieldKey: _keyEkstraBilgi),
      const SizedBox(height: 25),
      _buildActionButton(text: _yukleniyor ? 'Yükleniyor...' : butonMetni, onPressed: _yukleniyor ? null : _ilanKaydetBulunan),
    ]);
  }

  Widget buildSahiplendirmeForm(String butonMetni) {
    return Column(children: [
      _buildTextField(controller: hayvanAdController, label: 'Hayvan Adı', icon: Icons.pets),
      const SizedBox(height: 15),
      Container(key: _keyFotoYukleme, child: _buildPhotoUploadSection()),
      const SizedBox(height: 15),
      _buildHayvanTuruSection(),
      const SizedBox(height: 15),
      _buildHayvanRengiSection(),
      const SizedBox(height: 15),
      _buildAsiBilgileriSection(),
      const SizedBox(height: 15),
      _buildLocationField(controller: sahiplendirmeKonumController, tip: IlanTipi.sahiplendirme, fieldKey: _keyKonum),
      const SizedBox(height: 15),
      Row(children: [
        Expanded(child: _buildChoiceChip(label: 'Cinsiyet', options: ['Dişi', 'Erkek'], selected: cinsiyet, onSelected: (val) => setState(() => cinsiyet = val))),
        const SizedBox(width: 15),
        Expanded(child: _buildSwitchOption(label: 'Çipli mi?', value: cipli, onChanged: (val) => setState(() => cipli = val))),
      ]),
      const SizedBox(height: 15),
      Row(children: [
        Expanded(child: _buildSwitchOption(label: 'Kısır mı?', value: kisirMi, onChanged: (val) => setState(() => kisirMi = val))),
        const SizedBox(width: 15),
        Expanded(child: _buildSwitchOption(label: 'Kısırlaştırma Şartı', value: kisirlastirmaSarti, onChanged: (val) => setState(() => kisirlastirmaSarti = val))),
      ]),
      const SizedBox(height: 15),
      _buildTextField(controller: aliskanlikController, label: 'Özel İhtiyaçlar ve Alışkanlıklar', icon: Icons.psychology, maxLines: 2),
      const SizedBox(height: 15),
      _buildTextField(controller: ekstraBilgiController, label: 'Ekstra Bilgi', icon: Icons.info, maxLines: 3, fieldKey: _keyEkstraBilgi),
      const SizedBox(height: 25),
      _buildActionButton(text: _yukleniyor ? 'Yükleniyor...' : butonMetni, onPressed: _yukleniyor ? null : _ilanKaydetSahiplendirme),
    ]);
  }

  Widget _buildLocationField({required TextEditingController controller, required IlanTipi tip, Key? fieldKey}) {
    return Container(
      key: fieldKey,
      child: TextField(
        controller: controller, readOnly: true, onTap: () => _haritadanKonumSec(tip), maxLines: 2,
        decoration: InputDecoration(labelText: 'Konum Seç (Harita)', labelStyle: TextStyle(color: gri), prefixIcon: Icon(Icons.map, color: turuncuPastel), suffixIcon: const Icon(Icons.chevron_right), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: arkaPlan),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon, int maxLines = 1, Key? fieldKey}) {
    return Container(
        key: fieldKey,
        child: TextField(controller: controller, maxLines: maxLines, decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: gri), prefixIcon: Icon(icon, color: turuncuPastel), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: arkaPlan))
    );
  }

  Widget _buildDropdown({required String? value, required String label, required IconData icon, required List<String> items, required Function(String?) onChanged, String hintText = 'Seçim yapınız'}) {
    return DropdownButtonFormField<String>(value: value, decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: gri), prefixIcon: Icon(icon, color: turuncuPastel), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: arkaPlan, hintText: hintText), items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: onChanged);
  }

  Widget _buildChoiceChip({required String label, required List<String> options, required String selected, required Function(String) onSelected}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: zeytinYesili, fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 8),
      Container(height: 52, padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: arkaPlan, borderRadius: BorderRadius.circular(12), border: Border.all(color: gri.withOpacity(0.3))), child: Row(children: options.map((option) { final isSelected = selected == option; return Expanded(child: GestureDetector(onTap: () => onSelected(option), child: Container(margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: isSelected ? turuncuPastel : Colors.transparent, borderRadius: BorderRadius.circular(8)), child: Center(child: Text(option, style: TextStyle(color: isSelected ? beyaz : gri, fontWeight: FontWeight.bold)))))); }).toList())),
    ]);
  }

  Widget _buildSwitchOption({required String label, required bool value, required Function(bool) onChanged}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: zeytinYesili, fontWeight: FontWeight.bold, fontSize: 13)),
      const SizedBox(height: 4),
      Container(height: 45, padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: arkaPlan, borderRadius: BorderRadius.circular(12), border: Border.all(color: gri.withOpacity(0.3))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(value ? 'Evet' : 'Hayır', style: TextStyle(color: gri, fontWeight: FontWeight.bold, fontSize: 12)), Switch(value: value, onChanged: onChanged, activeColor: turuncuPastel)]))
    ]);
  }

  Widget _buildActionButton({required String text, required VoidCallback? onPressed}) {
    return SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: turuncuPastel, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: onPressed, child: _yukleniyor ? CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(beyaz)) : Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white))));
  }

  Widget _buildHayvanTuruSection() { return _buildDropdown(value: _secilenHayvanTuru, label: 'Hayvan Türü', icon: Icons.category, items: hayvanTurleri, onChanged: _hayvanTuruDegisti, hintText: 'Hayvan türünü seçin'); }
  Widget _buildHayvanRengiSection() { return _buildDropdown(value: _secilenHayvanRengi, label: 'Hayvan Rengi', icon: Icons.color_lens, items: _mevcutRenkSecenekleri, onChanged: (val) => setState(() => _secilenHayvanRengi = val), hintText: _secilenHayvanTuru == null ? 'Önce türü seçiniz' : 'Rengini seçiniz'); }

  Widget _buildAsiBilgileriSection() {
    if (_secilenHayvanTuru == null || (_secilenHayvanTuru != 'Kedi' && _secilenHayvanTuru != 'Köpek')) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Aşı Bilgileri', style: TextStyle(color: zeytinYesili, fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 8),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: arkaPlan, borderRadius: BorderRadius.circular(12), border: Border.all(color: gri.withOpacity(0.3))), child: Column(children: _mevcutAsiSecenekleri.map((asi) { final id = asi['id'] as String; return Row(children: [Checkbox(value: _secilenAsiIdleri.contains(id), onChanged: (v) => setState(() => v! ? _secilenAsiIdleri.add(id) : _secilenAsiIdleri.remove(id)), activeColor: turuncuPastel), Expanded(child: Text(asi['asi_adi']))]); }).toList())),
    ]);
  }

  Widget _buildPhotoUploadSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Hayvan Fotoğrafları (En az 1)', style: TextStyle(color: zeytinYesili, fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 8),
      SizedBox(height: 120, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: secilenFotograflar.length + 1, itemBuilder: (context, index) { if (index == secilenFotograflar.length) { return GestureDetector(onTap: _fotoCekVeyaSec, child: Container(width: 120, margin: const EdgeInsets.only(right: 10), decoration: BoxDecoration(color: arkaPlan, borderRadius: BorderRadius.circular(12), border: Border.all(color: turuncuPastel)), child: Icon(Icons.add_a_photo, color: turuncuPastel, size: 30))); } return Stack(children: [Container(width: 120, margin: const EdgeInsets.only(right: 10), child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(File(secilenFotograflar[index].path), fit: BoxFit.cover))), Positioned(right: 15, top: 5, child: GestureDetector(onTap: () => setState(() => secilenFotograflar.removeAt(index)), child: const CircleAvatar(radius: 10, backgroundColor: Colors.red, child: Icon(Icons.close, size: 12, color: Colors.white))))]); })),
      _buildPhotoTipMessage(),
    ]);
  }
}