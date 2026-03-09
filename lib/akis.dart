import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Panoya kopyalama için
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago; // Zaman formatı için
import 'shared_bottom_nav.dart';
import 'kullanici_profili.dart';
import 'profil.dart';
import 'ilanlar.dart';
import 'mesajlar.dart';

// --- RENKLER (ORİJİNAL TEMA) ---
const Color TEMA_YESIL = Color(0xFF558B2F); // Ana Yeşil
const Color TEMA_SARI = Color(0xFFFFC300); // Vurgular
const Color TEMA_LACIVERT = Color(0xFF1E3A8A); // Metinler
const Color ARKA_PLAN_ACIK = Color(0xFFF1F8E9); // Açık Yeşil Arkaplan
const Color ARKA_PLAN_BEYAZ = Colors.white;
const Color KART_GOLGE = Color(0xFFD3DCE6);
const Color KART_REPOST_M = Colors.blue; // Repost Mavi
const Color KART_KAYIP_K = Colors.red; // Kayıp Kırmızı
const Color KART_BULUNAN_Y = Color(0xFF4CAF50); // Bulunan Yeşil
const Color KART_GRI = Color(0xFF78909C);

final supabase = Supabase.instance.client;

const String _PROFIL_FOTO_KOVA_ADI = 'profil_fotolari';

// SORGULAR
const String _KAYIP_ILAN_FIELDS = 'id, kullanici_id, hayvan_adi, hayvan_turu, hayvan_rengi, hayvan_cinsiyeti, cipi_var_mi, ekstra_bilgi, created_at, konum, konum_text';
const String _BULUNAN_ILAN_FIELDS = 'id, kullanici_id, hayvan_turu, hayvan_rengi, hayvan_cinsiyeti, ekstra_bilgi, created_at, konum, konum_text';
const String _SAHIPLENDIRME_ILAN_FIELDS = 'id, kullanici_id, hayvan_adi, hayvan_turu, hayvan_rengi, hayvan_cinsiyeti, cipi_var_mi, kisir_mi, kisirlastirma_sarti, aliskanliklar, ekstra_bilgi, created_at, konum, konum_text';


class Kullanici {
  final String id;
  final String tamAd;
  final String? profilFotoUrl;

  Kullanici({
    required this.id,
    required this.tamAd,
    this.profilFotoUrl,
  });

  factory Kullanici.fromJson(Map<String, dynamic> json) {
    return Kullanici(
      id: json['id'] as String,
      tamAd: json['tam_ad'] as String? ?? 'İsimsiz Kullanıcı',
      profilFotoUrl: json['profil_foto'] as String?,
    );
  }
}

// Profil fotoğrafı için güvenli URL alma fonksiyonu
Future<String?> _profilFotoGuvenliUrlGetir(String? dosyaYolu) async {
  if (dosyaYolu == null || dosyaYolu.isEmpty) return null;
  try {
    return await supabase.storage.from(_PROFIL_FOTO_KOVA_ADI).createSignedUrl(dosyaYolu, 60);
  } catch (e) {
    return null;
  }
}

// İlan fotoğraflarını çekme fonksiyonu
Future<Map<String, List<String>>> _ilanFotograflariniGetir(List<String> ilanIdleri, String ilanTipi) async {
  if (ilanIdleri.isEmpty) return {};

  final List<dynamic> fotos = await supabase
      .from('ilan_fotograflari')
      .select('ilan_id, foto_url')
      .inFilter('ilan_id', ilanIdleri)
      .eq('ilan_tipi', ilanTipi)
      .order('created_at', ascending: true);

  Map<String, List<String>> ilanIdToFotos = {};
  for (final f in fotos) {
    final String iid = f['ilan_id'] as String;
    final String fotoUrl = f['foto_url'] as String;
    if (!ilanIdToFotos.containsKey(iid)) {
      ilanIdToFotos[iid] = [];
    }
    ilanIdToFotos[iid]!.add(fotoUrl);
  }
  return ilanIdToFotos;
}

class AkisSayfasi extends StatefulWidget {
  const AkisSayfasi({super.key});

  @override
  State<AkisSayfasi> createState() => _AkisSayfasiState();
}

class _AkisSayfasiState extends State<AkisSayfasi> {
  bool _aramaAcikMi = false;
  bool _yukleniyor = false;
  final TextEditingController _aramaKontrolcusu = TextEditingController();
  List<Kullanici> _aramaSonuclari = [];
  Map<String, String?> _fotoUrlMap = {};

  // bildirim sayısı
  Stream<int> _okunmamisMesajSayisiGetir() {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return Stream.value(0);

    return supabase
        .from('mesajlar')
        .stream(primaryKey: ['id'])
        .eq('alici_id', myId)
        .map((list) => list.where((m) => m['okundu'] == false).length);
  }

  void _aramaCubugunuDegistir() {
    setState(() {
      _aramaAcikMi = !_aramaAcikMi;
      if (!_aramaAcikMi) {
        _aramaKontrolcusu.clear();
        _aramaSonuclari = [];
        _yukleniyor = false;
      } else {
        _kullaniciAra(_aramaKontrolcusu.text);
      }
    });
  }

  void _kullaniciAra(String aramaMetni) async {
    final aramaKriteri = aramaMetni.trim();
    if (aramaKriteri.isEmpty) {
      setState(() { _aramaSonuclari = []; _yukleniyor = false; });
      return;
    }

    setState(() { _yukleniyor = true; });

    try {
      final response = await supabase
          .from('profiles')
          .select('id, tam_ad, profil_foto')
          .ilike('tam_ad', '%$aramaKriteri%');

      final List<Kullanici> sonuclar = [];
      final Map<String, String?> fotoUrlMap = {};

      for (var veri in response) {
        final kullanici = Kullanici.fromJson(veri);
        sonuclar.add(kullanici);
        if (veri['profil_foto'] != null) {
          fotoUrlMap[kullanici.id] = await _profilFotoGuvenliUrlGetir(veri['profil_foto'] as String);
        }
      }

      if (!mounted) return;
      setState(() {
        _aramaSonuclari = sonuclar;
        _fotoUrlMap = fotoUrlMap;
        _yukleniyor = false;
      });

    } catch (hata) {
      if (!mounted) return;
      setState(() { _yukleniyor = false; _aramaSonuclari = []; });
    }
  }

  @override
  void dispose() {
    _aramaKontrolcusu.dispose();
    super.dispose();
  }

  Widget _aramaSonuclariniGoster() {
    if (_yukleniyor) {
      return const Center(child: CircularProgressIndicator(color: TEMA_YESIL));
    }
    if (_aramaKontrolcusu.text.isEmpty) {
      return const Center(child: Text('Aramaya başlamak için bir isim yazın.', style: TextStyle(color: KART_GRI)));
    }
    if (_aramaSonuclari.isEmpty) {
      return const Center(child: Text('Bu isimle eşleşen kullanıcı bulunamadı.', style: TextStyle(color: KART_GRI)));
    }

    return ListView.builder(
      itemCount: _aramaSonuclari.length,
      itemBuilder: (context, index) {
        final kullanici = _aramaSonuclari[index];
        final String? fotoUrl = _fotoUrlMap[kullanici.id];

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              radius: 20,
              backgroundImage: fotoUrl != null ? NetworkImage(fotoUrl) : null,
              backgroundColor: TEMA_YESIL,
              child: fotoUrl == null ? const Icon(Icons.person, color: ARKA_PLAN_BEYAZ) : null,
            ),
            title: Text(kullanici.tamAd, style: const TextStyle(fontWeight: FontWeight.w600, color: TEMA_LACIVERT)),
            onTap: () {
              final currentUser = supabase.auth.currentUser;
              if (currentUser != null && currentUser.id == kullanici.id) {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const Profil()));
              } else {
                Navigator.push(context, MaterialPageRoute(builder: (context) => KullaniciProfili(kullaniciId: kullanici.id)));
              }
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ARKA_PLAN_ACIK,
      appBar: null,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, bottom: 16, left: 20, right: 20),
            decoration: const BoxDecoration(
              color: TEMA_YESIL,
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _aramaAcikMi
                  ? Container(
                key: const ValueKey<bool>(true),
                height: 48,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(24)),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.close, color: TEMA_YESIL), onPressed: _aramaCubugunuDegistir),
                    Expanded(
                      child: TextField(
                        controller: _aramaKontrolcusu,
                        cursorColor: TEMA_YESIL,
                        autofocus: true,
                        style: const TextStyle(color: TEMA_YESIL),
                        decoration: const InputDecoration(hintText: 'Kullanıcı Ara', border: InputBorder.none),
                        onChanged: _kullaniciAra,
                      ),
                    ),
                  ],
                ),
              )
                  : Row(
                key: const ValueKey<bool>(false),
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(icon: const Icon(Icons.search, color: Colors.white, size: 28), onPressed: _aramaCubugunuDegistir),
                  const Text('Akış', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24, color: Colors.white)),


                  StreamBuilder<int>(
                      stream: _okunmamisMesajSayisiGetir(),
                      builder: (context, snapshot) {
                        final int bildirimSayisi = snapshot.data ?? 0;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.mail_outline, color: Colors.white, size: 28),
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MesajlarSayfasi())),
                            ),
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
                                  child: Text(
                                    bildirimSayisi > 99 ? '99+' : '$bildirimSayisi',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        );
                      }
                  ),

                ],
              ),
            ),
          ),
          Expanded(child: _aramaAcikMi ? _aramaSonuclariniGoster() : const _AkisIcerikWidget()),
        ],
      ),
      bottomNavigationBar: const SharedBottomNavBar(currentIndex: 0, turuncuPastel: TEMA_SARI, gri: KART_GRI, beyaz: ARKA_PLAN_BEYAZ),
    );
  }
}

// === AKIŞ İÇERİĞİ ===

class _AkisIcerikWidget extends StatefulWidget {
  const _AkisIcerikWidget({super.key});

  @override
  State<_AkisIcerikWidget> createState() => _AkisIcerikWidgetState();
}

class _AkisIcerikWidgetState extends State<_AkisIcerikWidget> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _akisIlanlari = [];
  Map<String, Map<String, dynamic>> _kullaniciProfilleri = {};


  Set<String> _begendiklerim = {};
  Set<String> _repostladiklarim = {};
  Map<String, int> _begeniSayilari = {};
  Map<String, int> _yorumSayilari = {};

  @override
  void initState() {
    super.initState();
    _loadAkis();
  }

  Future<void> _loadAkis() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      setState(() => _isLoading = true);

      // Takip Edilenler
      final List<dynamic> takipEdilenler = await supabase.from('takipler').select('takip_edilen').eq('takip_eden', user.id);
      final List<String> takipEdilenIdList = takipEdilenler.map((e) => e['takip_edilen'] as String).toList();

      if (takipEdilenIdList.isEmpty) {
        setState(() { _akisIlanlari = []; _isLoading = false; });
        return;
      }

      // İlanları Çek
      final kayipIlanlar = await supabase.from('kayip_ilanlar').select(_KAYIP_ILAN_FIELDS).inFilter('kullanici_id', takipEdilenIdList);
      final bulunanIlanlar = await supabase.from('bulunan_ilanlar').select(_BULUNAN_ILAN_FIELDS).inFilter('kullanici_id', takipEdilenIdList);
      final sahiplendirmeIlanlar = await supabase.from('sahiplendirme_ilanlar').select(_SAHIPLENDIRME_ILAN_FIELDS).inFilter('kullanici_id', takipEdilenIdList);
      final repostlar = await supabase.from('repostlar').select('ilan_id, ilan_tipi, kullanici_id, created_at').inFilter('kullanici_id', takipEdilenIdList);

      // Tüm İlan ID'lerini topla
      final List<String> tumIlanIdleri = [];
      tumIlanIdleri.addAll(kayipIlanlar.map((e) => e['id'] as String));
      tumIlanIdleri.addAll(bulunanIlanlar.map((e) => e['id'] as String));
      tumIlanIdleri.addAll(sahiplendirmeIlanlar.map((e) => e['id'] as String));
      for(var r in repostlar) {
        if(!tumIlanIdleri.contains(r['ilan_id'])) tumIlanIdleri.add(r['ilan_id'] as String);
      }

      // Profiller
      final tumKullaniciIdleri = {...takipEdilenIdList, user.id};
      for(var i in kayipIlanlar) tumKullaniciIdleri.add(i['kullanici_id']);
      for(var i in bulunanIlanlar) tumKullaniciIdleri.add(i['kullanici_id']);
      for(var i in sahiplendirmeIlanlar) tumKullaniciIdleri.add(i['kullanici_id']);

      final profiller = await supabase.from('profiles').select('id, tam_ad, profil_foto').inFilter('id', tumKullaniciIdleri.toList());
      for (var profil in profiller) {
        final m = profil as Map<String, dynamic>;
        m['profil_foto_guvenli_url'] = await _profilFotoGuvenliUrlGetir(m['profil_foto']);
        _kullaniciProfilleri[m['id']] = m;
      }

      // Fotoğraflar
      final kayipIdList = kayipIlanlar.map((e) => e['id'] as String).toList();
      final bulunanIdList = bulunanIlanlar.map((e) => e['id'] as String).toList();
      final sahiplendirmeIdList = sahiplendirmeIlanlar.map((e) => e['id'] as String).toList();

      final kayipFotolar = await _ilanFotograflariniGetir(kayipIdList, 'kayip');
      final bulunanFotolar = await _ilanFotograflariniGetir(bulunanIdList, 'bulunan');
      final sahiplendirmeFotolar = await _ilanFotograflariniGetir(sahiplendirmeIdList, 'sahiplendirme');


      Set<String> cekilenBegendiklerim = {};
      Set<String> cekilenRepostlarim = {};

      if (tumIlanIdleri.isNotEmpty) {
        // Beğenilerim
        final userBegeniler = await supabase.from('begeniler').select('ilan_id').eq('kullanici_id', user.id).inFilter('ilan_id', tumIlanIdleri);
        cekilenBegendiklerim = userBegeniler.map((e) => e['ilan_id'] as String).toSet();

        // Repostlarım (Ben bu ilanı repost ettim mi?)
        final userRepostlar = await supabase.from('repostlar').select('ilan_id').eq('kullanici_id', user.id).inFilter('ilan_id', tumIlanIdleri);
        cekilenRepostlarim = userRepostlar.map((e) => e['ilan_id'] as String).toSet();
      }

      // Sayaçlar
      final Map<String, int> begeniSayiMap = {};
      final Map<String, int> yorumSayiMap = {};

      if (tumIlanIdleri.isNotEmpty) {
        // Beğeni Sayıları
        final begeniDatasi = await supabase.from('begeniler').select('ilan_id').inFilter('ilan_id', tumIlanIdleri);
        for(var b in begeniDatasi) {
          final id = b['ilan_id'] as String;
          begeniSayiMap[id] = (begeniSayiMap[id] ?? 0) + 1;
        }

        // Yorum Sayıları
        final yorumDatasi = await supabase.from('yorumlar').select('ilan_id').inFilter('ilan_id', tumIlanIdleri);
        for(var y in yorumDatasi) {
          final id = y['ilan_id'] as String;
          yorumSayiMap[id] = (yorumSayiMap[id] ?? 0) + 1;
        }
      }

      // 4. Veri Birleştirme
      final Map<String, Map<String, dynamic>> tumIlanlarMap = {};
      void listeyiIsle(List list, String tip, Map fotos) {
        for(var i in list) {
          final m = i as Map<String, dynamic>;
          m['tip'] = tip; m['repost'] = false; m['fotolar'] = fotos[m['id']] ?? [];
          tumIlanlarMap[m['id']] = m;
        }
      }
      listeyiIsle(kayipIlanlar, 'kayip', kayipFotolar);
      listeyiIsle(bulunanIlanlar, 'bulunan', bulunanFotolar);
      listeyiIsle(sahiplendirmeIlanlar, 'sahiplendirme', sahiplendirmeFotolar);

      // Repost Eksiklerini Tamamlama
      List<String> eksikKayip = [];
      List<String> eksikBulunan = [];
      List<String> eksikSahip = [];

      for(var repost in repostlar) {
        if(!tumIlanlarMap.containsKey(repost['ilan_id'])) {
          if(repost['ilan_tipi'] == 'kayip') eksikKayip.add(repost['ilan_id']);
          if(repost['ilan_tipi'] == 'bulunan') eksikBulunan.add(repost['ilan_id']);
          if(repost['ilan_tipi'] == 'sahiplendirme') eksikSahip.add(repost['ilan_id']);
        }
      }

      if(eksikKayip.isNotEmpty) {
        final eksikler = await supabase.from('kayip_ilanlar').select(_KAYIP_ILAN_FIELDS).inFilter('id', eksikKayip);
        final fotos = await _ilanFotograflariniGetir(eksikKayip, 'kayip');
        listeyiIsle(eksikler, 'kayip', fotos);
      }
      if(eksikBulunan.isNotEmpty) {
        final eksikler = await supabase.from('bulunan_ilanlar').select(_BULUNAN_ILAN_FIELDS).inFilter('id', eksikBulunan);
        final fotos = await _ilanFotograflariniGetir(eksikBulunan, 'bulunan');
        listeyiIsle(eksikler, 'bulunan', fotos);
      }
      if(eksikSahip.isNotEmpty) {
        final eksikler = await supabase.from('sahiplendirme_ilanlar').select(_SAHIPLENDIRME_ILAN_FIELDS).inFilter('id', eksikSahip);
        final fotos = await _ilanFotograflariniGetir(eksikSahip, 'sahiplendirme');
        listeyiIsle(eksikler, 'sahiplendirme', fotos);
      }

      // Akış Listesi
      final List<Map<String, dynamic>> akis = [];
      tumIlanlarMap.forEach((k, v) {
        if (v['repost'] == false && takipEdilenIdList.contains(v['kullanici_id'])) akis.add(v);
      });

      for (var r in repostlar) {
        final ilanId = r['ilan_id'];
        if (tumIlanlarMap.containsKey(ilanId)) {
          final orj = tumIlanlarMap[ilanId]!;
          akis.add({
            ...orj,
            'repost': true,
            'repost_yapan_id': r['kullanici_id'],
            'repost_tarihi': r['created_at'],
            'orijinal_sahip_id': orj['kullanici_id'],
          });
        }
      }

      akis.sort((a, b) {
        final dateA = DateTime.parse(a['repost'] ? a['repost_tarihi'] : a['created_at']);
        final dateB = DateTime.parse(b['repost'] ? b['repost_tarihi'] : b['created_at']);
        return dateB.compareTo(dateA);
      });

      if (!mounted) return;
      setState(() {
        _akisIlanlari = akis;
        _begendiklerim = cekilenBegendiklerim;
        _repostladiklarim = cekilenRepostlarim;
        _begeniSayilari = begeniSayiMap;
        _yorumSayilari = yorumSayiMap;
        _isLoading = false;
      });

    } catch (e) {
      print('Akış hatası: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _begenmeIslemi(String ilanId, String ilanTipi) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final bool zatenBegendi = _begendiklerim.contains(ilanId);

    setState(() {
      if (zatenBegendi) {
        _begendiklerim.remove(ilanId);
        _begeniSayilari[ilanId] = (_begeniSayilari[ilanId] ?? 1) - 1;
      } else {
        _begendiklerim.add(ilanId);
        _begeniSayilari[ilanId] = (_begeniSayilari[ilanId] ?? 0) + 1;
      }
    });

    try {
      if (zatenBegendi) {
        await supabase.from('begeniler').delete().eq('kullanici_id', user.id).eq('ilan_id', ilanId);
      } else {
        await supabase.from('begeniler').insert({'kullanici_id': user.id, 'ilan_id': ilanId, 'ilan_tipi': ilanTipi});
      }
    } catch (e) {
      // Hata olursa geri al
      setState(() {
        if (zatenBegendi) {
          _begendiklerim.add(ilanId);
          _begeniSayilari[ilanId] = (_begeniSayilari[ilanId] ?? 0) + 1;
        } else {
          _begendiklerim.remove(ilanId);
          _begeniSayilari[ilanId] = (_begeniSayilari[ilanId] ?? 1) - 1;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İşlem başarısız')));
    }
  }

  //  REPOST (YENİDEN PAYLAŞMA) İŞLEMİ
  Future<void> _repostIslemi(String ilanId, String ilanTipi) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final bool zatenRepostladi = _repostladiklarim.contains(ilanId);

    setState(() {
      if (zatenRepostladi) {
        _repostladiklarim.remove(ilanId);
      } else {
        _repostladiklarim.add(ilanId);
      }
    });

    try {
      if (zatenRepostladi) {
        await supabase.from('repostlar')
            .delete()
            .eq('kullanici_id', user.id)
            .eq('ilan_id', ilanId);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yeniden paylaşım kaldırıldı'), duration: Duration(seconds: 1)),
        );
      } else {
        await supabase.from('repostlar').insert({
          'kullanici_id': user.id,
          'ilan_id': ilanId,
          'ilan_tipi': ilanTipi,
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [Icon(Icons.repeat, color: Colors.white), SizedBox(width: 8), Text('Profilinde yeniden paylaşıldı!')]),
            backgroundColor: TEMA_YESIL,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() {
        if (zatenRepostladi) _repostladiklarim.add(ilanId);
        else _repostladiklarim.remove(ilanId);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İşlem başarısız')));
    }
  }

  void _yorumPenceresiniAc(BuildContext context, String ilanId, String ilanTipi) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _YorumlarModal(ilanId: ilanId, ilanTipi: ilanTipi),
    ).then((_) {
      _loadAkis();
    });
  }

  // PAYLAŞIM ÖZELLİĞİ
  void _paylasIslemi(Map<String, dynamic> ilan) {
    final String tip = ilan['tip'];
    final StringBuffer buffer = StringBuffer();

    if (tip == 'kayip') buffer.writeln("📢 KAYIP İLANI! 🆘");
    else if (tip == 'bulunan') buffer.writeln("📢 BULUNDU! 🏠");
    else buffer.writeln("📢 SAHİPLENDİRME İLANI! 🏡");

    buffer.writeln("");

    if (ilan['hayvan_adi'] != null) buffer.writeln("🐾 İsim: ${ilan['hayvan_adi']}");
    if (ilan['hayvan_turu'] != null) buffer.writeln("🐶 Tür: ${ilan['hayvan_turu']}");
    if (ilan['hayvan_cinsiyeti'] != null) buffer.writeln("⚧ Cinsiyet: ${ilan['hayvan_cinsiyeti']}");
    if (ilan['hayvan_rengi'] != null) buffer.writeln("🎨 Renk: ${ilan['hayvan_rengi']}");

    if (ilan['cipi_var_mi'] == true) buffer.writeln("✅ Çipi Var");

    if (tip == 'sahiplendirme') {
      if (ilan['kisir_mi'] == true) buffer.writeln("✅ Kısırlaştırılmış");
      if (ilan['kisirlastirma_sarti'] == true) buffer.writeln("❗ Kısırlaştırma Şartı Var");
      if (ilan['aliskanliklar'] != null && ilan['aliskanliklar'].toString().isNotEmpty) {
        buffer.writeln("\n📜 Alışkanlıklar:\n${ilan['aliskanliklar']}");
      }
    }

    if (ilan['konum_text'] != null && ilan['konum_text'].toString().isNotEmpty) {
      buffer.writeln("\n📍 Konum: ${ilan['konum_text']}");
    }

    if (ilan['ekstra_bilgi'] != null && ilan['ekstra_bilgi'].toString().isNotEmpty) {
      buffer.writeln("\n📝 Açıklama:\n${ilan['ekstra_bilgi']}");
    }

    buffer.writeln("\n📲 Bu ilan CanBul uygulamasında görüldü. Detaylar için uygulamayı indir!");

    Clipboard.setData(ClipboardData(text: buffer.toString())).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [Icon(Icons.content_copy, color: Colors.white), SizedBox(width: 10), Text("Tüm ilan bilgileri kopyalandı!")]),
          backgroundColor: TEMA_YESIL,
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  void _profilSayfasinaYonlendir(String kullaniciId) {
    final currentUser = supabase.auth.currentUser;
    if (currentUser != null && currentUser.id == kullaniciId) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const Profil()));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (context) => KullaniciProfili(kullaniciId: kullaniciId)));
    }
  }

  void _ilanDetayinaYonlendir(Map<String, dynamic> ilan) async {
    try {
      final String ilanId = ilan['id'];
      final String ilanTipi = ilan['tip'];
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
        selectQuery = 'id, kullanici_id, hayvan_adi, hayvan_turu, hayvan_rengi, hayvan_cinsiyeti, cipi_var_mi, kisir_mi, kisirlastirma_sarti, aliskanliklar, ekstra_bilgi, created_at, konum, konum_text, profiles(tam_ad, telefon)';
      }

      final ilanDetay = await supabase.from(tabloAdi).select(selectQuery).eq('id', ilanId).maybeSingle();
      if (ilanDetay == null) return;

      final List<dynamic> fotos = await supabase.from('ilan_fotograflari').select('foto_url').eq('ilan_id', ilanId).eq('ilan_tipi', ilanTipi).order('created_at', ascending: true);
      final List<String> fotoUrls = fotos.map((e) => e['foto_url'] as String).toList();
      final profileData = ilanDetay['profiles'] as Map<String, dynamic>?;

      final Ilan ilanNesnesi = Ilan.fromMap(
        data: ilanDetay,
        tip: ilanTipi,
        fotoUrls: fotoUrls,
        kullaniciTel: profileData?['telefon'] ?? 'Numara Yok',
        kullaniciAd: profileData?['tam_ad'] ?? 'Anonim Kullanıcı',
        isRepost: ilan['repost'] == true,
      );

      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => IlanDetaySayfasi(ilan: ilanNesnesi)));
      }
    } catch (e) {
      print('Detay yönlendirme hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: TEMA_YESIL));
    if (_akisIlanlari.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pets, size: 64, color: KART_GRI.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text("Akışta henüz bir şey yok.", style: TextStyle(color: KART_GRI)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAkis,
      color: TEMA_YESIL,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _akisIlanlari.length,
        itemBuilder: (context, index) {
          final ilan = _akisIlanlari[index];
          final String ilanId = ilan['id'];
          final String ilanTipi = ilan['tip'];
          final bool isRepost = ilan['repost'] == true;

          final profil = _kullaniciProfilleri[ilan['kullanici_id']];
          final String ad = profil?['tam_ad'] ?? 'Bilinmeyen';
          final String? fotoUrl = profil?['profil_foto_guvenli_url'];

          final List<String> fotolar = (ilan['fotolar'] as List?)?.cast<String>() ?? [];
          final bool begenildi = _begendiklerim.contains(ilanId);
          final bool repostlandi = _repostladiklarim.contains(ilanId);

          final int begeniSayisi = _begeniSayilari[ilanId] ?? 0;
          final int yorumSayisi = _yorumSayilari[ilanId] ?? 0;

          Color cerceveRengi = TEMA_LACIVERT;
          if (ilanTipi == 'kayip') cerceveRengi = KART_KAYIP_K;
          else if (ilanTipi == 'bulunan') cerceveRengi = KART_BULUNAN_Y;

          return Card(
            elevation: 4,
            margin: const EdgeInsets.only(bottom: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: isRepost ? KART_REPOST_M : cerceveRengi.withOpacity(0.5), width: 3),
            ),
            child: InkWell(
              onTap: () => _ilanDetayinaYonlendir(ilan),
              borderRadius: BorderRadius.circular(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Repost Bilgisi
                  if(isRepost)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          const Icon(Icons.repeat, size: 16, color: KART_REPOST_M),
                          const SizedBox(width: 5),
                          Text("${_kullaniciProfilleri[ilan['repost_yapan_id']]?['tam_ad']} paylaştı", style: const TextStyle(color: KART_REPOST_M, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),

                  // Profil Satırı
                  ListTile(
                    leading: GestureDetector(
                      onTap: () => _profilSayfasinaYonlendir(ilan['kullanici_id']),
                      child: CircleAvatar(
                        backgroundImage: fotoUrl != null ? NetworkImage(fotoUrl) : null,
                        backgroundColor: cerceveRengi.withOpacity(0.2),
                        child: fotoUrl == null ? Icon(Icons.person, color: cerceveRengi) : null,
                      ),
                    ),
                    title: GestureDetector(
                      onTap: () => _profilSayfasinaYonlendir(ilan['kullanici_id']),
                      child: Text(ad, style: const TextStyle(fontWeight: FontWeight.bold, color: TEMA_LACIVERT)),
                    ),
                    subtitle: Text(ilanTipi.toUpperCase(), style: TextStyle(color: cerceveRengi, fontSize: 12)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: KART_GRI),
                  ),

                  // Fotoğraf
                  if (fotolar.isNotEmpty)
                    SizedBox(
                      height: 300,
                      width: double.infinity,
                      child: PageView.builder(
                        itemCount: fotolar.length,
                        itemBuilder: (context, i) => Image.network(fotolar[i], fit: BoxFit.cover),
                      ),
                    ),

                  // İlan Açıklaması
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (ilan['hayvan_adi'] != null) Text(ilan['hayvan_adi'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: TEMA_LACIVERT)),
                        const SizedBox(height: 4),
                        Text(ilan['ekstra_bilgi'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),

                  // Alt Butonlar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _begenmeIslemi(ilanId, ilanTipi),
                          child: Row(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Icon(
                                  begenildi ? Icons.favorite : Icons.favorite_border,
                                  color: begenildi ? Colors.red : KART_GRI,
                                  size: 28,
                                ),
                              ),
                              Text('$begeniSayisi', style: const TextStyle(fontWeight: FontWeight.bold, color: KART_GRI)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => _yorumPenceresiniAc(context, ilanId, ilanTipi),
                          child: Row(
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Icon(Icons.comment_outlined, color: TEMA_LACIVERT, size: 26),
                              ),
                              Text('$yorumSayisi', style: const TextStyle(fontWeight: FontWeight.bold, color: KART_GRI)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: Icon(Icons.repeat, color: repostlandi ? KART_REPOST_M : KART_GRI, size: 28),
                          onPressed: () => _repostIslemi(ilanId, ilanTipi),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.share_outlined, color: KART_GRI, size: 26),
                          onPressed: () => _paylasIslemi(ilan),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

//  YORUM PENCERESİ
class _YorumlarModal extends StatefulWidget {
  final String ilanId;
  final String ilanTipi;
  const _YorumlarModal({required this.ilanId, required this.ilanTipi});

  @override
  State<_YorumlarModal> createState() => _YorumlarModalState();
}

class _YorumlarModalState extends State<_YorumlarModal> {
  final TextEditingController _yorumController = TextEditingController();
  bool _gonderiliyor = false;

  Stream<List<Map<String, dynamic>>> _yorumlariGetir() {
    return supabase.from('yorumlar')
        .stream(primaryKey: ['id'])
        .eq('ilan_id', widget.ilanId)
        .order('created_at', ascending: true)
        .map((data) => List<Map<String, dynamic>>.from(data));
  }

  Future<Map<String, dynamic>?> _profilGetir(String kullaniciId) async {
    try {
      final data = await supabase.from('profiles').select('tam_ad, profil_foto').eq('id', kullaniciId).single();
      final String? dosyaYolu = data['profil_foto'];
      if (dosyaYolu != null && dosyaYolu.isNotEmpty) {
        final String url = await supabase.storage.from('profil_fotolari').createSignedUrl(dosyaYolu, 60);
        data['profil_foto_url'] = url;
      }
      return data;
    } catch(e) { return null; }
  }

  void _profilYonlendirme(String targetUserId) {
    final currentUser = supabase.auth.currentUser;
    if (currentUser != null && currentUser.id == targetUserId) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const Profil()));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (context) => KullaniciProfili(kullaniciId: targetUserId)));
    }
  }

  Future<void> _yorumGonder() async {
    final text = _yorumController.text.trim();
    if (text.isEmpty) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _gonderiliyor = true);
    try {
      await supabase.from('yorumlar').insert({
        'kullanici_id': user.id,
        'ilan_id': widget.ilanId,
        'ilan_tipi': widget.ilanTipi,
        'yorum': text
      });
      _yorumController.clear();
      FocusScope.of(context).unfocus();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Yorum gönderilemedi.')));
    } finally {
      if(mounted) setState(() => _gonderiliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(color: ARKA_PLAN_BEYAZ, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        children: [
          Center(child: Container(margin: const EdgeInsets.only(top: 12, bottom: 8), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
          const Text("Yorumlar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: TEMA_LACIVERT)),
          const Divider(),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _yorumlariGetir(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: TEMA_YESIL));
                final yorumlar = snapshot.data!;
                if (yorumlar.isEmpty) return const Center(child: Text("Henüz yorum yok.", style: TextStyle(color: KART_GRI)));

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: yorumlar.length,
                  itemBuilder: (context, index) {
                    final yorum = yorumlar[index];
                    final yorumYapanId = yorum['kullanici_id'];

                    return FutureBuilder<Map<String, dynamic>?>(
                      future: _profilGetir(yorumYapanId),
                      builder: (context, profilSnapshot) {
                        final profil = profilSnapshot.data;
                        final ad = profil?['tam_ad'] ?? 'Kullanıcı';
                        final fotoUrl = profil?['profil_foto_url'];

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () => _profilYonlendirme(yorumYapanId),
                                child: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: TEMA_YESIL.withOpacity(0.1),
                                  backgroundImage: fotoUrl != null ? NetworkImage(fotoUrl) : null,
                                  child: fotoUrl == null ? const Icon(Icons.person, size: 20, color: TEMA_YESIL) : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    GestureDetector(
                                      onTap: () => _profilYonlendirme(yorumYapanId),
                                      child: Text(ad, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(timeago.format(DateTime.parse(yorum['created_at']), locale: 'tr'), style: TextStyle(color: Colors.grey[600], fontSize: 12))
                                  ]),
                                  const SizedBox(height: 2),
                                  Text(yorum['yorum'] as String, style: const TextStyle(fontSize: 15)),
                                ]),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16, left: 16, right: 16, top: 8),
            child: Row(children: [
              Expanded(child: TextField(
                  controller: _yorumController,
                  decoration: InputDecoration(hintText: 'Yorum yap...', filled: true, fillColor: Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10))
              )),
              const SizedBox(width: 8),
              IconButton(
                  onPressed: _gonderiliyor ? null : _yorumGonder,
                  icon: _gonderiliyor ? const CircularProgressIndicator(strokeWidth: 2, color: TEMA_YESIL) : const Icon(Icons.send, color: TEMA_YESIL)
              )
            ]),
          ),
        ],
      ),
    );
  }
}