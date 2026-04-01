import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';


import 'shared_bottom_nav.dart';
import 'kullanici_profili.dart';

final supabase = Supabase.instance.client;


const Color zeytinYesili = Color(0xFF558B2F);
const Color turuncuPastel = Color(0xFFFFB74D);
const Color arkaPlan = Color(0xFFF1F8E9);
const Color beyaz = Colors.white;
const Color gri = Color(0xFF9E9E9E);
const Color lacivert = Color(0xFF1E3A8A);
const Color maviTik = Color(0xFF2196F3);



class MesajlarSayfasi extends StatefulWidget {
  const MesajlarSayfasi({super.key});

  @override
  State<MesajlarSayfasi> createState() => _MesajlarSayfasiState();
}

class _MesajlarSayfasiState extends State<MesajlarSayfasi> {
  final String _aktifKullaniciId = supabase.auth.currentUser!.id;

  final TextEditingController _aramaController = TextEditingController();
  List<Map<String, dynamic>> _aramaSonuclari = [];
  bool _aramaAktifMi = false;

  @override
  void initState() {
    super.initState();
  }


  Future<void> _anlikKullaniciAra(String aramaMetni) async {
    final text = aramaMetni.trim();
    if (text.isEmpty) {
      setState(() {
        _aramaAktifMi = false;
        _aramaSonuclari = [];
      });
      return;
    }
    setState(() => _aramaAktifMi = true);
    try {
      final response = await supabase
          .from('profiles')
          .select('id, tam_ad, profil_foto')
          .ilike('tam_ad', '%$text%')
          .neq('id', _aktifKullaniciId)
          .limit(10);
      if (mounted) setState(() => _aramaSonuclari = List<Map<String, dynamic>>.from(response));
    } catch (e) {
      print("Arama hatası: $e");
    }
  }

  Widget _buildAvatar(String? fotoPath, String ad) {
    if (fotoPath == null) {
      return CircleAvatar(
        radius: 28,
        backgroundColor: turuncuPastel.withOpacity(0.2),
        child: Text(ad.isNotEmpty ? ad[0].toUpperCase() : '?',
            style: const TextStyle(color: zeytinYesili, fontWeight: FontWeight.bold)),
      );
    }
    return FutureBuilder<String>(
      future: supabase.storage.from('profil_fotolari').createSignedUrl(fotoPath, 60),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return CircleAvatar(
              radius: 28, backgroundColor: Colors.transparent, backgroundImage: NetworkImage(snapshot.data!));
        }
        return CircleAvatar(
            radius: 28,
            backgroundColor: turuncuPastel.withOpacity(0.2),
            child: const CircularProgressIndicator(color: zeytinYesili, strokeWidth: 2));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: arkaPlan,
      appBar: AppBar(
        title: const Text('Mesajlar', style: TextStyle(color: beyaz, fontWeight: FontWeight.bold)),
        backgroundColor: zeytinYesili,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: beyaz),
          onPressed: () => Navigator.pop(context),
        ),      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: zeytinYesili,
            child: TextField(
              controller: _aramaController,
              onChanged: _anlikKullaniciAra,
              style: const TextStyle(color: zeytinYesili),
              decoration: InputDecoration(
                hintText: 'Sohbet veya kişi ara...',
                hintStyle: TextStyle(color: gri),
                prefixIcon: const Icon(Icons.search, color: zeytinYesili),
                filled: true,
                fillColor: beyaz,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                suffixIcon: _aramaAktifMi
                    ? IconButton(
                    icon: const Icon(Icons.close, color: gri),
                    onPressed: () {
                      _aramaController.clear();
                      _anlikKullaniciAra('');
                    })
                    : null,
              ),
            ),
          ),
          Expanded(
            child: _aramaAktifMi
                ? (_aramaSonuclari.isEmpty
                ? Center(child: Text('Sonuç bulunamadı.', style: TextStyle(color: gri)))
                : ListView.builder(
              itemCount: _aramaSonuclari.length,
              itemBuilder: (context, index) {
                final user = _aramaSonuclari[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: ListTile(
                    leading: _buildAvatar(user['profil_foto'], user['tam_ad'] ?? ''),
                    title: Text(user['tam_ad'] ?? 'İsimsiz',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: lacivert)),
                    subtitle: const Text("Sohbeti başlat"),
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => SohbetEkrani(
                                  aliciId: user['id'],
                                  aliciAd: user['tam_ad'] ?? 'İsimsiz',
                                  aliciFotoUrl: null)));
                    },
                  ),
                );
              },
            ))
                : StreamBuilder<List<Map<String, dynamic>>>(
              stream: supabase
                  .from('mesajlar')
                  .stream(primaryKey: ['id'])
                  .order('created_at', ascending: false)
                  .map((data) => data),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text('Hata oluştu'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: zeytinYesili));

                final tumMesajlar = snapshot.data!;
                final Map<String, Map<String, dynamic>> sohbetMap = {};

                for (var mesaj in tumMesajlar) {
                  final String gonderen = mesaj['gonderen_id'];
                  final String alici = mesaj['alici_id'];
                  if (gonderen != _aktifKullaniciId && alici != _aktifKullaniciId) continue;

                  final String karsiTarafId = (gonderen == _aktifKullaniciId) ? alici : gonderen;

                  if (!sohbetMap.containsKey(karsiTarafId)) {
                    sohbetMap[karsiTarafId] = {
                      'karsi_taraf_id': karsiTarafId,
                      'son_mesaj': mesaj['mesaj'] ?? '',
                      'tarih': mesaj['created_at'],
                      'ben_mi_attim': (gonderen == _aktifKullaniciId),
                      'okunmamis_sayisi': 0,
                    };
                  }
                  if (alici == _aktifKullaniciId && (mesaj['okundu'] == false || mesaj['okundu'] == null)) {
                    sohbetMap[karsiTarafId]!['okunmamis_sayisi'] += 1;
                  }
                }

                final sohbetListesi = sohbetMap.values.toList();
                if (sohbetListesi.isEmpty) {
                  return Center(child: Text("Henüz sohbetin yok.", style: TextStyle(color: gri)));
                }

                return ListView.builder(
                  itemCount: sohbetListesi.length,
                  itemBuilder: (context, index) {
                    final sohbet = sohbetListesi[index];
                    final String karsiId = sohbet['karsi_taraf_id'];
                    final int okunmamis = sohbet['okunmamis_sayisi'];
                    final tarih = DateTime.parse(sohbet['tarih']).add(const Duration(hours: 3));
                    final saatFormat = DateFormat.Hm().format(tarih);

                    return FutureBuilder<Map<String, dynamic>>(
                      future: supabase.from('profiles').select('tam_ad, profil_foto').eq('id', karsiId).single(),
                      builder: (context, profilSnapshot) {
                        String ad = 'Yükleniyor...';
                        String? fotoPath;
                        if (profilSnapshot.hasData) {
                          ad = profilSnapshot.data!['tam_ad'] ?? 'İsimsiz';
                          fotoPath = profilSnapshot.data!['profil_foto'];
                        }

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          elevation: 2,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Stack(
                              children: [
                                _buildAvatar(fotoPath, ad),
                                if (okunmamis > 0)
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                      child: Text('$okunmamis',
                                          style: const TextStyle(
                                              color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(ad,
                                style: TextStyle(
                                    fontWeight: okunmamis > 0 ? FontWeight.bold : FontWeight.w600,
                                    color: lacivert)),
                            subtitle: Text(sohbet['son_mesaj'],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: okunmamis > 0 ? Colors.black87 : Colors.grey.shade700,
                                    fontWeight: okunmamis > 0 ? FontWeight.bold : FontWeight.normal)),
                            trailing: Text(saatFormat, style: TextStyle(color: gri, fontSize: 12)),
                            onTap: () {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          SohbetEkrani(aliciId: karsiId, aliciAd: ad, aliciFotoUrl: null)));
                            },
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar:
      const SharedBottomNavBar(currentIndex: 0, turuncuPastel: turuncuPastel, gri: gri, beyaz: beyaz),
    );
  }
}



class SohbetEkrani extends StatefulWidget {
  final String aliciId;
  final String aliciAd;
  final String? aliciFotoUrl;
  final String? baslangicMesaji;

  const SohbetEkrani(
      {super.key, required this.aliciId, required this.aliciAd, this.aliciFotoUrl, this.baslangicMesaji});

  @override
  State<SohbetEkrani> createState() => _SohbetEkraniState();
}

class _SohbetEkraniState extends State<SohbetEkrani> {
  final TextEditingController _mesajController = TextEditingController();
  final String _benimId = supabase.auth.currentUser!.id;
  final ScrollController _scrollController = ScrollController();
  String? _guncelFotoUrl;


  final String _silinmisMesajMetni = '🚫 Bu mesaj silindi';

  @override
  void initState() {
    super.initState();
    if (widget.baslangicMesaji != null) _mesajController.text = widget.baslangicMesaji!;
    _profiliYukle();
    _okunduIsaretle();
  }

  Future<void> _profiliYukle() async {
    try {
      final data = await supabase.from('profiles').select('profil_foto').eq('id', widget.aliciId).single();
      if (data['profil_foto'] != null) {
        final url = await supabase.storage.from('profil_fotolari').createSignedUrl(data['profil_foto'], 60);
        if (mounted) setState(() => _guncelFotoUrl = url);
      }
    } catch (e) {}
  }

  Future<void> _okunduIsaretle() async {
    try {

      await supabase
          .from('mesajlar')
          .update({'okundu': true})
          .eq('gonderen_id', widget.aliciId)
          .eq('alici_id', _benimId)
          .eq('okundu', false);
    } catch (e) {
      print('Okundu hatası: $e');
    }
  }

  Future<void> _mesajGonder() async {
    final mesajMetni = _mesajController.text.trim();
    if (mesajMetni.isEmpty) return;
    _mesajController.clear();
    try {
      await supabase.from('mesajlar').insert({
        'gonderen_id': _benimId,
        'alici_id': widget.aliciId,
        'mesaj': mesajMetni,
        'okundu': false,
      });
      _enAltaKaydir();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }




  Future<void> _mesajSil(String mesajId) async {
    try {
      await supabase
          .from('mesajlar')
          .update({'mesaj': _silinmisMesajMetni})
          .eq('id', mesajId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mesaj herkesten silindi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Silme hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }


  void _silmeOnayiGoster(String mesajId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mesajı Sil'),
        content: const Text(
            'Bu mesajı herkesten silmek istiyor musunuz? Karşı taraf bu mesajı sildiğinizi bilecek.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _mesajSil(mesajId);
            },
            child: const Text('Herkesten Sil', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _enAltaKaydir() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _profileGit() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => KullaniciProfili(kullaniciId: widget.aliciId)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F5E8),
      appBar: AppBar(
        backgroundColor: zeytinYesili,
        elevation: 1,
        titleSpacing: 0,
    leading: IconButton(
    icon: const Icon(Icons.arrow_back_ios_new, color: beyaz),
    onPressed: () => Navigator.pop(context),
    ),
        title: InkWell(
          onTap: _profileGit,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: turuncuPastel,
                backgroundImage: _guncelFotoUrl != null
                    ? NetworkImage(_guncelFotoUrl!)
                    : (widget.aliciFotoUrl != null ? NetworkImage(widget.aliciFotoUrl!) : null),
                child: (_guncelFotoUrl == null && widget.aliciFotoUrl == null)
                    ? Text(widget.aliciAd.isNotEmpty ? widget.aliciAd[0] : '?',
                    style: const TextStyle(color: beyaz))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.aliciAd,
                        style: const TextStyle(color: beyaz, fontSize: 16, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis),
                    const Text('Profil için dokun', style: TextStyle(color: Colors.white70, fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: supabase
                  .from('mesajlar')
                  .stream(primaryKey: ['id'])
                  .order('created_at', ascending: true)
                  .map((data) => data.where((m) {
                final gonderen = m['gonderen_id'];
                final alici = m['alici_id'];
                return (gonderen == _benimId && alici == widget.aliciId) ||
                    (gonderen == widget.aliciId && alici == _benimId);
              }).toList()),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Hata: ${snapshot.error}'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: zeytinYesili));

                final mesajlar = snapshot.data!;


                final bool okunmamisVarMi =
                mesajlar.any((m) => m['gonderen_id'] == widget.aliciId && m['okundu'] == false);

                if (okunmamisVarMi) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _okunduIsaretle();
                  });
                }

                if (mesajlar.isEmpty) {
                  return Center(
                      child: Text('Hadi ${widget.aliciAd} ile sohbete başla! 🐾', style: TextStyle(color: gri)));
                }

                WidgetsBinding.instance.addPostFrameCallback((_) => _enAltaKaydir());

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: mesajlar.length,
                  itemBuilder: (context, index) {
                    final mesajVerisi = mesajlar[index];
                    final String mesajId = mesajVerisi['id'];
                    final String mesajIcerik = mesajVerisi['mesaj'] ?? '';
                    final bool benAttim = mesajVerisi['gonderen_id'] == _benimId;
                    final tarih = DateTime.parse(mesajVerisi['created_at']).add(const Duration(hours: 3));
                    final saat = DateFormat.Hm().format(tarih);
                    final bool okundu = mesajVerisi['okundu'] ?? false;


                    final bool silinmisMesaj = mesajIcerik == _silinmisMesajMetni;

                    return Align(
                      alignment: benAttim ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(

                        onLongPress: (benAttim && !silinmisMesaj) ? () => _silmeOnayiGoster(mesajId) : null,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(

                            color: silinmisMesaj ? Colors.grey.shade300 : (benAttim ? turuncuPastel : beyaz),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: benAttim ? const Radius.circular(16) : Radius.zero,
                              bottomRight: benAttim ? Radius.zero : const Radius.circular(16),
                            ),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [

                              if (silinmisMesaj)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.block, size: 16, color: Colors.grey),
                                    const SizedBox(width: 6),
                                    Text(mesajIcerik,
                                        style: const TextStyle(
                                            color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 14)),
                                  ],
                                )
                              else
                                Text(mesajIcerik,
                                    style: TextStyle(
                                        color: benAttim ? beyaz : const Color(0xFF333333), fontSize: 16)),

                              const SizedBox(height: 4),


                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(saat,
                                      style: TextStyle(
                                          color:
                                          silinmisMesaj ? Colors.grey : (benAttim ? beyaz.withOpacity(0.8) : gri),
                                          fontSize: 10)),
                                  if (benAttim && !silinmisMesaj) ...[
                                    const SizedBox(width: 4),
                                    Icon(Icons.done_all,
                                        size: 16, color: okundu ? maviTik : beyaz.withOpacity(0.6)),
                                  ]
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            color: beyaz,
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                      child: TextField(
                          controller: _mesajController,
                          decoration: InputDecoration(
                              hintText: 'Mesajınızı yazın...',
                              hintStyle: TextStyle(color: gri),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                              filled: true,
                              fillColor: arkaPlan,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
                          minLines: 1,
                          maxLines: 4)),
                  const SizedBox(width: 8),
                  GestureDetector(
                      onTap: _mesajGonder,
                      child: CircleAvatar(
                          radius: 24,
                          backgroundColor: zeytinYesili,
                          child: const Icon(Icons.send, color: beyaz, size: 20))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
