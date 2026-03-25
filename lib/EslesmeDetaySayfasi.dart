import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Proje içi importlar
import 'ilanlar.dart';

// --- RENK SABİTLERİ ---
const Color zeytinYesili = Color(0xFF558B2F);
const Color lacivert = Color(0xFF002D72);
const Color sariPastel = Color(0xFFFFB74D);
const Color arkaPlan = Color(0xFFF1F8E9);

class EslesmeDetaySayfasi extends StatefulWidget {
  final Map<String, dynamic> grupVerisi;

  const EslesmeDetaySayfasi({super.key, required this.grupVerisi});

  @override
  State<EslesmeDetaySayfasi> createState() => _EslesmeDetaySayfasiState();
}

class _EslesmeDetaySayfasiState extends State<EslesmeDetaySayfasi> {
  // Gizlenen ilanların ID'lerini telefonun hafızasında tutacağımız liste
  Set<String> _gizlenenIlanlar = {};

  // Üstteki göz ikonunun durumu (Gizlileri göster/gösterme)
  bool _gizlileriGoster = false;

  bool _hafizaYukleniyor = true;

  @override
  void initState() {
    super.initState();
    _hafizadanGizlenenleriGetir();
  }

  // Telefonun yerel hafızasından (Local Storage) gizlenmiş ilanları okuyan fonksiyon
  Future<void> _hafizadanGizlenenleriGetir() async {
    final prefs = await SharedPreferences.getInstance();
    final kullaniciId = Supabase.instance.client.auth.currentUser?.id ?? 'anonim';

    // Her kullanıcıya özel bir hafıza anahtarı ile veriyi çekiyoruz
    final List<String> kayitliListe = prefs.getStringList('gizli_ilanlar_$kullaniciId') ?? [];

    setState(() {
      _gizlenenIlanlar = kayitliListe.toSet();
      _hafizaYukleniyor = false;
    });
  }

  // Gizle/Göster butonuna basıldığında hem ekranı hem hafızayı güncelleyen fonksiyon
  Future<void> _gizleDurumunuDegistir(String bulunanId, bool suAnGizliMi) async {
    final prefs = await SharedPreferences.getInstance();
    final kullaniciId = Supabase.instance.client.auth.currentUser?.id ?? 'anonim';

    setState(() {
      if (suAnGizliMi) {
        _gizlenenIlanlar.remove(bulunanId);
      } else {
        _gizlenenIlanlar.add(bulunanId);
      }
    });

    // Güncel listeyi telefonun hafızasına kalıcı olarak kaydet
    await prefs.setStringList('gizli_ilanlar_$kullaniciId', _gizlenenIlanlar.toList());
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> tumEslesmeler = widget.grupVerisi['eslesmeler'];

    final List<Map<String, dynamic>> gosterilecekEslesmeler = tumEslesmeler.where((eslesme) {
      final String bulunanId = eslesme['bulunan_ilan_id'].toString();
      final bool gizliMi = _gizlenenIlanlar.contains(bulunanId);

      if (_gizlileriGoster) {
        return true;
      } else {
        return !gizliMi;
      }
    }).toList();

    return Scaffold(
      backgroundColor: arkaPlan,
      appBar: AppBar(
        title: const Text("Tüm Eşleşmeler"),
        backgroundColor: sariPastel,
        foregroundColor: Colors.black,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _gizlileriGoster ? Icons.visibility : Icons.visibility_off,
              color: Colors.black87,
            ),
            tooltip: _gizlileriGoster ? "Gizlenenleri Kapat" : "Gizlenenleri Göster",
            onPressed: () {
              setState(() {
                _gizlileriGoster = !_gizlileriGoster;
              });
            },
          )
        ],
      ),
      body: _hafizaYukleniyor
          ? const Center(child: CircularProgressIndicator(color: zeytinYesili))
          : gosterilecekEslesmeler.isEmpty
          ? const Center(child: Text("Gösterilecek eşleşme bulunmuyor."))
          : ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 10),
        itemCount: gosterilecekEslesmeler.length,
        itemBuilder: (context, index) {
          final eslesmeVerisi = gosterilecekEslesmeler[index];
          final String bulunanId = eslesmeVerisi['bulunan_ilan_id'].toString();
          final bool gizliMi = _gizlenenIlanlar.contains(bulunanId);

          return _EslesmeKarti(
            key: ValueKey(bulunanId),
            eslesmeVerisi: eslesmeVerisi,
            sira: index + 1,
            gizliMi: gizliMi,
            onGizleTetiklendi: () => _gizleDurumunuDegistir(bulunanId, gizliMi),
          );
        },
      ),
    );
  }
}

// --- EŞLEŞME KARTI WIDGET'I ---
class _EslesmeKarti extends StatefulWidget {
  final Map<String, dynamic> eslesmeVerisi;
  final int sira;
  final bool gizliMi;
  final VoidCallback onGizleTetiklendi;

  const _EslesmeKarti({
    super.key,
    required this.eslesmeVerisi,
    required this.sira,
    required this.gizliMi,
    required this.onGizleTetiklendi,
  });

  @override
  State<_EslesmeKarti> createState() => _EslesmeKartiState();
}

class _EslesmeKartiState extends State<_EslesmeKarti> {
  String? _kayipFotoUrl;
  String? _bulunanFotoUrl;
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _fotolariHazirla();
  }

  Future<void> _fotolariHazirla() async {
    try {
      final kaynakRes = await Supabase.instance.client
          .from('ilan_fotograflari')
          .select('foto_url')
          .eq('ilan_id', widget.eslesmeVerisi['kayip_ilan_id'])
          .limit(1)
          .maybeSingle();

      final hedefRes = await Supabase.instance.client
          .from('ilan_fotograflari')
          .select('foto_url')
          .eq('ilan_id', widget.eslesmeVerisi['bulunan_ilan_id'])
          .limit(1)
          .maybeSingle();

      const String kovaAdi = 'hayvan_fotograflari';

      String? yolTemizle(String? tamUrl) {
        if (tamUrl == null) return null;
        if (tamUrl.contains('$kovaAdi/')) return tamUrl.split('$kovaAdi/').last;
        return tamUrl;
      }

      String? geciciKayipUrl;
      String? geciciBulunanUrl;

      if (kaynakRes != null && kaynakRes['foto_url'] != null) {
        String temizYol = yolTemizle(kaynakRes['foto_url'].toString())!;
        geciciKayipUrl = await Supabase.instance.client.storage.from(kovaAdi).createSignedUrl(temizYol, 3600);
      }

      if (hedefRes != null && hedefRes['foto_url'] != null) {
        String temizYol = yolTemizle(hedefRes['foto_url'].toString())!;
        geciciBulunanUrl = await Supabase.instance.client.storage.from(kovaAdi).createSignedUrl(temizYol, 3600);
      }

      if (mounted) {
        setState(() {
          _kayipFotoUrl = geciciKayipUrl;
          _bulunanFotoUrl = geciciBulunanUrl;
          _yukleniyor = false;
        });
      }
    } catch (hata) {
      debugPrint("Fotoğraf Çekme Hatası: $hata");
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _karsiBulunanIlaninaGit() async {
    try {
      final String karsiIlanId = widget.eslesmeVerisi['bulunan_ilan_id'].toString();

      final ilanDetay = await Supabase.instance.client.from('bulunan_ilanlar').select('id, kullanici_id, hayvan_turu, hayvan_rengi, hayvan_cinsiyeti, ekstra_bilgi, konum, konum_text, created_at, profiles(tam_ad, telefon)').eq('id', karsiIlanId).maybeSingle();

      if (ilanDetay == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bu ilan sistemden kaldırılmış olabilir.")));
        return;
      }

      final List<dynamic> fotos = await Supabase.instance.client.from('ilan_fotograflari').select('foto_url').eq('ilan_id', karsiIlanId).eq('ilan_tipi', 'bulunan');
      final List<String> fotoUrls = fotos.map((e) => e['foto_url'] as String).toList();

      final profileData = ilanDetay['profiles'] as Map<String, dynamic>?;

      final Ilan ilanNesnesi = Ilan.fromMap(
        data: ilanDetay,
        tip: 'bulunan',
        fotoUrls: fotoUrls,
        kullaniciTel: profileData?['telefon'] ?? '',
        kullaniciAd: profileData?['tam_ad'] ?? 'Kullanıcı',
      );

      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => IlanDetaySayfasi(ilan: ilanNesnesi)));
      }
    } catch (e) {
      debugPrint("Detay Yönlendirme Hatası: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("İlan detayları yüklenirken bir hata oluştu.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? benimFotoUrl = _kayipFotoUrl;
    final String? karsiFotoUrl = _bulunanFotoUrl;

    // Gizli olan kartları soluk (opacity: 0.5) gösteriyoruz
    return Opacity(
      opacity: widget.gizliMi ? 0.5 : 1.0,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        elevation: widget.gizliMi ? 0 : 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // --- SKOR VE MESAFE BÖLÜMÜ ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: sariPastel,
                        radius: 14,
                        child: Text("${widget.sira}", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "Benzerlik: %${((widget.eslesmeVerisi['eslesme_skoru'] ?? 0) * 100).toStringAsFixed(1)}",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: sariPastel),
                      ),
                    ],
                  ),
                  // Mesafe bilgisini tekrar ekledik!
                  Text(
                    "${widget.eslesmeVerisi['mesafe_km'] ?? '??'} km",
                    style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              const Divider(height: 30),

              Row(
                children: [
                  _fotoKutusu("Senin İlanın", benimFotoUrl),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Icon(Icons.compare_arrows, color: zeytinYesili, size: 26),
                  ),
                  _fotoKutusu("Potansiyel Eşleşme", karsiFotoUrl),
                ],
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: zeytinYesili,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: widget.gizliMi ? null : _karsiBulunanIlaninaGit,
                  child: const Text("Hayvanı Bulan Kişinin İlanına Git", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                height: 35,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.gizliMi ? Colors.blueAccent : Colors.redAccent,
                    side: BorderSide(color: widget.gizliMi ? Colors.blueAccent : Colors.redAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: Icon(widget.gizliMi ? Icons.restore : Icons.visibility_off, size: 18),
                  label: Text(widget.gizliMi ? "Gizlemeyi Kaldır" : "Bu Benim Hayvanım Değil (Gizle)"),
                  onPressed: widget.onGizleTetiklendi,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fotoKutusu(String baslik, String? url) {
    return Expanded(
      child: Column(
        children: [
          Text(baslik, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          Container(
            height: 140,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
              image: url != null ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
            ),
            child: url == null
                ? Center(child: _yukleniyor ? const CircularProgressIndicator(color: zeytinYesili) : const Icon(Icons.broken_image, size: 30, color: Colors.grey))
                : null,
          ),
        ],
      ),
    );
  }
}