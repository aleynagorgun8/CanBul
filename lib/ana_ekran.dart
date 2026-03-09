import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // Cihazdan fotoğraf yüklemek için
import 'package:image_cropper/image_cropper.dart'; // FOTOĞRAF KIRPMA İÇİN
import 'dart:io'; // Dosya okumak ve File nesnesi için
import 'shared_bottom_nav.dart'; // Navbar erişimi için
import 'package:supabase_flutter/supabase_flutter.dart'; // Supabase bağlantısı için
import 'package:google_maps_flutter/google_maps_flutter.dart'; // Koordinat işlemleri için
import 'konum_sec_sayfasi.dart'; // Harita sayfamız
import 'bildirimler.dart';

final supabase = Supabase.instance.client;

// İlan Tiplerini Yönetmek İçin Enum
enum IlanTipi { kayip, bulunan, sahiplendirme }

const List<String> hayvanTurleri = [
  'Kedi', 'Köpek'
];

const List<String> tumRenkler = [
  'Siyah', 'Beyaz', 'Gri', 'Kahverengi', 'Sarı', 'Çok Renkli'
];

// Hayvan türüne göre renk seçenekleri
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

  // Sayfa Durumu
  IlanTipi _secilenIlanTipi = IlanTipi.kayip; // Varsayılan: Kayıp

  // Fotoğraf İşlemleri
  List<XFile> secilenFotograflar = [];
  final ImagePicker _picker = ImagePicker();
  bool _yukleniyor = false;

  // Form Kontrolcüleri
  final TextEditingController hayvanAdController = TextEditingController();
  final TextEditingController ekstraBilgiController = TextEditingController(); // Kayıp ve Sahiplendirme için
  final TextEditingController ekstraBilgiBulduController = TextEditingController(); // Bulunan için
  final TextEditingController aliskanlikController = TextEditingController(); // Sahiplendirme özel

  // Konum kontrolcüleri
  final TextEditingController kayipKonumController = TextEditingController();
  final TextEditingController bulunanKonumController = TextEditingController();
  final TextEditingController sahiplendirmeKonumController = TextEditingController();

  // Koordinatlar
  LatLng? _secilenKayipKoordinat;
  LatLng? _secilenBulunanKoordinat;
  LatLng? _secilenSahiplendirmeKoordinat;

  // Seçmeli Alanlar
  String? _secilenHayvanTuru;
  String? _secilenHayvanRengi;
  String cinsiyet = 'Dişi';
  bool cipli = false;

  // Sahiplendirme Özel Alanlar
  bool kisirMi = false;
  bool kisirlastirmaSarti = false;

  // Listeler
  List<String> _mevcutRenkSecenekleri = [];
  List<Map<String, dynamic>> _mevcutAsiSecenekleri = [];
  List<String> _secilenAsiIdleri = [];

  String _gosterilecekAd = "";

  // Renkler
  final Color turuncuPastel = const Color(0xFFFFB74D);
  final Color zeytinYesili = const Color(0xFF558B2F);
  final Color arkaPlan = const Color(0xFFF1F8E9);
  final Color beyaz = Colors.white;
  final Color gri = const Color(0xFF9E9E9E);
  final Color koyuMavi = const Color(0xFF002D72);

  @override
  void initState() {
    super.initState();
    _ismiBelirleVeGuncelle();
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
      } catch (e) {
        print("İsim hatası: $e");
      }
    }
  }

  @override
  void dispose() {
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
    } catch (e) {
      print("Aşı hatası: $e");
    }
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

  // KIRPMA FONKSİYONU
  Future<XFile?> _resmiKirp(XFile dosya) async {
    CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: dosya.path,
      // başlıklar ve renk ayarları
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Fotoğrafı Düzenle',
          toolbarColor: zeytinYesili, // Uygulama ana rengi
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: turuncuPastel,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false, // Kullanıcı özgürce kırpabilsin
        ),
        IOSUiSettings(
          title: 'Fotoğrafı Düzenle',
        ),
      ],
    );

    if (croppedFile != null) {
      return XFile(croppedFile.path); // CroppedFile'ı XFile'a çevir
    }
    return null; // Kullanıcı iptal ederse null döner
  }
  //


  // FOTOĞRAF SEÇME FONKSİYONU
  Future<void> _fotoCekVeyaSec() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: beyaz,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
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
              title: const Text('Galeriden seç'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    if (source == ImageSource.gallery) {
      // Galeriden çoklu seçim
      final List<XFile>? fotolar = await _picker.pickMultiImage(imageQuality: 85);
      if (fotolar != null) {
        // Seçilen her fotoğrafı sırayla kırpma işlemine sokuyoruz
        for (var foto in fotolar) {
          XFile? kirpilmisFoto = await _resmiKirp(foto);
          if (kirpilmisFoto != null) {
            setState(() => secilenFotograflar.add(kirpilmisFoto));
          }
        }
      }
    } else {
      // Kameradan tekli çekim
      final XFile? foto = await _picker.pickImage(source: source, imageQuality: 85);
      if (foto != null) {
        XFile? kirpilmisFoto = await _resmiKirp(foto);
        if (kirpilmisFoto != null) {
          setState(() => secilenFotograflar.add(kirpilmisFoto));
        }
      }
    }
  }

  Future<void> _fotograflariYukle(String ilanId, String tabloAdi) async {
    print("📸 FOTOĞRAF YÜKLEME SÜRECİ BAŞLADI...");
    print("👉 Hedef Tablo: $tabloAdi | İlan ID: $ilanId");

    // İlan Tipi Belirleme
    String klasor = 'diger';
    String ilanTipi = 'belirsiz';

    if (tabloAdi == 'kayip_ilanlar') {
      klasor = 'kayip';
      ilanTipi = 'kayip';
    } else if (tabloAdi == 'bulunan_ilanlar') {
      klasor = 'bulunan';
      ilanTipi = 'bulunan';
    } else if (tabloAdi == 'sahiplendirme_ilanlar') {
      klasor = 'sahiplendirme';
      ilanTipi = 'sahiplendirme';
    }

    // Seçilen her fotoğraf için döngü
    for (int i = 0; i < secilenFotograflar.length; i++) {
      try {
        final foto = secilenFotograflar[i];
        final bytes = await File(foto.path).readAsBytes();

        // Dosya uzantısını al (jpg, png vs)
        String ext = foto.name.split('.').last.toLowerCase();
        if (ext == 'jpg') ext = 'jpeg';

        // Storage için dosya yolu oluştur
        final dosyaYolu = '$klasor/$ilanId/${DateTime.now().millisecondsSinceEpoch}_$i.$ext';

        // Storage'a Yükle
        await _supabase.storage.from('hayvan_fotograflari').uploadBinary(
          dosyaYolu,
          bytes,
          fileOptions: FileOptions(upsert: false, contentType: 'image/$ext'),
        );

        // Public URL'i al
        final publicUrl = _supabase.storage.from('hayvan_fotograflari').getPublicUrl(dosyaYolu);
        print("✅ Storage Yüklemesi Başarılı! URL: $publicUrl");

        //  Veritabanına Kaydet
        print("💾 Tabloya yazılıyor... (Tip: $ilanTipi)");

        await _supabase.from('ilan_fotograflari').insert({
          'ilan_id': ilanId,       // UUID formatında ID
          'ilan_tipi': ilanTipi,   // 'sahiplendirme', 'kayip' vs.
          'foto_url': publicUrl,   // Resmin linki
        });

        print("🎉 Veritabanı Kaydı TAMAMLANDI!");

      } catch (e) {
        print('❌ HATA OLUŞTU ($i. fotoğraf): $e');
        // Kullanıcıya hata mesajı gösterelim
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fotoğraf yüklenemedi: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _haritadanKonumSec(IlanTipi tip) async {
    final LatLng? result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const KonumSecSayfasi()),
    );

    if (result != null) {
      setState(() {
        final text = "Haritadan Seçildi ✅\n(${result.latitude.toStringAsFixed(5)}, ${result.longitude.toStringAsFixed(5)})";
        if (tip == IlanTipi.kayip) {
          _secilenKayipKoordinat = result;
          kayipKonumController.text = text;
        } else if (tip == IlanTipi.bulunan) {
          _secilenBulunanKoordinat = result;
          bulunanKonumController.text = text;
        } else {
          _secilenSahiplendirmeKoordinat = result;
          sahiplendirmeKonumController.text = text;
        }
      });
    }
  }

  // --- KAYDETME FONKSİYONLARI ---

  bool _temelKontroller(LatLng? konum) {
    if (secilenFotograflar.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen en az bir fotoğraf yükleyin.'), backgroundColor: Colors.orange));
      return false;
    }
    if (_secilenHayvanTuru == null || _secilenHayvanRengi == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen hayvan türünü ve rengini seçin.'), backgroundColor: Colors.orange));
      return false;
    }
    if (konum == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen haritadan konumu seçin.'), backgroundColor: Colors.orange));
      return false;
    }
    if (_supabase.auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Giriş yapmalısınız.'), backgroundColor: Colors.red));
      return false;
    }
    return true;
  }

  Future<void> _ilanKaydetKayip() async {
    if (!_temelKontroller(_secilenKayipKoordinat)) return;
    setState(() => _yukleniyor = true);

    try {
      final user = _supabase.auth.currentUser!;
      //  coğrafi veri kaydı
      await _supabase.rpc('kayip_ilan_ekle', params: {
        'p_kullanici_id': user.id,
        'p_hayvan_adi': hayvanAdController.text.trim().isNotEmpty ? hayvanAdController.text.trim() : "İsimsiz",
        'p_hayvan_turu': _secilenHayvanTuru,
        'p_hayvan_rengi': _secilenHayvanRengi,
        'p_hayvan_cinsiyeti': cinsiyet,
        'p_cipi_var_mi': cipli,
        'p_aciklama': ekstraBilgiController.text.trim().isNotEmpty ? ekstraBilgiController.text.trim() : null,
        'p_lat': _secilenKayipKoordinat!.latitude,
        'p_lng': _secilenKayipKoordinat!.longitude,
      });

      // ID'yi al
      final inserted = await _supabase.from('kayip_ilanlar')
          .select('id').eq('kullanici_id', user.id).order('created_at', ascending: false).limit(1).single();

      final ilanId = inserted['id'];

      // Aşıları ekle
      if (_secilenAsiIdleri.isNotEmpty) {
        final asilar = _secilenAsiIdleri.map((id) => {'kayip_ilan_id': ilanId, 'asi_id': id}).toList();
        await _supabase.from('kayip_ilan_asilar').insert(asilar);
      }

      await _fotograflariYukle(ilanId, 'kayip_ilanlar');

      _basariliMesaj('Kayıp İlanı');
    } catch (e) {
      _hataMesaji(e.toString());
    } finally {
      setState(() => _yukleniyor = false);
    }
  }

  Future<void> _ilanKaydetBulunan() async {
    if (!_temelKontroller(_secilenBulunanKoordinat)) return;
    setState(() => _yukleniyor = true);

    try {
      final user = _supabase.auth.currentUser!;
      await _supabase.rpc('bulunan_ilan_ekle', params: {
        'p_kullanici_id': user.id,
        'p_hayvan_turu': _secilenHayvanTuru,
        'p_hayvan_rengi': _secilenHayvanRengi,
        'p_aciklama': ekstraBilgiBulduController.text.trim().isNotEmpty ? ekstraBilgiBulduController.text.trim() : null,
        'p_lat': _secilenBulunanKoordinat!.latitude,
        'p_lng': _secilenBulunanKoordinat!.longitude,
      });

      final inserted = await _supabase.from('bulunan_ilanlar')
          .select('id').eq('kullanici_id', user.id).order('created_at', ascending: false).limit(1).single();

      await _fotograflariYukle(inserted['id'], 'bulunan_ilanlar');
      _basariliMesaj('Bulunan İlanı');
    } catch (e) {
      _hataMesaji(e.toString());
    } finally {
      setState(() => _yukleniyor = false);
    }
  }

  Future<void> _ilanKaydetSahiplendirme() async {
    // Temel kontroller
    if (!_temelKontroller(_secilenSahiplendirmeKoordinat)) return;

    setState(() => _yukleniyor = true);

    try {
      final user = _supabase.auth.currentUser!;
      print("🚀 Sahiplendirme İlanı Oluşturuluyor...");

      // İlanı Oluştur (RPC Çağrısı)
      await _supabase.rpc('sahiplendirme_ilan_ekle', params: {
        'p_kullanici_id': user.id,
        'p_hayvan_adi': hayvanAdController.text.trim().isNotEmpty ? hayvanAdController.text.trim() : "İsimsiz",
        'p_hayvan_turu': _secilenHayvanTuru,
        'p_hayvan_rengi': _secilenHayvanRengi,
        'p_hayvan_cinsiyeti': cinsiyet,
        'p_cipi_var_mi': cipli,
        'p_kisir_mi': kisirMi,
        'p_kisirlastirma_sarti': kisirlastirmaSarti,
        'p_aliskanliklar': aliskanlikController.text.trim(),
        'p_aciklama': ekstraBilgiController.text.trim(),
        'p_lat': _secilenSahiplendirmeKoordinat!.latitude,
        'p_lng': _secilenSahiplendirmeKoordinat!.longitude,
      });

      print("✅ İlan verisi SQL'e gönderildi.");

      // Oluşan İlanın ID'sini Çek
      // (Kullanıcının son eklediği ilanı buluyoruz)
      final inserted = await _supabase.from('sahiplendirme_ilanlar')
          .select('id')
          .eq('kullanici_id', user.id)
          .order('created_at', ascending: false)
          .limit(1)
          .single();

      final ilanId = inserted['id'];
      print("🆔 İlan ID Alındı: $ilanId");

      // Aşıları Ekle (Varsa)
      if (_secilenAsiIdleri.isNotEmpty) {
        final asilar = _secilenAsiIdleri.map((id) => {
          'sahiplendirme_ilan_id': ilanId,
          'asi_id': id
        }).toList();
        await _supabase.from('sahiplendirme_ilan_asilar').insert(asilar);
      }

      // Fotoğrafları Yükle ve Tabloya İşle

      await _fotograflariYukle(ilanId, 'sahiplendirme_ilanlar');

      _basariliMesaj('Sahiplendirme İlanı');

    } catch (e) {
      _hataMesaji(e.toString());
    } finally {
      if (mounted) {
        setState(() => _yukleniyor = false);
      }
    }
  }
  void _basariliMesaj(String tur) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$tur başarıyla kaydedildi! 🦁'), backgroundColor: zeytinYesili, behavior: SnackBarBehavior.floating),
    );
    _formTemizle();
  }

  void _hataMesaji(String hata) {
    print("Hata: $hata");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Hata oluştu. Lütfen tekrar dene.'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
    );
  }

  void _formTemizle({bool resetAll = true}) {
    hayvanAdController.clear();
    ekstraBilgiController.clear();
    ekstraBilgiBulduController.clear();
    aliskanlikController.clear();
    kayipKonumController.clear();
    bulunanKonumController.clear();
    sahiplendirmeKonumController.clear();

    if (resetAll) {
      setState(() {
        _secilenHayvanTuru = null;
        _secilenHayvanRengi = null;
        _secilenKayipKoordinat = null;
        _secilenBulunanKoordinat = null;
        _secilenSahiplendirmeKoordinat = null;
        cinsiyet = 'Dişi';
        cipli = false;
        kisirMi = false;
        kisirlastirmaSarti = false;
        secilenFotograflar.clear();
        _mevcutAsiSecenekleri = [];
        _secilenAsiIdleri.clear();
      });
    }
  }

  // FOTOĞRAF UYARI METODU
  Widget _buildPhotoTipMessage() {
    // Mesaj sadece Kayıp ve Bulunan ilan tiplerinde gösterilecek
    if (_secilenIlanTipi != IlanTipi.kayip && _secilenIlanTipi != IlanTipi.bulunan) {
      return const SizedBox.shrink(); // Sahiplendirme ise boş döner
    }

    final String mesaj = _secilenIlanTipi == IlanTipi.kayip
        ? 'Dostunuzun **farklı açılardan ve belirgin özelliklerinin** olduğu fotoğraflarını yüklemek, yapay zeka destekli arama sisteminde bulunma ihtimalini **önemli ölçüde artırır**.'
        : 'Bulduğunuz hayvanın **farklı açılardan ve belirgin özelliklerinin** olduğu fotoğraflarını yüklemek, sahibinin onu tanımasını ve yapay zeka ile eşleşmesini kolaylaştırır.';

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 15, bottom: 5),
      decoration: BoxDecoration(
        color: zeytinYesili.withOpacity(0.1), // Hafif yeşil arka plan
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: zeytinYesili),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, color: zeytinYesili, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'İpucu: ', style: TextStyle(fontWeight: FontWeight.bold, color:zeytinYesili)),
                  TextSpan(text: mesaj.replaceAll('**', ''), style: TextStyle(color: gri.withOpacity(0.8), height: 1.3)),
                ],
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }



  @override
  @override
  Widget build(BuildContext context) {
    String altMetin;
    String butonMetni;

    switch (_secilenIlanTipi) {
      case IlanTipi.kayip:
        altMetin = 'Kayıp ilanı oluştur ve sevimli dostumuzu bulalım';
        butonMetni = 'İlanı Paylaş';
        break;
      case IlanTipi.bulunan:
        altMetin = 'Bulduğun hayvanı ilan et ve sahibine kavuştur';
        butonMetni = 'Bulduğumu Bildir';
        break;
      case IlanTipi.sahiplendirme:
        altMetin = 'Yeni bir yuva arayan dostumuz için ilan oluştur';
        butonMetni = 'Sahiplendir';
        break;
    }

    return Scaffold(
      backgroundColor: arkaPlan,
      body: SafeArea(
        child: Column(
          children: [
            // ÜST BAŞLIK ALANI
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
              decoration: BoxDecoration(
                color: zeytinYesili,
                borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hoşgeldin ${getFormattedUserName()} 🐾',
                          style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(altMetin,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.white70)),
                      ],
                    ),
                  ),


                  // SAĞ TARAFTAKİ BİLDİRİM İKONU
                  if (Supabase.instance.client.auth.currentUser != null)
                    Container(
                      margin: const EdgeInsets.only(left: 10, top: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: StreamBuilder<List<Map<String, dynamic>>>(
                        // Canlı Dinleme (Realtime)
                        stream: Supabase.instance.client
                            .from('bildirimler')
                            .stream(primaryKey: ['id'])
                            .eq('kullanici_id', Supabase.instance.client.auth.currentUser!.id)
                            .order('created_at', ascending: false),
                        builder: (context, snapshot) {
                          int bildirimSayisi = 0;

                          if (snapshot.hasData && snapshot.data != null) {
                            // Okunmamışları filtrele (goruldu == false)
                            final okunmamislar = snapshot.data!
                                .where((b) => b['goruldu'] == false)
                                .toList();
                            bildirimSayisi = okunmamislar.length;
                          }

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              IconButton(
                                icon: const Icon(
                                    Icons.notifications_active_outlined,
                                    color: Colors.white),
                                onPressed: () {

                                  // Veritabanı değiştiği an burası otomatik güncellenir.
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                      const BildirimlerSayfasi(),
                                    ),
                                  );
                                },
                              ),

                              // Bildirim Sayısı Rozeti
                              if (bildirimSayisi > 0)
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFFB74D),
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '$bildirimSayisi',
                                        style: const TextStyle(
                                          color: Color(0xFF002D72),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),

                ],
              ),
            ),

            const SizedBox(height: 20),

            // 3'LÜ SEÇİM BUTONLARI
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: beyaz,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: gri.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: Row(
                  children: [
                    _buildTabButton('Kayıp', Icons.pets, IlanTipi.kayip),
                    Container(width: 1, height: 30, color: gri.withOpacity(0.3)),
                    _buildTabButton('Bulunan', Icons.search, IlanTipi.bulunan),
                    Container(width: 1, height: 30, color: gri.withOpacity(0.3)),
                    _buildTabButton('Sahiplendir', Icons.volunteer_activism,
                        IlanTipi.sahiplendirme),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            //  FORM ALANI
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: beyaz,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: gri.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SingleChildScrollView(
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
      bottomNavigationBar: SharedBottomNavBar(
          currentIndex: 2, turuncuPastel: turuncuPastel, gri: gri, beyaz: beyaz),
    );
  }

  Widget _buildTabButton(String text, IconData icon, IlanTipi tip) {
    final bool isSelected = _secilenIlanTipi == tip;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _secilenIlanTipi = tip;
            _formTemizle(resetAll: true);
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? turuncuPastel : beyaz,
            borderRadius: BorderRadius.circular(20), // Köşeleri yuvarla
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? beyaz : gri, size: 24),
              const SizedBox(height: 4),
              Text(text, style: TextStyle(color: isSelected ? beyaz : zeytinYesili, fontWeight: FontWeight.bold, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormContent(String butonMetni) {
    switch (_secilenIlanTipi) {
      case IlanTipi.kayip:
        return buildKayipIlanForm(butonMetni);
      case IlanTipi.bulunan:
        return buildBulunanForm(butonMetni);
      case IlanTipi.sahiplendirme:
        return buildSahiplendirmeForm(butonMetni);
    }
  }

  // --- FORM WIDGETLARI ---

  Widget buildKayipIlanForm(String butonMetni) {
    return Column(
      children: [
        _buildTextField(controller: hayvanAdController, label: 'Hayvan Adı', icon: Icons.pets),
        const SizedBox(height: 15),
        _buildPhotoUploadSection(),
        const SizedBox(height: 15),
        _buildHayvanTuruSection(),
        const SizedBox(height: 15),
        _buildHayvanRengiSection(),
        const SizedBox(height: 15),
        _buildAsiBilgileriSection(),
        const SizedBox(height: 15),
        _buildLocationField(controller: kayipKonumController, tip: IlanTipi.kayip),
        const SizedBox(height: 15),
        Row(children: [
          Expanded(child: _buildChoiceChip(label: 'Cinsiyet', options: ['Dişi', 'Erkek'], selected: cinsiyet, onSelected: (val) => setState(() => cinsiyet = val))),
          const SizedBox(width: 15),
          Expanded(child: _buildSwitchOption(label: 'Çipli mi?', value: cipli, onChanged: (val) => setState(() => cipli = val))),
        ]),
        const SizedBox(height: 15),
        _buildTextField(controller: ekstraBilgiController, label: 'Ekstra Bilgi', icon: Icons.info, maxLines: 3),
        const SizedBox(height: 25),
        _buildActionButton(text: _yukleniyor ? 'Yükleniyor...' : butonMetni, onPressed: _yukleniyor ? null : _ilanKaydetKayip),
      ],
    );
  }

  Widget buildBulunanForm(String butonMetni) {
    return Column(
      children: [
        _buildPhotoUploadSection(),
        const SizedBox(height: 15),
        _buildHayvanTuruSection(),
        const SizedBox(height: 15),
        _buildHayvanRengiSection(),
        const SizedBox(height: 15),
        _buildLocationField(controller: bulunanKonumController, tip: IlanTipi.bulunan),
        const SizedBox(height: 15),
        _buildTextField(controller: ekstraBilgiBulduController, label: 'Ekstra Bilgi', icon: Icons.info, maxLines: 3),
        const SizedBox(height: 25),
        _buildActionButton(text: _yukleniyor ? 'Yükleniyor...' : butonMetni, onPressed: _yukleniyor ? null : _ilanKaydetBulunan),
      ],
    );
  }

  Widget buildSahiplendirmeForm(String butonMetni) {
    return Column(
      children: [
        _buildTextField(controller: hayvanAdController, label: 'Hayvan Adı', icon: Icons.pets),
        const SizedBox(height: 15),
        _buildPhotoUploadSection(),
        const SizedBox(height: 15),
        _buildHayvanTuruSection(),
        const SizedBox(height: 15),
        _buildHayvanRengiSection(),
        const SizedBox(height: 15),
        _buildAsiBilgileriSection(),
        const SizedBox(height: 15),
        _buildLocationField(controller: sahiplendirmeKonumController, tip: IlanTipi.sahiplendirme),
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
        _buildTextField(controller: ekstraBilgiController, label: 'Ekstra Bilgi', icon: Icons.info, maxLines: 3),
        const SizedBox(height: 25),
        _buildActionButton(text: _yukleniyor ? 'Yükleniyor...' : butonMetni, onPressed: _yukleniyor ? null : _ilanKaydetSahiplendirme),
      ],
    );
  }

  // ORTAK UI WIDGETLARI

  Widget _buildLocationField({required TextEditingController controller, required IlanTipi tip}) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: () => _haritadanKonumSec(tip),
      maxLines: 2,
      decoration: InputDecoration(
        labelText: 'Konum Seç (Harita)',
        labelStyle: TextStyle(color: gri),
        prefixIcon: Icon(Icons.map, color: turuncuPastel),
        suffixIcon: const Icon(Icons.chevron_right),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: gri.withOpacity(0.3))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: turuncuPastel)),
        filled: true,
        fillColor: arkaPlan,
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon, int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: gri),
        prefixIcon: Icon(icon, color: turuncuPastel),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: gri.withOpacity(0.3))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: turuncuPastel)),
        filled: true, fillColor: arkaPlan,
      ),
    );
  }

  Widget _buildDropdown({required String? value, required String label, required IconData icon, required List<String> items, required Function(String?) onChanged, String hintText = 'Seçim yapınız'}) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label, labelStyle: TextStyle(color: gri), prefixIcon: Icon(icon, color: turuncuPastel),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: gri.withOpacity(0.3))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: turuncuPastel)),
        filled: true, fillColor: arkaPlan, hintText: hintText,
      ),
      isExpanded: true,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildChoiceChip({required String label, required List<String> options, required String selected, required Function(String) onSelected}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: zeytinYesili, fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 8),
      Container(
        height: 52, padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: arkaPlan, borderRadius: BorderRadius.circular(12), border: Border.all(color: gri.withOpacity(0.3))),
        child: Row(children: options.map((option) {
          final isSelected = selected == option;
          return Expanded(child: GestureDetector(
            onTap: () => onSelected(option),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(color: isSelected ? turuncuPastel : Colors.transparent, borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text(option, style: TextStyle(color: isSelected ? beyaz : gri, fontWeight: FontWeight.bold))),
            ),
          ));
        }).toList()),
      ),
    ]);
  }

  Widget _buildSwitchOption({required String label, required bool value, required Function(bool) onChanged}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: zeytinYesili, fontWeight: FontWeight.bold, fontSize: 13)),
      const SizedBox(height: 4),
      Container(
        height: 45, padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: arkaPlan, borderRadius: BorderRadius.circular(12), border: Border.all(color: gri.withOpacity(0.3))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(value ? 'Evet' : 'Hayır', style: TextStyle(color: gri, fontWeight: FontWeight.bold, fontSize: 12)),
          Switch(value: value, onChanged: onChanged, activeColor: turuncuPastel),
        ]),
      ),
    ]);
  }

  Widget _buildActionButton({required String text, required VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity, height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: turuncuPastel, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        onPressed: onPressed,
        child: _yukleniyor ? CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(beyaz)) : Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  Widget _buildHayvanTuruSection() {
    return _buildDropdown(value: _secilenHayvanTuru, label: 'Hayvan Türü', icon: Icons.category, items: hayvanTurleri, onChanged: _hayvanTuruDegisti, hintText: 'Hayvan türünü seçin');
  }

  Widget _buildHayvanRengiSection() {
    return _buildDropdown(value: _secilenHayvanRengi, label: 'Hayvan Rengi', icon: Icons.color_lens, items: _mevcutRenkSecenekleri, onChanged: (val) => setState(() => _secilenHayvanRengi = val), hintText: _secilenHayvanTuru == null ? 'Önce türü seçiniz' : 'Rengini seçiniz');
  }

  Widget _buildAsiBilgileriSection() {
    if (_secilenHayvanTuru == null || (_secilenHayvanTuru != 'Kedi' && _secilenHayvanTuru != 'Köpek')) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Aşı Bilgileri', style: TextStyle(color: zeytinYesili, fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: arkaPlan, borderRadius: BorderRadius.circular(12), border: Border.all(color: gri.withOpacity(0.3))),
        child: Column(children: _mevcutAsiSecenekleri.map((asi) {
          final id = asi['id'] as String;
          return Row(children: [
            Checkbox(value: _secilenAsiIdleri.contains(id), onChanged: (v) => setState(() => v! ? _secilenAsiIdleri.add(id) : _secilenAsiIdleri.remove(id)), activeColor: turuncuPastel),
            Expanded(child: Text(asi['asi_adi'])),
          ]);
        }).toList()),
      ),
    ]);
  }

  Widget _buildPhotoUploadSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hayvan Fotoğrafları (En az 1)', style: TextStyle(color: zeytinYesili, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: secilenFotograflar.length + 1,
            itemBuilder: (context, index) {
              if (index == secilenFotograflar.length) {
                return GestureDetector(
                  onTap: _fotoCekVeyaSec,
                  child: Container(
                    width: 120, margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(color: arkaPlan, borderRadius: BorderRadius.circular(12), border: Border.all(color: turuncuPastel)),
                    child: Icon(Icons.add_a_photo, color: turuncuPastel, size: 30),
                  ),
                );
              }
              return Stack(children: [
                Container(width: 120, margin: const EdgeInsets.only(right: 10), child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(File(secilenFotograflar[index].path), fit: BoxFit.cover))),
                Positioned(right: 15, top: 5, child: GestureDetector(onTap: () => setState(() => secilenFotograflar.removeAt(index)), child: const CircleAvatar(radius: 10, backgroundColor: Colors.red, child: Icon(Icons.close, size: 12, color: Colors.white)))),
              ]);
            },
          ),
        ),

        // YENİ UYARI MESAJI BURADA ÇAĞRILIYOR
        _buildPhotoTipMessage(),

      ],
    );
  }
}