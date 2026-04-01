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
    return BildirimModel(
      id: map['id'].toString(),
      baslik: map['baslik'] ?? 'Bildirim',
      icerik: map['mesaj'] ?? '',
      zaman: zamanMetni,
      tur: gelenTur,
      okunduMu: map['goruldu'] ?? false,
      ilgiliId: map['ilgili_id']?.toString(),
      ilgiliTip: map['ilgili_tip']?.toString(),
      gonderenAd: gonderenData?['tam_ad'] ?? 'Anonim',
      gonderenFotoUrl: gonderenData?['profil_foto'],
    );
  }
}

class BildirimlerSayfasi extends StatelessWidget {
  final int varsayilanTab; // Analizden sonra 1 gönderilir ✅

  const BildirimlerSayfasi({super.key, this.varsayilanTab = 0});

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
      initialIndex: varsayilanTab, // Hangi sekmenin açık geleceğini belirler ✅
      child: Scaffold(
        backgroundColor: arkaPlan,
        appBar: AppBar(
          // --- iOS TARZI GERİ OKU EKLEDİĞİMİZ KISIM ---
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => Navigator.of(context).pop(),
          ),
          // --------------------------------------------
          title: const Text("Bildirimler"),
          centerTitle: true,
          backgroundColor: zeytinYesili,
          foregroundColor: Colors.white,
          bottom: TabBar( // DİKKAT: const kelimesini sildik çünkü içi dinamik ✅
            indicatorColor: sariPastel,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(
                text: "Sosyal",
                icon: _buildSosyalBadgeIcon(user.id), // Dinamik rozetli ikon
              ),
              Tab(
                text: "İlan Eşleşmeleri",
                icon: _buildEslesmeBadgeIcon(user.id), // Dinamik rozetli ikon
              ),
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
    );  }

  // --- MÜHENDİSLİK DOKUNUŞU: TAB İKONLARI İÇİN BAĞIMSIZ STREAM'LER ---

  // Sosyal Tab'ı için dinleyici
  Widget _buildSosyalBadgeIcon(String userId) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('bildirimler')
          .stream(primaryKey: ['id'])
          .eq('kullanici_id', userId),
      builder: (context, snapshot) {
        int count = 0;
        if (snapshot.hasData) {
          count = snapshot.data!.where((b) => b['goruldu'] == false).length;
        }
        return _rozetliIkon(Icons.people, count);
      },
    );
  }

  // Eşleşmeler Tab'ı için dinleyici (Akıllı Sayım Filtresi ile)
  Widget _buildEslesmeBadgeIcon(String userId) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('eslesmeler')
          .stream(primaryKey: ['id'])
          .eq('kontrol_edildi', false)
          .asyncMap((tumEslesmeler) async {

        final benimIlanlarim = await Supabase.instance.client
            .from('kayip_ilanlar')
            .select('id')
            .eq('kullanici_id', userId);

        final benimIdSetim = benimIlanlarim.map((e) => e['id'].toString()).toSet();
        return tumEslesmeler.where((e) => benimIdSetim.contains(e['kayip_ilan_id'].toString())).toList();
      }),
      builder: (context, snapshot) {
        int count = 0;
        if (snapshot.hasData) {
          final benzersizBasliklar = snapshot.data!.map((e) => e['kayip_ilan_id'].toString()).toSet();
          count = benzersizBasliklar.length;
        }
        return _rozetliIkon(Icons.pets, count);
      },
    );
  }

  // Ortak Rozet (Badge) Tasarımı
  Widget _rozetliIkon(IconData ikon, int bildirimSayisi) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(ikon),
        if (bildirimSayisi > 0)
          Positioned(
            right: -8, // İkonun tam köşesine oturması için
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: sariPastel,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Center(
                child: Text(
                  bildirimSayisi > 9 ? '9+' : '$bildirimSayisi',
                  style: const TextStyle(
                    color: lacivert,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

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

// --- 2. SEKME: İLAN EŞLEŞMELERİ (STATEFUL WIDGET OLARAK GÜNCELLENDİ) ---
class _IlanEslesmeleriTab extends StatefulWidget {
  final User user;
  const _IlanEslesmeleriTab({required this.user});

  @override
  State<_IlanEslesmeleriTab> createState() => _IlanEslesmeleriTabState();
}

class _IlanEslesmeleriTabState extends State<_IlanEslesmeleriTab> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('eslesmeler')
          .stream(primaryKey: ['id'])
          .order('eslesme_tarihi', ascending: false)
          .asyncMap((eslesmeler) async {

        // 1. ADIM: Sadece GİRİŞ YAPAN KULLANICININ kayıp ilanlarını çekiyoruz
        // Stateful Widget içinde parametrelere 'widget.user' şeklinde erişilir ✅
        final benimKayipIlanlarim = await Supabase.instance.client
            .from('kayip_ilanlar')
            .select('id, hayvan_adi')
            .eq('kullanici_id', widget.user.id);

        Map<String, String> kayipMap = {
          for (var ilan in benimKayipIlanlarim)
            ilan['id'].toString(): ilan['hayvan_adi'] ?? 'İsimsiz Hayvan'
        };

        Map<String, Map<String, dynamic>> gruplar = {};

        // 2. ADIM: Eşleşmeleri kayıp ilan bazlı grupluyoruz
        for (var eslesme in eslesmeler) {
          String kID = eslesme['kayip_ilan_id'].toString();
          if (kayipMap.containsKey(kID)) {
            if (!gruplar.containsKey(kID)) {
              gruplar[kID] = {
                'benim_ilan_id': kID,
                'benim_ilan_tipi': 'kayip',
                'baslik': kayipMap[kID],
                'eslesmeler': <Map<String, dynamic>>[]
              };
            }
            gruplar[kID]!['eslesmeler'].add(eslesme);
          }
        }
        return gruplar.values.toList();
      }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: zeytinYesili));
        }
        final gruplanmisVeriler = snapshot.data ?? [];

        if (gruplanmisVeriler.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                "Henüz kayıp ilanlarınız için bir eşleşme bulunmuyor.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: gruplanmisVeriler.length,
          itemBuilder: (context, index) {
            final grup = gruplanmisVeriler[index];
            final List eslesmelerListesi = grup['eslesmeler'] as List;
            final int adaySayisi = eslesmelerListesi.length;

            // --- MÜHENDİSLİK MANTIĞI: Bu grupta hiç okunmamış eşleşme var mı? ---
            final bool okunmadiMi = eslesmelerListesi.any((e) => e['kontrol_edildi'] == false);

            return Card(
              color: okunmadiMi ? const Color(0xFFFFFDE7) : Colors.white,
              elevation: okunmadiMi ? 4 : 2,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                leading: const CircleAvatar(
                  backgroundColor: lacivert,
                  child: Icon(Icons.pets, color: Colors.white, size: 20),
                ),
                title: Text(
                  "${grup['baslik']} Hakkında Eşleşmeler",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: lacivert),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    "Sizin için $adaySayisi potansiyel aday bulundu.",
                    style: TextStyle(
                      color: okunmadiMi ? Colors.black87 : Colors.grey.shade700,
                      fontWeight: okunmadiMi ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ),
                trailing: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    if (okunmadiMi)
                      const Icon(Icons.circle, size: 12, color: sariPastel),
                    const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  ],
                ),
                onTap: () async {
                  // 1. ADIM: ID'leri topla
                  final List<dynamic> idler = eslesmelerListesi.map((e) => e['id']).toList();

                  // 2. ADIM: Arka planda DB güncellemesi başlasın (await YOK, kullanıcıyı bekletmiyoruz!) ✅
                  Supabase.instance.client
                      .from('eslesmeler')
                      .update({'kontrol_edildi': true})
                      .inFilter('id', idler)
                      .then((_) => debugPrint("✅ DB Güncellendi"))
                      .catchError((e) => debugPrint("🚨 DB Hatası: $e"));

                  // 3. ADIM: Detay sayfasına ANINDA git ve kullanıcının GERİ DÖNMESİNİ BEKLE (await var) ✅
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => EslesmeDetaySayfasi(grupVerisi: grup)),
                  );

                  // 4. ADIM: Kullanıcı geri döndüğünde ekranı ZORLA YENİLE (Sarı nokta anında silinir) ✅
                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
            );
          },
        );
      },
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
  late bool _yerelOkundu;

  @override
  void initState() {
    super.initState();
    _yerelOkundu = widget.bildirim.okunduMu;
    _fotoUrlGetir();
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
      await Supabase.instance.client.from('bildirimler').update({'goruldu': true}).eq('id', widget.bildirim.id);
    }

    final String? hedefId = widget.bildirim.ilgiliId;
    if (hedefId == null) return;

    if (widget.bildirim.tur == BildirimTuru.takip) {
      final myId = Supabase.instance.client.auth.currentUser?.id;
      if (myId == hedefId) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const Profil()));
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (context) => KullaniciProfili(kullaniciId: hedefId)));
      }
    } else {
      _ilanDetayinaGit(context, hedefId, widget.bildirim.ilgiliTip ?? 'kayip');
    }
  }

  Future<void> _ilanDetayinaGit(BuildContext context, String ilanId, String ilanTipi) async {
    try {
      String tabloAdi = (ilanTipi == 'kayip') ? 'kayip_ilanlar' : (ilanTipi == 'bulunan' ? 'bulunan_ilanlar' : 'sahiplendirme_ilanlar');

      final ilanDetay = await Supabase.instance.client.from(tabloAdi).select('*, profiles(tam_ad, telefon)').eq('id', ilanId).maybeSingle();
      if (ilanDetay == null) return;

      final List<dynamic> fotos = await Supabase.instance.client.from('ilan_fotograflari').select('foto_url').eq('ilan_id', ilanId).eq('ilan_tipi', ilanTipi);
      final List<String> fotoUrls = fotos.map((e) => e['foto_url'] as String).toList();
      final profileData = ilanDetay['profiles'] as Map<String, dynamic>?;

      final Ilan ilanNesnesi = Ilan.fromMap(
        data: ilanDetay, tip: ilanTipi, fotoUrls: fotoUrls,
        kullaniciTel: profileData?['telefon'] ?? '', kullaniciAd: profileData?['tam_ad'] ?? 'Kullanıcı',
      );
      if (mounted) Navigator.push(context, MaterialPageRoute(builder: (context) => IlanDetaySayfasi(ilan: ilanNesnesi)));
    } catch (e) {
      debugPrint("Yönlendirme hatası: $e");
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

  IconData _ikonGetir(BildirimTuru tur) => tur == BildirimTuru.eslesme ? Icons.pets : (tur == BildirimTuru.begeni ? Icons.favorite : (tur == BildirimTuru.yorum ? Icons.comment : Icons.person));
  Color _renkGetir(BildirimTuru tur) => tur == BildirimTuru.eslesme ? lacivert : (tur == BildirimTuru.begeni ? sariPastel : (tur == BildirimTuru.yorum ? Colors.blue : zeytinYesili));
}