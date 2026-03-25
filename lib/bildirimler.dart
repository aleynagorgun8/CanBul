import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'EslesmeDetaySayfasi.dart';

// Proje içi importlar
import 'ilanlar.dart';
import 'kullanici_profili.dart';
import 'profil.dart';

// --- RENK SABİTLERİ ---
const Color zeytinYesili = Color(0xFF558B2F);
const Color lacivert = Color(0xFF002D72);
const Color sariPastel = Color(0xFFFFB74D);
const Color arkaPlan = Color(0xFFF1F8E9);

enum BildirimTuru { mesaj, eslesme, begeni, yorum, takip }

// --- BİLDİRİM MODELİ (Orijinal) ---
class BildirimModel {
  final String id;
  final String baslik;
  final String icerik;
  final String zaman;
  final BildirimTuru tur;
  final bool okunduMu;
  final String? ilgiliId;
  final String? ilgiliTip;
  final String gonderenAd;
  final String? gonderenFotoUrl;

  BildirimModel({
    required this.id, required this.baslik, required this.icerik,
    required this.zaman, required this.tur, required this.okunduMu,
    this.ilgiliId, this.ilgiliTip, required this.gonderenAd, this.gonderenFotoUrl,
  });

  factory BildirimModel.fromMap(Map<String, dynamic> map) {
    BildirimTuru gelenTur;
    final String turString = map['tur'] ?? 'mesaj';
    switch (turString) {
      case 'eslesme': gelenTur = BildirimTuru.eslesme; break;
      case 'begeni': gelenTur = BildirimTuru.begeni; break;
      case 'yorum': gelenTur = BildirimTuru.yorum; break;
      case 'takip': gelenTur = BildirimTuru.takip; break;
      default: gelenTur = BildirimTuru.mesaj;
    }

    String zamanMetni = '';
    if (map['created_at'] != null) {
      final created = DateTime.parse(map['created_at']).toLocal();
      final fark = DateTime.now().difference(created);
      if (fark.inMinutes < 1) zamanMetni = 'Şimdi';
      else if (fark.inMinutes < 60) zamanMetni = '${fark.inMinutes} dk önce';
      else if (fark.inHours < 24) zamanMetni = '${fark.inHours} sa önce';
      else zamanMetni = '${fark.inDays} gün önce';
    }

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

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: arkaPlan,
        appBar: AppBar(
          title: const Text("Bildirimler"),
          centerTitle: true,
          backgroundColor: zeytinYesili,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: sariPastel,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: "Sosyal", icon: Icon(Icons.people)),
              Tab(text: "İlan Eşleşmeleri", icon: Icon(Icons.pets)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _SosyalBildirimlerTab(user: user),
            _IlanEslesmeleriTab(user: user),
          ],
        ),
      ),
    );
  }
}

// --- 1. SEKME: SOSYAL BİLDİRİMLER (Orijinal) ---
class _SosyalBildirimlerTab extends StatelessWidget {
  final User user;
  const _SosyalBildirimlerTab({required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('bildirimler')
          .stream(primaryKey: ['id'])
          .eq('kullanici_id', user.id)
          .order('created_at', ascending: false)
          .asyncMap((data) async {
        List<Map<String, dynamic>> zenginlesmisData = [];
        for (var bildirim in data) {
          var yeniVeri = Map<String, dynamic>.from(bildirim);
          if (bildirim['gonderen_id'] != null) {
            final profil = await Supabase.instance.client.from('profiles').select('tam_ad, profil_foto').eq('id', bildirim['gonderen_id']).maybeSingle();
            if (profil != null) yeniVeri['gonderen'] = profil;
          }
          zenginlesmisData.add(yeniVeri);
        }
        return zenginlesmisData;
      }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: zeytinYesili));
        if (snapshot.hasError) return Center(child: Text("Hata: ${snapshot.error}"));
        final data = snapshot.data;
        if (data == null || data.isEmpty) return const Center(child: Text("Henüz bir sosyal bildiriminiz yok."));

        final bildirimler = data.map((e) => BildirimModel.fromMap(e)).toList();
        return ListView.separated(
          itemCount: bildirimler.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) => _BildirimKarti(bildirim: bildirimler[index]),
        );
      },
    );
  }
}

// --- 2. SEKME: İLAN EŞLEŞMELERİ (SADECE KAYIP İLANLAR İÇİN) ---
class _IlanEslesmeleriTab extends StatelessWidget {
  final User user;
  const _IlanEslesmeleriTab({required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('eslesmeler')
          .stream(primaryKey: ['id'])
          .order('eslesme_tarihi', ascending: false)
          .asyncMap((eslesmeler) async {
        // SADECE kullanıcının KAYIP ilanlarını çekiyoruz
        final benimKayipRes = await Supabase.instance.client.from('kayip_ilanlar').select('id, hayvan_adi').eq('kullanici_id', user.id);
        Map<String, String> kayipAdlari = { for (var e in benimKayipRes) e['id'].toString(): e['hayvan_adi']?.toString() ?? 'Bilinmeyen' };

        List<Map<String, dynamic>> gruplanmisList = [];
        Map<String, Map<String, dynamic>> geciciGruplar = {};

        for (var eslesme in eslesmeler) {
          String kayipId = eslesme['kayip_ilan_id'].toString();

          // Eğer eşleşmedeki kayıp ilan BANA aitse, grubu oluştur
          if (kayipAdlari.containsKey(kayipId)) {
            if (!geciciGruplar.containsKey(kayipId)) {
              geciciGruplar[kayipId] = {
                'benim_ilan_id': kayipId,
                'benim_ilan_tipi': 'kayip',
                'baslik': '"${kayipAdlari[kayipId]}" isimli kayıp ilanınız için bulunan olası eşleşmeler',
                'eslesmeler': <Map<String, dynamic>>[]
              };
            }
            geciciGruplar[kayipId]!['eslesmeler'].add(eslesme);
          }
          // Bulunan ilanlar artık kontrol edilmiyor, sistem onları yok sayıyor
        }

        // Puanlara göre sırala ve ilk 5'ini al
        for (var grup in geciciGruplar.values) {
          List<Map<String, dynamic>> liste = grup['eslesmeler'];
          liste.sort((a, b) => (b['eslesme_skoru'] ?? 0).compareTo(a['eslesme_skoru'] ?? 0));
          if (liste.length > 5) {
            grup['eslesmeler'] = liste.sublist(0, 5);
          }
          gruplanmisList.add(grup);
        }

        return gruplanmisList;
      }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: zeytinYesili));
        final data = snapshot.data ?? [];
        if (data.isEmpty) return const Center(child: Text("Henüz kayıp ilanlarınız için bir eşleşme bulunamadı."));

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: data.length,
          itemBuilder: (context, index) {
            final grup = data[index];
            final String baslik = grup['baslik'];
            final int eslesmeSayisi = (grup['eslesmeler'] as List).length;

            return Card(
              color: sariPastel.withOpacity(0.15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const CircleAvatar(backgroundColor: sariPastel, child: Icon(Icons.search, color: Colors.white, size: 20)),
                title: Text(baslik, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text("Olası $eslesmeSayisi eşleşme bulundu.", style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: zeytinYesili),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EslesmeDetaySayfasi(grupVerisi: grup),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

// --- BİLDİRİM KARTI SINIFI (Sosyal Bildirimler İçin Orijinal Kod) ---
class _BildirimKarti extends StatefulWidget {
  final BildirimModel bildirim;
  const _BildirimKarti({required this.bildirim});

  @override
  State<_BildirimKarti> createState() => _BildirimKartiState();
}

class _BildirimKartiState extends State<_BildirimKarti> {
  String? _profilFotoUrl;
  late bool _yerelOkundu;

  @override
  void initState() {
    super.initState();
    _yerelOkundu = widget.bildirim.okunduMu;
    _fotoUrlGetir();
  }

  @override
  void didUpdateWidget(_BildirimKarti oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bildirim.okunduMu != oldWidget.bildirim.okunduMu) {
      setState(() { _yerelOkundu = widget.bildirim.okunduMu; });
    }
  }

  Future<void> _fotoUrlGetir() async {
    if (widget.bildirim.gonderenFotoUrl != null && widget.bildirim.gonderenFotoUrl!.isNotEmpty) {
      try {
        final url = await Supabase.instance.client.storage.from('profil_fotolari').createSignedUrl(widget.bildirim.gonderenFotoUrl!, 3600);
        if (mounted) setState(() => _profilFotoUrl = url);
      } catch (e) { debugPrint("Fotoğraf hatası: $e"); }
    }
  }

  Future<void> _yonlendir(BuildContext context) async {
    if (!_yerelOkundu) {
      setState(() { _yerelOkundu = true; });
      Supabase.instance.client.from('bildirimler').update({'goruldu': true}).eq('id', widget.bildirim.id).then((_) => debugPrint("DB Güncellendi"));
    }
    final String? hedefId = widget.bildirim.ilgiliId;
    final String? hedefTip = widget.bildirim.ilgiliTip;
    if (hedefId == null) return;

    if (widget.bildirim.tur == BildirimTuru.takip) {
      final myId = Supabase.instance.client.auth.currentUser?.id;
      if (myId == hedefId) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const Profil()));
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (context) => KullaniciProfili(kullaniciId: hedefId)));
      }
    } else {
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
      } else { return; }

      final ilanDetay = await Supabase.instance.client.from(tabloAdi).select(selectQuery).eq('id', ilanId).maybeSingle();
      if (ilanDetay == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("İlan mevcut değil.")));
        return;
      }
      final List<dynamic> fotos = await Supabase.instance.client.from('ilan_fotograflari').select('foto_url').eq('ilan_id', ilanId).eq('ilan_tipi', ilanTipi);
      final List<String> fotoUrls = fotos.map((e) => e['foto_url'] as String).toList();
      final profileData = ilanDetay['profiles'] as Map<String, dynamic>?;

      final Ilan ilanNesnesi = Ilan.fromMap(
        data: ilanDetay, tip: ilanTipi, fotoUrls: fotoUrls,
        kullaniciTel: profileData?['telefon'] ?? '', kullaniciAd: profileData?['tam_ad'] ?? 'Kullanıcı',
      );
      if (mounted) Navigator.push(context, MaterialPageRoute(builder: (context) => IlanDetaySayfasi(ilan: ilanNesnesi)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Hata oluştu.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isUnread = !_yerelOkundu;
    return Container(
      color: isUnread ? const Color(0xFFFFFDE7) : Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 26, backgroundColor: Colors.grey[200],
          backgroundImage: _profilFotoUrl != null ? NetworkImage(_profilFotoUrl!) : null,
          child: _profilFotoUrl == null ? Icon(_ikonGetir(widget.bildirim.tur), color: _renkGetir(widget.bildirim.tur)) : null,
        ),
        title: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.black, fontSize: 14),
            children: [
              TextSpan(text: widget.bildirim.gonderenAd, style: const TextStyle(fontWeight: FontWeight.bold, color: lacivert)),
              const TextSpan(text: " "),
              TextSpan(text: widget.bildirim.icerik),
            ],
          ),
        ),
        subtitle: Padding(padding: const EdgeInsets.only(top: 6.0), child: Text(widget.bildirim.zaman, style: TextStyle(fontSize: 11, color: Colors.grey[600]))),
        trailing: isUnread ? const Icon(Icons.circle, size: 12, color: sariPastel) : null,
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