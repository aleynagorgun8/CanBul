import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Proje içi importlar
import 'ilanlar.dart';
import 'kullanici_profili.dart';
import 'profil.dart';

const Color zeytinYesili = Color(0xFF558B2F);
const Color lacivert = Color(0xFF002D72);
const Color sariPastel = Color(0xFFFFB74D);
const Color arkaPlan = Color(0xFFF1F8E9);

// 1. Enum: Bildirim Türleri
enum BildirimTuru {
  mesaj,
  eslesme,
  begeni,
  yorum,
  takip
}

// Gelişmiş Bildirim Verisi
class BildirimModel {
  final String id;
  final String baslik;
  final String icerik;
  final String zaman;
  final BildirimTuru tur;
  final bool okunduMu;
  final String? ilgiliId;
  final String? ilgiliTip;

  // Gönderen Kişi Bilgileri
  final String gonderenAd;
  final String? gonderenFotoUrl;

  BildirimModel({
    required this.id,
    required this.baslik,
    required this.icerik,
    required this.zaman,
    required this.tur,
    required this.okunduMu,
    this.ilgiliId,
    this.ilgiliTip,
    required this.gonderenAd,
    this.gonderenFotoUrl,
  });

  factory BildirimModel.fromMap(Map<String, dynamic> map) {
    //Tür Dönüşümü
    BildirimTuru gelenTur;
    final String turString = map['tur'] ?? 'mesaj';
    switch (turString) {
      case 'eslesme': gelenTur = BildirimTuru.eslesme; break;
      case 'begeni': gelenTur = BildirimTuru.begeni; break;
      case 'yorum': gelenTur = BildirimTuru.yorum; break;
      case 'takip': gelenTur = BildirimTuru.takip; break;
      default: gelenTur = BildirimTuru.mesaj;
    }

    // Zaman Hesaplaması
    String zamanMetni = '';
    if (map['created_at'] != null) {
      final created = DateTime.parse(map['created_at']).toLocal();
      final fark = DateTime.now().difference(created);
      if (fark.inMinutes < 1) zamanMetni = 'Şimdi';
      else if (fark.inMinutes < 60) zamanMetni = '${fark.inMinutes} dk önce';
      else if (fark.inHours < 24) zamanMetni = '${fark.inHours} sa önce';
      else zamanMetni = '${fark.inDays} gün önce';
    }

    // C. İlişkili Tablodan (profiles) Gelen Veriyi Çözümleme

    final gonderenData = map['gonderen'] as Map<String, dynamic>?;
    final String ad = gonderenData?['tam_ad'] ?? 'Anonim';
    final String? foto = gonderenData?['profil_foto'];

    return BildirimModel(
      id: map['id'].toString(),
      baslik: map['baslik'] ?? 'Bildirim',
      icerik: map['mesaj'] ?? '',
      zaman: zamanMetni,
      tur: gelenTur,
      okunduMu: map['goruldu'] ?? false,
      ilgiliId: map['ilgili_id']?.toString(),
      ilgiliTip: map['ilgili_tip']?.toString(),
      gonderenAd: ad,
      gonderenFotoUrl: foto,
    );
  }
}

class BildirimlerSayfasi extends StatelessWidget {
  const BildirimlerSayfasi({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Bildirimler")),
        body: const Center(child: Text("Giriş yapmalısınız.")),
      );
    }

    return Scaffold(
      backgroundColor: arkaPlan,
      appBar: AppBar(
        title: const Text("Bildirimler"),
        centerTitle: true,
        backgroundColor: zeytinYesili,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        // DİNAMİK YAPI: Stream veritabanını sürekli dinler.
        stream: Supabase.instance.client
            .from('bildirimler')
            .stream(primaryKey: ['id'])
            .eq('kullanici_id', user.id)
            .order('created_at', ascending: false)
            .asyncMap((data) async { // Profil verilerini çekmek için asyncMap
          List<Map<String, dynamic>> zenginlesmisData = [];
          for (var bildirim in data) {
            var yeniVeri = Map<String, dynamic>.from(bildirim);

            // Gönderen ID varsa profili çek
            if (bildirim['gonderen_id'] != null) {
              final profil = await Supabase.instance.client
                  .from('profiles')
                  .select('tam_ad, profil_foto')
                  .eq('id', bildirim['gonderen_id'])
                  .maybeSingle();

              if (profil != null) {
                yeniVeri['gonderen'] = profil;
              }
            }
            zenginlesmisData.add(yeniVeri);
          }
          return zenginlesmisData;
        }),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: zeytinYesili));
          }
          if (snapshot.hasError) {
            return Center(child: Text("Hata: ${snapshot.error}"));
          }

          final data = snapshot.data;
          if (data == null || data.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text("Henüz bir bildiriminiz yok.", style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            );
          }

          final bildirimler = data.map((e) => BildirimModel.fromMap(e)).toList();

          return ListView.separated(
            itemCount: bildirimler.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              return _BildirimKarti(bildirim: bildirimler[index]);
            },
          );
        },
      ),
    );
  }
}

class _BildirimKarti extends StatefulWidget {
  final BildirimModel bildirim;
  const _BildirimKarti({required this.bildirim});

  @override
  State<_BildirimKarti> createState() => _BildirimKartiState();
}

class _BildirimKartiState extends State<_BildirimKarti> {
  String? _profilFotoUrl;
  late bool _yerelOkundu; // Anlık UI güncellemesi için yerel değişken

  @override
  void initState() {
    super.initState();
    _yerelOkundu = widget.bildirim.okunduMu;
    _fotoUrlGetir();
  }

  // Stream güncellenirse yerel değişkeni de senkronize et
  @override
  void didUpdateWidget(_BildirimKarti oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bildirim.okunduMu != oldWidget.bildirim.okunduMu) {
      setState(() {
        _yerelOkundu = widget.bildirim.okunduMu;
      });
    }
  }

  Future<void> _fotoUrlGetir() async {
    if (widget.bildirim.gonderenFotoUrl != null && widget.bildirim.gonderenFotoUrl!.isNotEmpty) {
      try {
        final url = await Supabase.instance.client.storage
            .from('profil_fotolari')
            .createSignedUrl(widget.bildirim.gonderenFotoUrl!, 60 * 60);
        if (mounted) setState(() => _profilFotoUrl = url);
      } catch (e) {
        debugPrint("Fotoğraf URL hatası: $e");
      }
    }
  }

  Future<void> _yonlendir(BuildContext context) async {
    //  Tıklandığı an okundu yap
    if (!_yerelOkundu) {
      setState(() {
        _yerelOkundu = true;
      });

      // Arka planda veritabanını güncelle
      Supabase.instance.client
          .from('bildirimler')
          .update({'goruldu': true})
          .eq('id', widget.bildirim.id)
          .then((_) => debugPrint("DB Güncellendi"));
    }

    final String? hedefId = widget.bildirim.ilgiliId;
    final String? hedefTip = widget.bildirim.ilgiliTip;

    if (hedefId == null) return;

    // Yönlendirme Mantığı
    if (widget.bildirim.tur == BildirimTuru.takip) {
      final myId = Supabase.instance.client.auth.currentUser?.id;
      if (myId == hedefId) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const Profil()));
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (context) => KullaniciProfili(kullaniciId: hedefId)));
      }
    } else {
      // İlan Detayına Git
      _ilanDetayinaGit(context, hedefId, hedefTip ?? 'kayip');
    }
  }

  Future<void> _ilanDetayinaGit(BuildContext context, String ilanId, String ilanTipi) async {
    try {
      String tabloAdi = '';
      String selectQuery = '';

      if (ilanTipi == 'kayip') {
        tabloAdi = 'kayip_ilanlar';
        selectQuery = 'id, kullanici_id, hayvan_adi, hayvan_turu, hayvan_rengi, ekstra_bilgi, konum, konum_text, hayvan_cinsiyeti, cipi_var_mi, created_at, profiles(tam_ad, telefon)';
      } else if (ilanTipi == 'bulunan') {
        tabloAdi = 'bulunan_ilanlar';
        selectQuery = 'id, kullanici_id, hayvan_turu, hayvan_rengi, hayvan_cinsiyeti, ekstra_bilgi, konum, konum_text, created_at, profiles(tam_ad, telefon)';
      } else if (ilanTipi == 'sahiplendirme') {
        tabloAdi = 'sahiplendirme_ilanlar';
        selectQuery = 'id, kullanici_id, hayvan_adi, hayvan_turu, hayvan_rengi, ekstra_bilgi, konum, konum_text, hayvan_cinsiyeti, cipi_var_mi, kisir_mi, kisirlastirma_sarti, aliskanliklar, created_at, profiles(tam_ad, telefon)';
      } else {
        return;
      }

      final ilanDetay = await Supabase.instance.client.from(tabloAdi).select(selectQuery).eq('id', ilanId).maybeSingle();
      if (ilanDetay == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bu ilan artık mevcut değil.")));
        return;
      }

      final List<dynamic> fotos = await Supabase.instance.client.from('ilan_fotograflari').select('foto_url').eq('ilan_id', ilanId).eq('ilan_tipi', ilanTipi);
      final List<String> fotoUrls = fotos.map((e) => e['foto_url'] as String).toList();
      final profileData = ilanDetay['profiles'] as Map<String, dynamic>?;

      final Ilan ilanNesnesi = Ilan.fromMap(
        data: ilanDetay,
        tip: ilanTipi,
        fotoUrls: fotoUrls,
        kullaniciTel: profileData?['telefon'] ?? '',
        kullaniciAd: profileData?['tam_ad'] ?? 'Kullanıcı',
      );

      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => IlanDetaySayfasi(ilan: ilanNesnesi)));
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("İlan detayları yüklenemedi.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Yerel değişkeni kullanıyoruz
    final bool isUnread = !_yerelOkundu;

    return Container(
      color: isUnread ? const Color(0xFFFFFDE7) : Colors.white, // Okunmamışsa hafif sarı
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: Colors.grey[200],
          backgroundImage: _profilFotoUrl != null ? NetworkImage(_profilFotoUrl!) : null,
          child: _profilFotoUrl == null
              ? Icon(_ikonGetir(widget.bildirim.tur), color: _renkGetir(widget.bildirim.tur))
              : null,
        ),
        title: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.black, fontSize: 14),
            children: [
              TextSpan(
                text: widget.bildirim.gonderenAd,
                style: const TextStyle(fontWeight: FontWeight.bold, color: lacivert),
              ),
              const TextSpan(text: " "),
              TextSpan(text: widget.bildirim.icerik),
            ],
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Text(
            widget.bildirim.zaman,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ),
        trailing: isUnread
            ? const Icon(Icons.circle, size: 12, color: sariPastel) // Okunmamışsa sarı nokta
            : null,
        onTap: () => _yonlendir(context),
      ),
    );
  }

  IconData _ikonGetir(BildirimTuru tur) {
    switch (tur) {
      case BildirimTuru.eslesme: return Icons.pets;
      case BildirimTuru.begeni: return Icons.favorite;
      case BildirimTuru.yorum: return Icons.comment;
      case BildirimTuru.takip: return Icons.person;
      default: return Icons.notifications;
    }
  }

  Color _renkGetir(BildirimTuru tur) {
    switch (tur) {
      case BildirimTuru.eslesme: return lacivert;
      case BildirimTuru.begeni: return sariPastel;
      case BildirimTuru.yorum: return Colors.blue;
      case BildirimTuru.takip: return zeytinYesili;
      default: return Colors.grey;
    }
  }
}