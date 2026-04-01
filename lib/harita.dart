import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart';

import 'shared_bottom_nav.dart';
import 'ilanlar.dart';

final supabase = Supabase.instance.client;

enum MekanTipi { veteriner, petshop, bilinmiyor }

class Mekan {
  final String id;
  final String ad;
  final LatLng konum;
  final MekanTipi tip;

  Mekan({required this.id, required this.ad, required this.konum, required this.tip});
}

class HaritaIlani {
  final String id;
  final String baslik;
  final LatLng konum;
  final String tip;
  final Map<String, dynamic> hamVeri;

  HaritaIlani({
    required this.id,
    required this.baslik,
    required this.konum,
    required this.tip,
    required this.hamVeri,
  });
}

class HaritaSayfasi extends StatefulWidget {
  const HaritaSayfasi({super.key});

  @override
  State<HaritaSayfasi> createState() => _HaritaSayfasiState();
}

class _HaritaSayfasiState extends State<HaritaSayfasi> {
  GoogleMapController? _haritaKontrolcusu;
  LatLng? _kullaniciKonumu;


  List<Mekan> _mekanlar = [];
  List<HaritaIlani> _dbIlanlar = [];

  Set<Marker> _isaretciler = {};
  Set<Circle> _daireler = {};

  bool _veriYukleniyor = false;
  bool _haritaHareketEtti = false;
  LatLng? _haritaMerkezi;




  bool _veterinerGoster = false;
  bool _petshopGoster = false;


  bool _kayipGoster = true;
  bool _bulunanGoster = true;
  bool _sahiplendirmeGoster = true;


  bool _mekanPaneliAcik = false;
  bool _ilanPaneliAcik = false;

  final String _apiKey = "AIzaSyCB9_pncVw-woxlEuy9s4WAkyRsCfthkgY";

  @override
  void initState() {
    super.initState();
    _ilkKonumuAl();
    _veritabaniIlanlariniGetir();
  }

  Future<void> _ilkKonumuAl() async {
    LocationPermission izin = await Geolocator.checkPermission();
    if (izin == LocationPermission.denied) {
      izin = await Geolocator.requestPermission();
    }
    if (izin == LocationPermission.denied || izin == LocationPermission.deniedForever) return;

    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() {
          _kullaniciKonumu = LatLng(pos.latitude, pos.longitude);
          _haritaMerkezi = _kullaniciKonumu;
        });
      }
    } catch (e) {
      debugPrint("Konum hatası: $e");
    }
  }


  LatLng? _koordinatCozumle(dynamic data) {
    if (data == null) return null;
    String hexString = data.toString();

    final RegExp regex = RegExp(r'POINT\((.*) (.*)\)');
    final match = regex.firstMatch(hexString);
    if (match != null) {
      try {
        double lng = double.parse(match.group(1)!);
        double lat = double.parse(match.group(2)!);
        return LatLng(lat, lng);
      } catch (e) {
        print("Regex hatası: $e");
      }
    }

    if (hexString.length > 20) {
      try {
        List<int> bytes = [];
        for (int i = 0; i < hexString.length; i += 2) {
          if (i + 2 <= hexString.length) {
            bytes.add(int.parse(hexString.substring(i, i + 2), radix: 16));
          }
        }
        final ByteData byteData = ByteData.sublistView(Uint8List.fromList(bytes));
        final bool isLittleEndian = byteData.getUint8(0) == 1;
        final Endian endian = isLittleEndian ? Endian.little : Endian.big;

        int offset = 5;
        int type = byteData.getUint32(1, endian);
        if ((type & 0x20000000) != 0) offset += 4;

        double x = byteData.getFloat64(offset, endian);
        double y = byteData.getFloat64(offset + 8, endian);
        return LatLng(y, x);
      } catch (e) {}
    }
    return null;
  }


  Future<void> _veritabaniIlanlariniGetir() async {
    List<HaritaIlani> geciciListe = [];

    try {
      final kayipData = await supabase.from('kayip_ilanlar').select('id, hayvan_adi, hayvan_turu, konum, profiles(tam_ad, telefon)');
      for (var ilan in kayipData) {
        final LatLng? pos = _koordinatCozumle(ilan['konum']);
        if (pos != null) {
          geciciListe.add(HaritaIlani(id: ilan['id'], baslik: "${ilan['hayvan_adi']} (Kayıp)", konum: pos, tip: 'kayip', hamVeri: ilan));
        }
      }

      final bulunanData = await supabase.from('bulunan_ilanlar').select('id, hayvan_turu, konum, profiles(tam_ad, telefon)');
      for (var ilan in bulunanData) {
        final LatLng? pos = _koordinatCozumle(ilan['konum']);
        if (pos != null) {
          geciciListe.add(HaritaIlani(id: ilan['id'], baslik: "Bulunan ${ilan['hayvan_turu']}", konum: pos, tip: 'bulunan', hamVeri: ilan));
        }
      }

      final sahiplendirmeData = await supabase.from('sahiplendirme_ilanlar').select('id, hayvan_adi, hayvan_turu, konum, profiles(tam_ad, telefon)');
      for (var ilan in sahiplendirmeData) {
        final LatLng? pos = _koordinatCozumle(ilan['konum']);
        if (pos != null) {
          geciciListe.add(HaritaIlani(id: ilan['id'], baslik: "${ilan['hayvan_adi']} (Sahiplendirme)", konum: pos, tip: 'sahiplendirme', hamVeri: ilan));
        }
      }
    } catch (e) {
      debugPrint("İlan çekme hatası: $e");
    }

    if (mounted) {
      setState(() {
        _dbIlanlar = geciciListe;
      });
      _markerlariGuncelle();
    }
  }


  Future<void> _googlePlacesVerisiGetir(double lat, double lng, int yaricap) async {
    if (!_veterinerGoster && !_petshopGoster) {
      setState(() {
        _daireler.clear();
        _mekanlar.clear();
        _markerlariGuncelle();
      });
      return;
    }

    _aramaDairesiniGuncelle(lat, lng, yaricap.toDouble());

    setState(() {
      _veriYukleniyor = true;
      _haritaHareketEtti = false;
    });

    List<Mekan> yeniMekanlar = [];

    try {
      if (_veterinerGoster) {
        await _istekAt(lat, lng, yaricap, "veterinary_care", MekanTipi.veteriner, yeniMekanlar);
      }
      if (_petshopGoster) {
        await _istekAt(lat, lng, yaricap, "pet_store", MekanTipi.petshop, yeniMekanlar);
      }

      if (mounted) {
        setState(() {
          _mekanlar = yeniMekanlar;
          _veriYukleniyor = false;
        });
        _markerlariGuncelle();
      }
    } catch (e) {
      debugPrint("API Hatası: $e");
      if (mounted) setState(() => _veriYukleniyor = false);
    }
  }

  void _aramaDairesiniGuncelle(double lat, double lng, double radiusInMeters) {
    if (!_veterinerGoster && !_petshopGoster) {
      setState(() => _daireler.clear());
      return;
    }

    setState(() {
      _daireler.clear();
      _daireler.add(
        Circle(
          circleId: const CircleId("arama_alani_dairesi"),
          center: LatLng(lat, lng),
          radius: radiusInMeters,
          strokeWidth: 2,
          strokeColor: Colors.amber,
          fillColor: Colors.amber.withOpacity(0.1),
        ),
      );
    });
  }

  Future<void> _istekAt(double lat, double lng, int yaricap, String type, MekanTipi tipEnum, List<Mekan> liste) async {
    final String url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=$yaricap&type=$type&key=$_apiKey&language=tr";
    final cevap = await http.get(Uri.parse(url));
    if (cevap.statusCode == 200) {
      final jsonVerisi = json.decode(cevap.body);
      if (jsonVerisi['status'] == 'OK') {
        final results = jsonVerisi['results'] as List;
        for (var yer in results) {
          liste.add(Mekan(
            id: yer['place_id'],
            ad: yer['name'] ?? (tipEnum == MekanTipi.veteriner ? "Veteriner" : "Pet Shop"),
            konum: LatLng(yer['geometry']['location']['lat'], yer['geometry']['location']['lng']),
            tip: tipEnum,
          ));
        }
      }
    }
  }

  Future<void> _ilanDetayinaGit(HaritaIlani haritaIlani) async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
    try {
      String tabloAdi = '';
      String selectQuery = '';
      if (haritaIlani.tip == 'kayip') {
        tabloAdi = 'kayip_ilanlar';
        selectQuery = 'id, kullanici_id, hayvan_adi, hayvan_turu, hayvan_rengi, ekstra_bilgi, konum, konum_text, hayvan_cinsiyeti, cipi_var_mi, created_at, profiles(tam_ad, telefon)';
      } else if (haritaIlani.tip == 'bulunan') {
        tabloAdi = 'bulunan_ilanlar';
        selectQuery = 'id, kullanici_id, hayvan_turu, hayvan_rengi, ekstra_bilgi, konum, konum_text, hayvan_cinsiyeti, created_at, profiles(tam_ad, telefon)';
      } else {
        tabloAdi = 'sahiplendirme_ilanlar';
        selectQuery = 'id, kullanici_id, hayvan_adi, hayvan_turu, hayvan_rengi, ekstra_bilgi, konum, konum_text, hayvan_cinsiyeti, cipi_var_mi, kisir_mi, kisirlastirma_sarti, aliskanliklar, created_at, profiles(tam_ad, telefon)';
      }

      final data = await supabase.from(tabloAdi).select(selectQuery).eq('id', haritaIlani.id).single();
      final List<dynamic> fotos = await supabase.from('ilan_fotograflari').select('foto_url').eq('ilan_id', haritaIlani.id).eq('ilan_tipi', haritaIlani.tip).order('created_at', ascending: true);
      List<String> fotoUrls = fotos.map((e) => e['foto_url'] as String).toList();

      if(mounted) Navigator.pop(context);
      final ilanModeli = Ilan.fromMap(data: data, tip: haritaIlani.tip, fotoUrls: fotoUrls);
      if(mounted) Navigator.push(context, MaterialPageRoute(builder: (context) => IlanDetaySayfasi(ilan: ilanModeli)));
    } catch (e) {
      if(mounted) Navigator.pop(context);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Detaylar yüklenemedi: $e")));
    }
  }

  void _markerlariGuncelle() {
    Set<Marker> yeniIsaretciler = {};

    for (var mekan in _mekanlar) {
      bool goster = false;
      if (mekan.tip == MekanTipi.veteriner && _veterinerGoster) goster = true;
      if (mekan.tip == MekanTipi.petshop && _petshopGoster) goster = true;

      if (goster) {
        yeniIsaretciler.add(Marker(
          markerId: MarkerId(mekan.id),
          position: mekan.konum,
          infoWindow: InfoWindow(title: mekan.ad, snippet: "Google Maps Mekanı"),
          icon: BitmapDescriptor.defaultMarkerWithHue(mekan.tip == MekanTipi.veteriner ? BitmapDescriptor.hueRed : BitmapDescriptor.hueBlue),
        ));
      }
    }

    for (var ilan in _dbIlanlar) {
      bool goster = false;
      double hue = BitmapDescriptor.hueRed;

      if (ilan.tip == 'kayip' && _kayipGoster) {
        goster = true; hue = BitmapDescriptor.hueOrange;
      } else if (ilan.tip == 'bulunan' && _bulunanGoster) {
        goster = true; hue = BitmapDescriptor.hueGreen;
      } else if (ilan.tip == 'sahiplendirme' && _sahiplendirmeGoster) {
        goster = true; hue = BitmapDescriptor.hueViolet;
      }

      if (goster) {
        yeniIsaretciler.add(Marker(
          markerId: MarkerId(ilan.id),
          position: ilan.konum,
          infoWindow: InfoWindow(title: ilan.baslik, snippet: "Detaylar için tıklayın", onTap: () => _ilanDetayinaGit(ilan)),
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        ));
      }
    }

    setState(() {
      _isaretciler = yeniIsaretciler;
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color turuncuPastel = Color(0xFFFFB74D);
    const Color zeytinYesili = Color(0xFF558B2F);
    const Color beyaz = Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kayıp Pati Haritası', style: TextStyle(color: beyaz, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: zeytinYesili,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: beyaz),
            tooltip: 'İlanları Yenile',
            onPressed: _veritabaniIlanlariniGetir,
          ),
          IconButton(
            icon: const Icon(Icons.my_location, color: beyaz),
            tooltip: 'Konumuma Git',
            onPressed: () {
              if (_kullaniciKonumu != null && _haritaKontrolcusu != null) {
                _haritaKontrolcusu!.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: _kullaniciKonumu!, zoom: 12)));
              }
            },
          ),
        ],
      ),
      body: _kullaniciKonumu == null
          ? const Center(child: CircularProgressIndicator(color: zeytinYesili))
          : Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,

            initialCameraPosition: CameraPosition(target: _kullaniciKonumu!, zoom: 12.0),
            onMapCreated: (c) => _haritaKontrolcusu = c,
            onCameraMove: (p) {
              _haritaMerkezi = p.target;
              if (!_veriYukleniyor && !_haritaHareketEtti && (_veterinerGoster || _petshopGoster)) {
                setState(() => _haritaHareketEtti = true);
              }
            },
            myLocationEnabled: true,

            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: _isaretciler,
            circles: _daireler,
          ),

          if (_haritaHareketEtti && (_veterinerGoster || _petshopGoster))
            Positioned(
              top: 20, left: 0, right: 0,
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (_haritaMerkezi != null) {
                      _googlePlacesVerisiGetir(_haritaMerkezi!.latitude, _haritaMerkezi!.longitude, 50000);
                    }
                  },
                  icon: _veriYukleniyor
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: zeytinYesili))
                      : const Icon(Icons.search, size: 18, color: zeytinYesili),
                  label: Text(_veriYukleniyor ? "Aranıyor..." : "Bu bölgede mekan ara (50km)", style: const TextStyle(color: zeytinYesili, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, shape: const StadiumBorder(), elevation: 4),
                ),
              ),
            ),


          Positioned(
            left: 10,
            top: 80,
            child: _buildSolPanel(),
          ),


          Positioned(
            right: 10,
            top: 80,
            child: _buildSagPanel(),
          ),

          if (_veriYukleniyor && !_haritaHareketEtti)
            const Center(child: CircularProgressIndicator(color: zeytinYesili)),
        ],
      ),
      bottomNavigationBar: const SharedBottomNavBar(
        currentIndex: 1,
        turuncuPastel: turuncuPastel,
        gri: Color(0xFF9E9E9E),
        beyaz: beyaz,
      ),
    );
  }


  Widget _buildSolPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: _mekanPaneliAcik ? 280 : 50,

      height: _mekanPaneliAcik ? 190 : 50,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => setState(() => _mekanPaneliAcik = !_mekanPaneliAcik),
                  child: Container(
                    height: 50,
                    width: _mekanPaneliAcik ? 280 : 50,

                    alignment: _mekanPaneliAcik ? Alignment.centerLeft : Alignment.center,
                    padding: _mekanPaneliAcik ? const EdgeInsets.symmetric(horizontal: 12) : EdgeInsets.zero,
                    child: _mekanPaneliAcik
                        ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.filter_list, color: Colors.grey[700]),
                            const SizedBox(width: 8),
                            const Text("Mekan Filtreleri", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                        const Icon(Icons.arrow_back_ios, size: 18, color: Colors.grey),
                      ],
                    )
                        : const Center(child: Icon(Icons.filter_list, color: Colors.grey)),
                  ),
                ),

                if (_mekanPaneliAcik)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 260,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Divider(height: 1),
                            _buildSwitchRow("Veteriner", Icons.local_hospital, Colors.red, _veterinerGoster, (val) {
                              setState(() {
                                _veterinerGoster = val;
                                if(val && _kullaniciKonumu != null) {
                                  _googlePlacesVerisiGetir(_haritaMerkezi!.latitude, _haritaMerkezi!.longitude, 50000);
                                } else if (!val) {
                                  _markerlariGuncelle();
                                  if(!_petshopGoster) _daireler.clear();
                                }
                              });
                            }),
                            _buildSwitchRow("Pet Shop", Icons.store, Colors.blue, _petshopGoster, (val) {
                              setState(() {
                                _petshopGoster = val;
                                if(val && _kullaniciKonumu != null) {
                                  _googlePlacesVerisiGetir(_haritaMerkezi!.latitude, _haritaMerkezi!.longitude, 50000);
                                } else if (!val) {
                                  _markerlariGuncelle();
                                  if(!_veterinerGoster) _daireler.clear();
                                }
                              });
                            }),
                            const Padding(
                              padding: EdgeInsets.only(top: 5, bottom: 10),
                              child: Text("50 km sınırı geçerli", style: TextStyle(fontSize: 10, color: Colors.grey)),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildSagPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: _ilanPaneliAcik ? 280 : 50,
      height: _ilanPaneliAcik ? 230 : 50,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => setState(() => _ilanPaneliAcik = !_ilanPaneliAcik),
                  child: Container(
                    height: 50,
                    width: _ilanPaneliAcik ? 280 : 50,

                    alignment: _ilanPaneliAcik ? Alignment.centerRight : Alignment.center,
                    padding: _ilanPaneliAcik ? const EdgeInsets.symmetric(horizontal: 12) : EdgeInsets.zero,
                    child: _ilanPaneliAcik
                        ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey),
                        Row(
                          children: [
                            const Text("İlan Filtreleri", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(width: 8),
                            const Icon(Icons.pets, color: Color(0xFFFFB74D), size: 28),
                          ],
                        ),
                      ],
                    )
                        : const Center(child: Icon(Icons.pets, color: Color(0xFFFFB74D), size: 28)),
                  ),
                ),

                if (_ilanPaneliAcik)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 260,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          children: [
                            const Divider(height: 1),
                            _buildSwitchRow("Kayıp İlanı", Icons.search, Colors.orange, _kayipGoster, (val) {
                              setState(() { _kayipGoster = val; _markerlariGuncelle(); });
                            }),
                            _buildSwitchRow("Bulunan", Icons.check_circle, Colors.green, _bulunanGoster, (val) {
                              setState(() { _bulunanGoster = val; _markerlariGuncelle(); });
                            }),
                            _buildSwitchRow("Sahiplendirme", Icons.volunteer_activism, Colors.purple, _sahiplendirmeGoster, (val) {
                              setState(() { _sahiplendirmeGoster = val; _markerlariGuncelle(); });
                            }),
                            const Padding(
                              padding: EdgeInsets.only(top: 5, bottom: 10),
                              child: Text("Tüm ilanlar (Sınırsız)", style: TextStyle(fontSize: 10, color: Colors.grey)),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchRow(String label, IconData icon, Color color, bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 30,
            child: Switch(
              value: value,
              activeColor: color,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}