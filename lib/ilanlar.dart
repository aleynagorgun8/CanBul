import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'shared_bottom_nav.dart';
import 'mesajlar.dart';
import 'konum_sec_sayfasi.dart';
import 'kullanici_profili.dart';
import 'profil.dart';
import 'package:timeago/timeago.dart' as timeago;

final supabase = Supabase.instance.client;



const String _KAYIP_ILAN_SELECT_QUERY =
    'id, kullanici_id, hayvan_adi, hayvan_turu, hayvan_rengi, ekstra_bilgi, konum, konum_text, hayvan_cinsiyeti, cipi_var_mi, created_at, profiles(tam_ad, telefon)';

const String _BULUNAN_ILAN_SELECT_QUERY =
    'id, kullanici_id, hayvan_turu, hayvan_rengi, ekstra_bilgi, konum, konum_text, hayvan_cinsiyeti, created_at, profiles(tam_ad, telefon)';

const String _SAHIPLENDIRME_ILAN_SELECT_QUERY =
    'id, kullanici_id, hayvan_adi, hayvan_turu, hayvan_rengi, ekstra_bilgi, konum, konum_text, hayvan_cinsiyeti, cipi_var_mi, kisir_mi, kisirlastirma_sarti, aliskanliklar, created_at, profiles(tam_ad, telefon)';



Future<List<String>> ilanAsilariniGetir(String ilanId, String ilanTipi) async {
  try {
    String tabloAdi = '';
    String kolonAdi = '';

    if (ilanTipi == 'kayip') {
      tabloAdi = 'kayip_ilan_asilar';
      kolonAdi = 'kayip_ilan_id';
    } else if (ilanTipi == 'sahiplendirme') {
      tabloAdi = 'sahiplendirme_ilan_asilar';
      kolonAdi = 'sahiplendirme_ilan_id';
    } else {
      return [];
    }

    final List<dynamic> response = await supabase
        .from(tabloAdi)
        .select('asilistesi(asi_adi)')
        .eq(kolonAdi, ilanId);

    if (response.isEmpty) return [];

    return response.map((e) => e['asilistesi']['asi_adi'] as String).toList();
  } catch (e) {
    return [];
  }
}

Future<Map<String, List<String>>> _ilanFotograflariniGetir(List<String> ilanIdleri) async {
  if (ilanIdleri.isEmpty) return {};

  try {
    final List<dynamic> fotos = await supabase
        .from('ilan_fotograflari')
        .select('ilan_id, foto_url')
        .filter('ilan_id', 'in', ilanIdleri)
        .order('created_at', ascending: true);

    Map<String, List<String>> ilanIdToFotoListesi = {};

    for (final f in fotos) {
      final String iid = f['ilan_id'].toString();
      final String? url = f['foto_url']?.toString();

      if (url != null && url.trim().isNotEmpty) {
        if (!ilanIdToFotoListesi.containsKey(iid)) {
          ilanIdToFotoListesi[iid] = [];
        }
        ilanIdToFotoListesi[iid]!.add(url);
      }
    }
    return ilanIdToFotoListesi;
  } catch (e) {
    return {};
  }
}

Future<void> _ilanAsilariniGuncelle(String ilanId, List<String> yeniAsiIdleri, {bool isSahiplendirme = false}) async {
  try {
    final String tabloAdi = isSahiplendirme ? 'sahiplendirme_ilan_asilar' : 'kayip_ilan_asilar';
    final String kolonAdi = isSahiplendirme ? 'sahiplendirme_ilan_id' : 'kayip_ilan_id';

    await supabase.from(tabloAdi).delete().eq(kolonAdi, ilanId);

    if (yeniAsiIdleri.isNotEmpty) {
      final List<Map<String, String>> iliskiVerileri = yeniAsiIdleri.map((asiId) {
        return {
          kolonAdi: ilanId,
          'asi_id': asiId,
        };
      }).toList();

      await supabase.from(tabloAdi).insert(iliskiVerileri);
    }
  } catch (e) {
    throw Exception('Aşı güncelleme hatası: $e');
  }
}


LatLng? _koordinatCozumle(dynamic data) {
  if (data == null) return null;
  String hexString = data.toString();


  final RegExp regex = RegExp(r'POINT\(([-+]?\d*\.?\d+) ([-+]?\d*\.?\d+)\)');
  final match = regex.firstMatch(hexString);
  if (match != null && match.groupCount >= 2) {
    try {
      double lng = double.parse(match.group(1)!);
      double lat = double.parse(match.group(2)!);
      return LatLng(lat, lng);
    } catch (e) {
      debugPrint("POINT Regex hatası: $e");
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
    } catch (e) {
      debugPrint("WKB Çözümleme hatası: $e");
    }
  }
  return null;
}



class Ilan {
  final String id;
  final String kullaniciId;
  final String kullaniciAdi;
  final String hayvanAdi;
  final String hayvanTuru;
  final String hayvanRengi;
  final String ilanTipi;
  final String sehir;
  final String? hamKonum;
  final List<String> fotoUrlListesi;
  final String telefonNumarasi;
  final String ekstraBilgi;
  final bool isRepost;
  final String hayvanCinsiyeti;
  final bool cipiVarMi;
  final DateTime createdAt;

  final bool kisirMi;
  final bool kisirlastirmaSarti;
  final String? aliskanliklar;
  final List<String>? asilar;

  Ilan({
    required this.id,
    required this.kullaniciId,
    required this.kullaniciAdi,
    required this.hayvanAdi,
    required this.hayvanTuru,
    required this.hayvanRengi,
    required this.ilanTipi,
    required this.sehir,
    this.hamKonum,
    required this.fotoUrlListesi,
    required this.telefonNumarasi,
    required this.ekstraBilgi,
    required this.hayvanCinsiyeti,
    required this.cipiVarMi,
    required this.createdAt,
    this.kisirMi = false,
    this.kisirlastirmaSarti = false,
    this.aliskanliklar,
    this.isRepost = false,
    this.asilar,
  });

  factory Ilan.fromMap({
    required Map<String, dynamic> data,
    required String tip,
    required List<String> fotoUrls,
    String? kullaniciAd,
    String? kullaniciTel,
    bool isRepost = false,
    List<String>? asilar,
  }) {
    String konumVerisi = 'Konum Bilgisi Yok';
    String? rawKonum;


    if (data['konum'] != null) {
      rawKonum = data['konum'].toString();
    }


    if (data['konum_text'] != null) {
      konumVerisi = data['konum_text'].toString();
    } else if (rawKonum != null) {
      konumVerisi = rawKonum;
    }


    String hayvanAd = 'İsimsiz';
    if (tip == 'kayip' || tip == 'sahiplendirme') {
      hayvanAd = data['hayvan_adi'] ?? 'İsimsiz';
    } else {
      hayvanAd = 'Bulunan Hayvan';
    }

    final String finalAd = kullaniciAd ?? data['profiles']?['tam_ad'] ?? 'Anonim Kullanıcı';
    final String finalTel = kullaniciTel ?? data['profiles']?['telefon'] ?? 'Numara Yok';

    DateTime olusturulmaTarihi = DateTime.now();
    if (data['created_at'] != null) {
      olusturulmaTarihi = DateTime.parse(data['created_at']);
    }

    return Ilan(
      id: data['id'].toString(),
      kullaniciId: data['kullanici_id'].toString(),
      kullaniciAdi: finalAd,
      hayvanAdi: hayvanAd,
      hayvanTuru: data['hayvan_turu'] ?? 'Bilinmiyor',
      hayvanRengi: data['hayvan_rengi'] ?? 'Bilinmiyor',
      ilanTipi: tip,
      sehir: konumVerisi,
      hamKonum: rawKonum,
      fotoUrlListesi: fotoUrls,
      telefonNumarasi: finalTel,
      ekstraBilgi: data['ekstra_bilgi'] ?? 'Ek bilgi bulunmamaktadır.',
      hayvanCinsiyeti: data['hayvan_cinsiyeti'] ?? 'Belirtilmemiş',
      cipiVarMi: data['cipi_var_mi'] ?? false,
      createdAt: olusturulmaTarihi,
      kisirMi: data['kisir_mi'] ?? false,
      kisirlastirmaSarti: data['kisirlastirma_sarti'] ?? false,
      aliskanliklar: data['aliskanliklar'],
      isRepost: isRepost,
      asilar: asilar,
    );
  }
}

class Filtreler {
  final String? hayvanTuru;
  final String? sehir;
  final String? ilanTipi;

  Filtreler({this.hayvanTuru, this.sehir, this.ilanTipi});

  Filtreler copyWith({String? hayvanTuru, String? sehir, String? ilanTipi}) {
    return Filtreler(
      hayvanTuru: hayvanTuru ?? this.hayvanTuru,
      sehir: sehir ?? this.sehir,
      ilanTipi: ilanTipi ?? this.ilanTipi,
    );
  }

  bool get hasActiveFilters => hayvanTuru != null || sehir != null || ilanTipi != null;
}

Future<List<Ilan>> tumIlanlariGetir() async {

  List<Ilan> ilanlar = [];
  try {
    final results = await Future.wait([
      supabase.from('kayip_ilanlar').select(_KAYIP_ILAN_SELECT_QUERY),
      supabase.from('bulunan_ilanlar').select(_BULUNAN_ILAN_SELECT_QUERY),
      supabase.from('sahiplendirme_ilanlar').select(_SAHIPLENDIRME_ILAN_SELECT_QUERY)
    ]);

    List<String> tumIds = [];
    for(var list in results) {
      tumIds.addAll((list as List).map((e) => e['id'].toString()));
    }

    final Map<String, List<String>> tumFotolar = await _ilanFotograflariniGetir(tumIds);

    for (var data in results[0]) ilanlar.add(Ilan.fromMap(data: data, tip: 'kayip', fotoUrls: tumFotolar[data['id'].toString()] ?? []));
    for (var data in results[1]) ilanlar.add(Ilan.fromMap(data: data, tip: 'bulunan', fotoUrls: tumFotolar[data['id'].toString()] ?? []));
    for (var data in results[2]) ilanlar.add(Ilan.fromMap(data: data, tip: 'sahiplendirme', fotoUrls: tumFotolar[data['id'].toString()] ?? []));

    ilanlar.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  } catch (e) {
    print("Genel veri çekme hatası: $e");
  }
  return ilanlar;
}



class IlanlarSayfasi extends StatefulWidget {
  const IlanlarSayfasi({super.key});

  @override
  State<IlanlarSayfasi> createState() => _IlanlarSayfasiState();
}

class _IlanlarSayfasiState extends State<IlanlarSayfasi> {
  final Color turuncuPastel = const Color(0xFFFFB74D);
  final Color zeytinYesili = const Color(0xFF558B2F);
  final Color acikYesil = const Color(0xFFC5E1A5);
  final Color lacivert = const Color(0xFF002D72);
  final Color gri = const Color(0xFF9E9E9E);
  final Color beyaz = Colors.white;

  Filtreler _filtreler = Filtreler();
  List<Ilan> _tumIlanlar = [];
  List<Ilan> _filtrelenmisIlanlar = [];
  bool _yukleniyor = true;
  String? _hataMesaji;


  Map<String, Set<String>> _cityDistrictMap = {};


  Map<String, String> _cozumlenmisKonumlar = {};

  String? _selectedCity;
  String? _selectedDistrict;

  @override
  void initState() {
    super.initState();
    _ilanlariYukle();
  }


  Future<void> _loadCityAndDistrictData() async {
    Map<String, Set<String>> dropdownMap = {};
    Map<String, String> idToLocationMap = {};


    List<Future<void>> resolutionTasks = [];

    for (var ilan in _tumIlanlar) {
      String sehirAdi = ilan.sehir;
      String ilanId = ilan.id;


      if (sehirAdi.contains('/')) {
        final parts = sehirAdi.split('/').map((s) => s.trim()).toList();
        if (parts.length == 2) {
          final city = parts[0];
          final district = parts[1];
          dropdownMap.putIfAbsent(city, () => {}).add(district);
          idToLocationMap[ilanId] = "$city / $district";
        }
      }

      else if (sehirAdi.startsWith('POINT')) {
        final LatLng? koordinat = _koordinatCozumle(ilan.hamKonum);

        if (koordinat != null) {
          resolutionTasks.add(
              placemarkFromCoordinates(koordinat.latitude, koordinat.longitude)
                  .then((placemarks) {
                if (placemarks.isNotEmpty) {
                  Placemark yer = placemarks.first;
                  String city = yer.administrativeArea ?? '';
                  String district = yer.subAdministrativeArea ?? '';

                  if (city.isNotEmpty) {
                    if (district.isNotEmpty && district != city) {
                      dropdownMap.putIfAbsent(city, () => {}).add(district);
                      idToLocationMap[ilanId] = "$city / $district";
                    } else {
                      dropdownMap.putIfAbsent(city, () => {});
                      idToLocationMap[ilanId] = city;
                    }
                  }
                }
              }).catchError((_) {

              })
          );
        }
      }

      else if (sehirAdi.isNotEmpty && sehirAdi != 'Konum Bilgisi Yok') {
        dropdownMap.putIfAbsent(sehirAdi, () => {});
        idToLocationMap[ilanId] = sehirAdi;
      }
    }


    await Future.wait(resolutionTasks);

    if(mounted) {
      setState(() {
        _cityDistrictMap = dropdownMap;
        _cozumlenmisKonumlar = idToLocationMap;
      });


      _filtrele();
    }
  }

  Future<void> _ilanlariYukle() async {
    try {
      setState(() { _yukleniyor = true; _hataMesaji = null; });
      final ilanlar = await tumIlanlariGetir();
      if (mounted) {
        setState(() {
          _tumIlanlar = ilanlar;
          _filtrelenmisIlanlar = ilanlar;
          _yukleniyor = false;
        });
        await _loadCityAndDistrictData();
      }
    } catch (e) {
      if (mounted) setState(() { _yukleniyor = false; _hataMesaji = 'Hata: ${e.toString()}'; });
    }
  }


  void _filtrele() {
    List<Ilan> filtrelenmis = _tumIlanlar;

    debugPrint('--- FİLTRELEME BAŞLADI ---');


    if (_filtreler.hayvanTuru != null) {
      filtrelenmis = filtrelenmis.where((ilan) => ilan.hayvanTuru == _filtreler.hayvanTuru).toList();
    }


    if (_filtreler.ilanTipi != null) {
      filtrelenmis = filtrelenmis.where((ilan) => ilan.ilanTipi == _filtreler.ilanTipi).toList();
    }


    if (_selectedCity != null) {
      filtrelenmis = filtrelenmis.where((ilan) {

        final effectiveLocation = _cozumlenmisKonumlar[ilan.id] ?? ilan.sehir;

        final parts = effectiveLocation.split('/').map((s) => s.trim()).toList();
        if (parts.isNotEmpty) {
          return parts[0] == _selectedCity;
        }
        return false;
      }).toList();
    }


    if (_selectedDistrict != null) {
      filtrelenmis = filtrelenmis.where((ilan) {
        final effectiveLocation = _cozumlenmisKonumlar[ilan.id] ?? ilan.sehir;

        if (effectiveLocation.contains('/')) {
          final parts = effectiveLocation.split('/').map((s) => s.trim()).toList();
          if (parts.length == 2) {
            return parts[1] == _selectedDistrict;
          }
        }
        return false;
      }).toList();
    }

    setState(() => _filtrelenmisIlanlar = filtrelenmis);
  }


  void _filtreleriTemizle() {
    setState(() {
      _filtreler = Filtreler();
      _selectedCity = null;
      _selectedDistrict = null;
      _filtrelenmisIlanlar = _tumIlanlar;
    });
  }

  List<String> _getHayvanTurleri() {
    final turler = _tumIlanlar.map((ilan) => ilan.hayvanTuru).toSet().toList();
    turler.sort();
    return turler;
  }

  @override
  Widget build(BuildContext context) {
    List<String> availableCities = _cityDistrictMap.keys.toList();
    availableCities.sort();

    List<String> availableDistricts = _cityDistrictMap[_selectedCity]?.toList() ?? [];
    availableDistricts.sort();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        title: const Text('Tüm İlanlar', style: TextStyle(color: Color(0xFF558B2F), fontWeight: FontWeight.bold)),
        backgroundColor: beyaz,
        elevation: 1,
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildFiltrelemeBolumu(availableCities, availableDistricts),
          Expanded(child: _buildIlanListesi()),
        ],
      ),
      bottomNavigationBar: SharedBottomNavBar(currentIndex: 3, turuncuPastel: turuncuPastel, gri: gri, beyaz: beyaz),
    );
  }

  Widget _buildFiltrelemeBolumu(List<String> availableCities, List<String> availableDistricts) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt, color: turuncuPastel),
              const SizedBox(width: 8),
              Text('Filtrele', style: TextStyle(fontWeight: FontWeight.bold, color: zeytinYesili, fontSize: 16)),
              const Spacer(),
              if (_filtreler.hasActiveFilters || _selectedCity != null || _selectedDistrict != null)
                InkWell(
                  onTap: _filtreleriTemizle,
                  child: const Row(children: [Icon(Icons.clear, color: Colors.red, size: 18), Text('Temizle', style: TextStyle(color: Colors.red))]),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildDropdown(label: 'Hayvan Türü', value: _filtreler.hayvanTuru, items: _getHayvanTurleri(), onChanged: (v) { setState(() => _filtreler = _filtreler.copyWith(hayvanTuru: v)); _filtrele(); })),
              const SizedBox(width: 8),
              Expanded(child: _buildDropdown(label: 'İlan Türü', value: _filtreler.ilanTipi, items: const ['kayip', 'bulunan', 'sahiplendirme'], onChanged: (v) { setState(() => _filtreler = _filtreler.copyWith(ilanTipi: v)); _filtrele(); })),
            ],
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(child: _buildDropdown(
                label: 'Şehir',
                value: _selectedCity,
                items: availableCities,
                onChanged: (v) {
                  setState(() {
                    _selectedCity = v;
                    _selectedDistrict = null;
                  });
                  _filtrele();
                },
                hintText: 'Tüm şehirler',
              )),
              const SizedBox(width: 8),

              Expanded(child: _buildDropdown(
                label: 'İlçe',
                value: _selectedDistrict,
                items: availableDistricts,
                onChanged: (v) {
                  setState(() {
                    _selectedDistrict = v;
                  });
                  _filtrele();
                },
                isEnabled: _selectedCity != null,
                hintText: _selectedCity == null ? 'Önce şehir seçin' : 'Tüm ilçeler',
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
    bool isEnabled = true,
    String hintText = 'Tümü'
  }) {
    Color activeColor = isEnabled ? turuncuPastel : Colors.grey.shade400;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: gri)),
        Container(
          height: 40,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
              color: activeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: Icon(Icons.arrow_drop_down, color: activeColor),
              hint: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(hintText, style: TextStyle(color: activeColor))),
              items: [
                DropdownMenuItem<String>(value: null, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(hintText, style: TextStyle(color: activeColor)))),
                ...items.map((item) {
                  String text = item;
                  if (item == 'kayip') text = 'Kayıp'; if (item == 'bulunan') text = 'Bulunan'; if (item == 'sahiplendirme') text = 'Sahiplendirme';
                  return DropdownMenuItem<String>(value: item, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(text)));
                }).toList()
              ],
              onChanged: isEnabled ? onChanged : null,
              dropdownColor: beyaz,
              style: TextStyle(color: lacivert, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIlanListesi() {
    if (_yukleniyor) return Center(child: CircularProgressIndicator(color: turuncuPastel));
    if (_hataMesaji != null) return Center(child: Text(_hataMesaji!, style: const TextStyle(color: Colors.red)));
    if (_filtrelenmisIlanlar.isEmpty) return Center(child: Text('İlan bulunamadı.', style: TextStyle(color: gri)));

    return RefreshIndicator(
      onRefresh: _ilanlariYukle,
      color: turuncuPastel,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80, top: 8),
        itemCount: _filtrelenmisIlanlar.length,
        itemBuilder: (context, index) {
          final ilan = _filtrelenmisIlanlar[index];
          final cozumlenmisKonum = _cozumlenmisKonumlar[ilan.id];

          return IlanListItem(
            ilan: ilan,
            turuncuPastel: turuncuPastel,
            zeytinYesili: zeytinYesili,
            lacivert: lacivert,
            resolvedLocation: cozumlenmisKonum,

            onSilindi: () {
              setState(() {
                _tumIlanlar.removeWhere((i) => i.id == ilan.id);
                _filtrelenmisIlanlar.removeWhere((i) => i.id == ilan.id);
              });
            },

            onDuzenlendi: () {
              _ilanlariYukle();
            },
          );
        },
      ),
    );
  }
}

class IlanListItem extends StatelessWidget {
  final Ilan ilan;
  final Color turuncuPastel;
  final Color zeytinYesili;
  final Color lacivert;
  final String? resolvedLocation;
  final VoidCallback? onSilindi;
  final VoidCallback? onDuzenlendi;

  const IlanListItem({
    super.key,
    required this.ilan,
    required this.turuncuPastel,
    required this.zeytinYesili,
    required this.lacivert,
    this.resolvedLocation,
    this.onSilindi,
    this.onDuzenlendi,
  });

  @override
  Widget build(BuildContext context) {
    String baslik = '';
    Color baslikRengi = Colors.black;
    if (ilan.ilanTipi == 'kayip') {
      baslik = '${ilan.hayvanAdi} (Kayıp)';
      baslikRengi = Colors.red;
    } else if (ilan.ilanTipi == 'bulunan') {
      baslik = 'Bulunan Hayvan';
      baslikRengi = zeytinYesili;
    } else {
      baslik = '${ilan.hayvanAdi} (Yuva Arıyor)';
      baslikRengi = lacivert;
    }

    Widget fotoWidget;
    if (ilan.fotoUrlListesi.isNotEmpty) {
      final encodedUrl = Uri.encodeFull(ilan.fotoUrlListesi.first);
      fotoWidget = Image.network(encodedUrl, width: 90, height: 90, fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(width: 90, height: 90, color: Colors.grey.shade300, child: const Icon(Icons.broken_image)));
    } else {
      fotoWidget = Container(width: 90, height: 90, color: Colors.grey.shade200, child: Icon(Icons.pets, color: baslikRengi.withOpacity(0.5), size: 40));
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () async {

          final sonuc = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => IlanDetaySayfasi(ilan: ilan)),
          );

          if (sonuc == 'silindi' && onSilindi != null) {
            onSilindi!();
          } else if (sonuc == 'duzenlendi' && onDuzenlendi != null) {
            onDuzenlendi!();
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(12), child: fotoWidget),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(baslik, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: baslikRengi), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text('Tür: ${ilan.hayvanTuru}', style: TextStyle(color: Colors.grey.shade700)),
                    Text(ilan.kullaniciAdi, style: TextStyle(color: Colors.grey.shade700)),
                    Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: KonumBilgisiWidget(
                            hamKonumVerisi: resolvedLocation ?? ilan.sehir,
                            iconColor: baslikRengi
                        )
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



class IlanDetaySayfasi extends StatefulWidget {
  final Ilan ilan;
  const IlanDetaySayfasi({super.key, required this.ilan});

  @override
  State<IlanDetaySayfasi> createState() => _IlanDetaySayfasiState();
}

class _IlanDetaySayfasiState extends State<IlanDetaySayfasi> {
  final Color turuncuPastel = const Color(0xFFFFB74D);
  final Color zeytinYesili = const Color(0xFF558B2F);
  final Color acikYesil = const Color(0xFFC5E1A5);
  final Color lacivert = const Color(0xFF002D72);

  final PageController _sayfaKontrolcu = PageController();
  int _mevcutSayfa = 0;
  bool _isLoading = false;
  late Ilan _gosterilenIlan;

  bool get _asiListesiGerekli => (_gosterilenIlan.ilanTipi == 'kayip' || _gosterilenIlan.ilanTipi == 'sahiplendirme') && (_gosterilenIlan.hayvanTuru == 'Kedi' || _gosterilenIlan.hayvanTuru == 'Köpek');

  bool get _isIlanSahibi {
    final currentUserId = supabase.auth.currentUser?.id;
    return currentUserId != null && currentUserId == _gosterilenIlan.kullaniciId;
  }

  Future<List<String>>? _asiListesiFuture;

  @override
  void initState() {
    super.initState();
    _gosterilenIlan = widget.ilan;
    if (_asiListesiGerekli) {
      _asiListesiFuture = ilanAsilariniGetir(_gosterilenIlan.id, _gosterilenIlan.ilanTipi);
    }
  }


  Future<void> _ilanSil() async {
    final bool onay = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İlanı Sil'),
        content: const Text('Bu ilanı silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;

    if (!onay) return;

    setState(() => _isLoading = true);

    try {
      final String ilanId = _gosterilenIlan.id;
      final String ilanTipi = _gosterilenIlan.ilanTipi;

      String tabloAdi = '';
      if (ilanTipi == 'kayip') tabloAdi = 'kayip_ilanlar';
      else if (ilanTipi == 'bulunan') tabloAdi = 'bulunan_ilanlar';
      else if (ilanTipi == 'sahiplendirme') tabloAdi = 'sahiplendirme_ilanlar';

      if (ilanTipi == 'kayip') await supabase.from('kayip_ilan_asilar').delete().eq('kayip_ilan_id', ilanId);
      else if (ilanTipi == 'sahiplendirme') await supabase.from('sahiplendirme_ilan_asilar').delete().eq('sahiplendirme_ilan_id', ilanId);

      await supabase.from('repostlar').delete().eq('ilan_id', ilanId).eq('ilan_tipi', ilanTipi);
      await supabase.from('begeniler').delete().eq('ilan_id', ilanId).eq('ilan_tipi', ilanTipi);
      await supabase.from('yorumlar').delete().eq('ilan_id', ilanId).eq('ilan_tipi', ilanTipi);

      final List<dynamic> fotoKayitlari = await supabase.from('ilan_fotograflari').select('foto_url').eq('ilan_id', ilanId).eq('ilan_tipi', ilanTipi);
      final List<String> silinecekYollar = [];
      for(final foto in fotoKayitlari) {
        final String url = foto['foto_url'] as String;
        final String dosyaYolu = Uri.parse(url).pathSegments.sublist(2).join('/');
        silinecekYollar.add(dosyaYolu);
      }
      if(silinecekYollar.isNotEmpty) await supabase.storage.from('hayvan_fotograflari').remove(silinecekYollar);

      await supabase.from('ilan_fotograflari').delete().eq('ilan_id', ilanId).eq('ilan_tipi', ilanTipi);

      if (ilanTipi == 'kayip') await supabase.from('eslesmeler').delete().eq('kayip_ilan_id', ilanId);
      else if (ilanTipi == 'bulunan') await supabase.from('eslesmeler').delete().eq('bulunan_ilan_id', ilanId);

      await supabase.from(tabloAdi).delete().eq('id', ilanId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İlan başarıyla silindi'), backgroundColor: Colors.green));
        Navigator.pop(context, 'silindi');
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _ilanDuzenleEkraniniAc() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => IlanDuzenleEkrani(ilan: _gosterilenIlan)),
    ).then((_) {
      Navigator.pop(context, 'duzenlendi');
    });
  }

  Future<void> ilanPaylas(BuildContext context) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Giriş yapmalısınız.'), backgroundColor: Colors.red));
      return;
    }
    try {
      final existingRepost = await supabase.from('repostlar').select('id').eq('kullanici_id', userId).eq('ilan_id', _gosterilenIlan.id).eq('ilan_tipi', _gosterilenIlan.ilanTipi).limit(1).maybeSingle();
      if (existingRepost != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Zaten paylaştınız.', style: TextStyle(color: Colors.white)), backgroundColor: turuncuPastel));
        return;
      }
      await supabase.from('repostlar').insert({'kullanici_id': userId, 'ilan_id': _gosterilenIlan.id, 'ilan_tipi': _gosterilenIlan.ilanTipi});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('İlan paylaşıldı!'), backgroundColor: zeytinYesili));
    } catch (e) {
      print("Repost hatası: $e");
    }
  }

  void _iletisimSecenekleriniGoster(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'İletişime Geç',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: zeytinYesili),
                ),
                const Divider(),
                ListTile(
                  leading: Icon(Icons.phone, color: zeytinYesili),
                  title: Text(_gosterilenIlan.telefonNumarasi),
                  subtitle: const Text('Ara'),
                  onTap: () {
                    Navigator.pop(context);
                    final url = Uri.parse('tel:${_gosterilenIlan.telefonNumarasi}');
                    launchUrl(url);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.message, color: turuncuPastel),
                  title: const Text('Mesaj Gönder'),
                  onTap: () async {
                    Navigator.pop(context);

                    final currentUser = supabase.auth.currentUser;
                    if (currentUser == null) return;
                    if (currentUser.id == _gosterilenIlan.kullaniciId) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Kendi ilanınıza mesaj atamazsınız.')));
                      return;
                    }

                    String temizKonum = "";
                    String sehirVerisi = _gosterilenIlan.sehir;

                    if (sehirVerisi.startsWith('POINT') || sehirVerisi.length > 40) {
                      LatLng? koordinat = _koordinatCozumle(_gosterilenIlan.hamKonum ?? sehirVerisi);

                      if (koordinat != null) {
                        try {
                          List<Placemark> placemarks = await placemarkFromCoordinates(
                              koordinat.latitude,
                              koordinat.longitude
                          );

                          if (placemarks.isNotEmpty) {
                            Placemark yer = placemarks.first;
                            temizKonum = "${yer.administrativeArea ?? ''}, ${yer.subAdministrativeArea ?? ''}";
                            if (temizKonum == ", ") temizKonum = "";
                          }
                        } catch (e) {
                          debugPrint("Adres çözümleme hatası: $e");
                        }
                      }
                    } else {
                      if (sehirVerisi != 'Konum Bilgisi Yok' && sehirVerisi.isNotEmpty) {
                        temizKonum = sehirVerisi;
                      }
                    }

                    String otomatikMesaj = "";

                    if (_gosterilenIlan.ilanTipi == 'kayip') {
                      otomatikMesaj = "Merhaba, ${_gosterilenIlan.hayvanAdi} isimli kayıp ilanınız için yazıyorum.";
                    } else if (_gosterilenIlan.ilanTipi == 'sahiplendirme') {
                      otomatikMesaj = "Merhaba, ${_gosterilenIlan.hayvanAdi} isimli sahiplendirme ilanınız için yazıyorum.";
                    } else {
                      String konumMetni = temizKonum.isNotEmpty ? "$temizKonum konumunda " : "";
                      otomatikMesaj = "Merhaba, ${konumMetni}bulunan ${_gosterilenIlan.hayvanRengi} ${_gosterilenIlan.hayvanTuru} ilanı için yazıyorum.";
                    }

                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SohbetEkrani(
                            aliciId: _gosterilenIlan.kullaniciId,
                            aliciAd: _gosterilenIlan.kullaniciAdi,
                            aliciFotoUrl: null,
                            baslangicMesaji: otomatikMesaj,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _profilSayfasinaYonlendir(String kullaniciId) {
    final currentUser = supabase.auth.currentUser;

    if (currentUser != null && currentUser.id == kullaniciId) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const Profil(),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => KullaniciProfili(kullaniciId: kullaniciId),
        ),
      );
    }
  }

  Future<void> _konumaYonlendir(String? hamKonumVerisi) async {
    if (hamKonumVerisi == null || hamKonumVerisi.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu ilanın kesin konum bilgisi mevcut değil.')),
      );
      return;
    }

    final LatLng? koordinat = _koordinatCozumle(hamKonumVerisi);

    if (koordinat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konum formatı çözümlenemiyor. (Veritabanı formatı hatalı olabilir)')),
      );
      return;
    }

    try {
      final String googleMapsUrl =
          'https://www.google.com/maps/dir/?api=1&destination=${koordinat.latitude},${koordinat.longitude}&dir_action=navigate';

      final Uri uri = Uri.parse(googleMapsUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Haritalar uygulamasını başlatılamıyor.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harita yönlendirme hatası.')),
      );
      debugPrint('Harita başlatma hatası: $e');
    }
  }

  void _fotografiTamEkranAc(List<String> imageUrls, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TamEkranGaleri(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color baslikRengi = _gosterilenIlan.ilanTipi == 'kayip' ? Colors.red : (_gosterilenIlan.ilanTipi == 'sahiplendirme' ? lacivert : zeytinYesili);
    String baslikMetni = _gosterilenIlan.ilanTipi == 'kayip' ? _gosterilenIlan.hayvanAdi : (_gosterilenIlan.ilanTipi == 'sahiplendirme' ? '${_gosterilenIlan.hayvanAdi} Yuva Arıyor' : 'Bulunan Hayvan');

    return Scaffold(

      appBar: AppBar(

        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _gosterilenIlan.hayvanAdi,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: zeytinYesili,
        foregroundColor: Colors.white,
      ),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Column(
          children: [
            _buildFotografGalerisi(baslikRengi),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(baslikMetni, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: baslikRengi)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _profilSayfasinaYonlendir(_gosterilenIlan.kullaniciId),
                        child: _buildInfoRow(
                          Icons.person,
                          'Sahibi: ${_gosterilenIlan.kullaniciAdi}',
                          color: baslikRengi,
                          isClickable: true,
                        ),
                      ),
                    ),
                    Expanded(child: KonumBilgisiWidget(hamKonumVerisi: _gosterilenIlan.sehir, iconColor: baslikRengi)),
                  ]),
                  const Divider(height: 30),

                  if (_gosterilenIlan.hamKonum != null)
                    Card(
                      elevation: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: Icon(Icons.pin_drop, color: lacivert, size: 28),
                        title: const Text(
                          "Google Haritalar ile Görüntüle",
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          _gosterilenIlan.sehir.contains('Konum Bilgisi Yok') ? "Konum bilgisi mevcut değil" : "Yol tarifi almak için dokunun (${_gosterilenIlan.sehir})",
                          style: TextStyle(color: Colors.grey),
                        ),
                        trailing: Icon(Icons.directions, color: turuncuPastel, size: 30),
                        onTap: () => _konumaYonlendir(_gosterilenIlan.hamKonum),
                      ),
                    ),

                  _buildDetailCard('Temel Bilgiler', [
                    _buildInfoRow(Icons.pets, 'Tür: ${_gosterilenIlan.hayvanTuru}'),
                    _buildInfoRow(Icons.color_lens, 'Renk: ${_gosterilenIlan.hayvanRengi}'),
                    if (_gosterilenIlan.hayvanCinsiyeti.isNotEmpty) _buildInfoRow(Icons.wc, 'Cinsiyet: ${_gosterilenIlan.hayvanCinsiyeti}'),

                    if (_gosterilenIlan.cipiVarMi) _buildInfoRow(Icons.memory, 'Çipli', color: zeytinYesili),
                  ]),
                  const SizedBox(height: 20),
                  if (_gosterilenIlan.ilanTipi == 'sahiplendirme') ...[
                    _buildDetailCard('Sahiplendirme Detayları', [
                      _buildInfoRow(Icons.health_and_safety, _gosterilenIlan.kisirMi ? 'Kısırlaştırılmış' : 'Kısırlaştırılmamış'),
                      _buildInfoRow(Icons.gavel, _gosterilenIlan.kisirlastirmaSarti ? 'Kısırlaştırma Şartı VAR' : 'Kısırlaştırma Şartı YOK', color: _gosterilenIlan.kisirlastirmaSarti ? Colors.red : Colors.green),
                      if (_gosterilenIlan.aliskanliklar != null && _gosterilenIlan.aliskanliklar!.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                      "Alışkanlıklar:",
                                      style: TextStyle(fontWeight: FontWeight.bold)
                                  ),
                                  Text(_gosterilenIlan.aliskanliklar!)
                                ]
                            )
                        ),
                    ]),
                    const SizedBox(height: 20),
                  ],
                  if (_asiListesiGerekli)
                    FutureBuilder<List<String>>(
                      future: _asiListesiFuture,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
                        return _buildDetailCard('Aşılar', snapshot.data!.map((e) => _buildInfoRow(Icons.vaccines, e)).toList());
                      },
                    ),
                  const SizedBox(height: 20),
                  _buildDetailCard('Açıklama', [
                    Text(
                      _gosterilenIlan.ekstraBilgi.trim().isEmpty
                          ? 'Ek bilgi bulunmamaktadır.'
                          : _gosterilenIlan.ekstraBilgi,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ]),
                  const SizedBox(height: 20),


                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {

                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => IlanDetayYorumModal(
                            ilanId: _gosterilenIlan.id,
                            ilanTipi: _gosterilenIlan.ilanTipi,
                          ),
                        );
                      },
                      icon: const Icon(Icons.forum, color: Colors.white),
                      label: const Text('Yorumları Görüntüle', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: turuncuPastel,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 3,
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]),
        child: Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => ilanPaylas(context),
              icon: const Icon(Icons.share, color: Colors.white),
              label: const Text('Paylaş', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: turuncuPastel, padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
          const SizedBox(width: 16),

          if (!_isIlanSahibi)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _iletisimSecenekleriniGoster(context),
                icon: const Icon(Icons.phone, color: Colors.white),
                label: const Text('İletişim', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: zeytinYesili, padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            )
          else
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _ilanSil,
                      icon: const Icon(Icons.delete, color: Colors.white, size: 18),
                      label: const Text('Sil', style: TextStyle(color: Colors.white, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _ilanDuzenleEkraniniAc,
                      icon: const Icon(Icons.edit, color: Colors.white, size: 18),
                      label: const Text('Düzenle', style: TextStyle(color: Colors.white, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: lacivert,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildFotografGalerisi(Color ikonRengi) {
    final fotolar = _gosterilenIlan.fotoUrlListesi;
    if (fotolar.isEmpty) {
      return Container(height: 300, color: Colors.grey.shade200, child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.pets, size: 80, color: ikonRengi.withOpacity(0.3)), const SizedBox(height: 10), Text("Fotoğraf Yok", style: TextStyle(color: Colors.grey.shade600, fontSize: 16))])));
    }
    return Column(children: [
      Container(
        height: 350, color: Colors.black12,
        child: PageView.builder(
          controller: _sayfaKontrolcu,
          itemCount: fotolar.length,
          onPageChanged: (i) => setState(() => _mevcutSayfa = i),
          itemBuilder: (c, i) {
            final url = Uri.encodeFull(fotolar[i]);

            return GestureDetector(
              onTap: () => _fotografiTamEkranAc(fotolar, i),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey)),
              ),
            );
          },
        ),
      ),
      if (fotolar.length > 1) Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(fotolar.length, (i) => Container(width: 8, height: 8, margin: const EdgeInsets.all(4), decoration: BoxDecoration(shape: BoxShape.circle, color: _mevcutSayfa == i ? turuncuPastel : Colors.grey)))),

      const Padding(
        padding: EdgeInsets.only(top: 8.0),
        child: Text(
          "(Büyütmek için fotoğrafa dokunun)",
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ),
    ]);
  }


  Widget _buildInfoRow(
      IconData icon,
      String text,
      {
        Color? color,
        bool isClickable = false
      }
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade800,
                fontWeight: isClickable ? FontWeight.bold : FontWeight.normal,
                decoration: isClickable ? TextDecoration.underline : TextDecoration.none,
                decorationColor: color ?? Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: acikYesil), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: zeytinYesili)), const Divider(), ...children]),
    );
  }
}



class IlanDetayYorumModal extends StatefulWidget {
  final String ilanId;
  final String ilanTipi;
  const IlanDetayYorumModal({super.key, required this.ilanId, required this.ilanTipi});

  @override
  State<IlanDetayYorumModal> createState() => _IlanDetayYorumModalState();
}

class _IlanDetayYorumModalState extends State<IlanDetayYorumModal> {
  final TextEditingController _yorumController = TextEditingController();
  bool _gonderiliyor = false;

  final Color turuncuPastel = const Color(0xFFFFB74D);
  final Color zeytinYesili = const Color(0xFF558B2F);
  final Color lacivert = const Color(0xFF002D72);

  Stream<List<Map<String, dynamic>>> _yorumlariGetir() {
    return Supabase.instance.client.from('yorumlar')
        .stream(primaryKey: ['id'])
        .eq('ilan_id', widget.ilanId)
        .order('created_at', ascending: true)
        .map((data) => List<Map<String, dynamic>>.from(data));
  }

  Future<Map<String, dynamic>?> _profilGetir(String kullaniciId) async {
    try {
      final data = await Supabase.instance.client.from('profiles').select('tam_ad, profil_foto').eq('id', kullaniciId).single();
      final String? dosyaYolu = data['profil_foto'];
      if (dosyaYolu != null && dosyaYolu.isNotEmpty) {
        final String url = await Supabase.instance.client.storage.from('profil_fotolari').createSignedUrl(dosyaYolu, 60);
        data['profil_foto_url'] = url;
      }
      return data;
    } catch(e) { return null; }
  }

  void _profilYonlendirme(String targetUserId) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null && currentUser.id == targetUserId) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const Profil()));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (context) => KullaniciProfili(kullaniciId: targetUserId)));
    }
  }

  Future<void> _yorumGonder() async {
    final text = _yorumController.text.trim();
    if (text.isEmpty) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => _gonderiliyor = true);
    try {
      await Supabase.instance.client.from('yorumlar').insert({
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
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        children: [
          Center(child: Container(margin: const EdgeInsets.only(top: 12, bottom: 8), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
          Text("Yorumlar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: lacivert)),
          const Divider(),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _yorumlariGetir(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Center(child: CircularProgressIndicator(color: zeytinYesili));
                final yorumlar = snapshot.data!;
                if (yorumlar.isEmpty) return const Center(child: Text("Henüz yorum yok. İlk yorumu sen yap!", style: TextStyle(color: Colors.grey)));

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
                                  backgroundColor: zeytinYesili.withOpacity(0.1),
                                  backgroundImage: fotoUrl != null ? NetworkImage(fotoUrl) : null,
                                  child: fotoUrl == null ? Icon(Icons.person, size: 20, color: zeytinYesili) : null,
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
                  icon: _gonderiliyor ? CircularProgressIndicator(strokeWidth: 2, color: zeytinYesili) : Icon(Icons.send, color: zeytinYesili)
              )
            ]),
          ),
        ],
      ),
    );
  }
}

class TamEkranGaleri extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const TamEkranGaleri({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  @override
  State<TamEkranGaleri> createState() => _TamEkranGaleriState();
}

class _TamEkranGaleriState extends State<TamEkranGaleri> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        alignment: Alignment.center,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.imageUrls.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final url = Uri.encodeFull(widget.imageUrls[index]);
              return InteractiveViewer(

                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (c, e, s) => const Icon(
                      Icons.broken_image,
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                ),
              );
            },
          ),


          Positioned(
            top: 50,
            left: 10,
            right: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${_currentIndex + 1} / ${widget.imageUrls.length}",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(width: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class KonumBilgisiWidget extends StatefulWidget {
  final dynamic hamKonumVerisi;
  final Color iconColor;
  const KonumBilgisiWidget({super.key, required this.hamKonumVerisi, required this.iconColor});
  @override
  State<KonumBilgisiWidget> createState() => _KonumBilgisiWidgetState();
}

class _KonumBilgisiWidgetState extends State<KonumBilgisiWidget> {
  String _adresMetni = "Konum Hesaplanıyor...";

  @override
  void initState() {
    super.initState();
    _adresiCozumle();
  }

  @override
  void didUpdateWidget(covariant KonumBilgisiWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hamKonumVerisi != oldWidget.hamKonumVerisi) {
      _adresiCozumle();
    }
  }

  Future<void> _adresiCozumle() async {
    String veri = widget.hamKonumVerisi?.toString() ?? "";
    if (veri.isEmpty || veri == 'Konum Bilgisi Yok' || veri == 'null') {
      if (mounted) setState(() => _adresMetni = "Konum Yok");
      return;
    }
    bool sayiVarMi = RegExp(r'\d').hasMatch(veri);
    if (!sayiVarMi) {
      if (mounted) setState(() => _adresMetni = veri);
      return;
    }

    final LatLng? koordinat = _koordinatCozumle(veri);

    if (koordinat == null) {
      if (mounted) setState(() => _adresMetni = "Konum Formatı Hatalı");
      return;
    }

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(koordinat.latitude, koordinat.longitude);

      if (placemarks.isNotEmpty && mounted) {
        Placemark yer = placemarks.first;
        String adres = "${yer.administrativeArea ?? ''}, ${yer.subAdministrativeArea ?? ''}";
        if (adres == ", ") adres = "Bilinmeyen Konum";
        setState(() => _adresMetni = adres);
      }
    } catch (geoError) {
      if (mounted) setState(() => _adresMetni = "${koordinat.latitude.toStringAsFixed(2)}, ${koordinat.longitude.toStringAsFixed(2)}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [Icon(Icons.location_on, size: 20, color: widget.iconColor), const SizedBox(width: 8), Expanded(child: Text(_adresMetni, style: TextStyle(fontSize: 15, color: Colors.grey.shade800), overflow: TextOverflow.ellipsis))]),
    );
  }
}


class IlanDuzenleEkrani extends StatefulWidget {
  final Ilan ilan;
  const IlanDuzenleEkrani({super.key, required this.ilan});

  @override
  State<IlanDuzenleEkrani> createState() => _IlanDuzenleEkraniState();
}

class _IlanDuzenleEkraniState extends State<IlanDuzenleEkrani> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  bool _yukleniyor = false;
  bool _fotografIsleniyor = false;

  late TextEditingController _hayvanAdController;
  late TextEditingController _ekstraBilgiController;
  late TextEditingController _konumController;
  late TextEditingController _digerHayvanController;
  late TextEditingController _aliskanlikController;

  LatLng? _guncelKoordinat;

  String? _secilenHayvanTuru;
  String? _secilenHayvanRengi;
  String _cinsiyet = 'Disi';
  bool _cipli = false;
  bool _kisirMi = false;
  bool _kisirlastirmaSarti = false;

  List<Map<String, dynamic>> _tumAsiSecenekleri = [];
  List<String> _secilenAsiIdleri = [];
  bool _asilariYukleniyor = true;

  List<String> _mevcutFotograflar = [];
  List<XFile> _eklenecekYeniFotograflar = [];

  bool get _isKayip => widget.ilan.ilanTipi == 'kayip';
  bool get _isSahiplendirme => widget.ilan.ilanTipi == 'sahiplendirme';
  bool get _asiGereklidir => _secilenHayvanTuru == 'Kedi' || _secilenHayvanTuru == 'Köpek';

  final Color turuncuPastel = const Color(0xFFFFB74D);
  final Color zeytinYesili = const Color(0xFF558B2F);
  final Color arkaPlan = const Color(0xFFF1F8E9);
  final Color gri = const Color(0xFF9E9E9E);
  final Color beyaz = Colors.white;

  final List<String> hayvanTurleri = const ['Kedi', 'Köpek', 'Kuş', 'Hamster', 'Diğer'];
  final Map<String, List<String>> renkSecenekleri = const {
    'Kedi': ['Sarman', 'Tekir', 'Smokin', 'Siyah', 'Beyaz', 'Gri', 'Kahverengi', 'Calico'],
    'Köpek': ['Sarı', 'Siyah', 'Beyaz', 'Gri', 'Kahverengi', 'Dalmaçyalı', 'Çok renkli'],
    'Kuş': ['Sarı', 'Yeşil', 'Mavi', 'Beyaz', 'Gri', 'Kırmızı', 'Mor', 'Çok renkli'],
    'Hamster': ['Sarı', 'Kahverengi', 'Beyaz', 'Gri', 'Siyah', 'Çok renkli'],
    'Diğer': ['Siyah', 'Beyaz', 'Gri', 'Kahverengi', 'Krem', 'Sarı', 'Turuncu', 'Kızıl', 'Altın', 'Mavi', 'Yeşil', 'Çok renkli'],
  };
  List<String> _mevcutRenkSecenekleri = [];

  @override
  void initState() {
    super.initState();
    _digerHayvanController = TextEditingController();
    _hayvanAdController = TextEditingController(text: widget.ilan.hayvanAdi == 'İsimsiz' ? '' : widget.ilan.hayvanAdi);
    _ekstraBilgiController = TextEditingController(text: widget.ilan.ekstraBilgi);
    _aliskanlikController = TextEditingController(text: widget.ilan.aliskanliklar ?? '');
    _konumController = TextEditingController();

    _formuDoldur();
    _mevcutFotograflar = List.from(widget.ilan.fotoUrlListesi);

    if (_isKayip || _isSahiplendirme) {
      _asilariVeMevcutSecimleriYukle();
    } else {
      _asilariYukleniyor = false;
    }

    _konumVerisiniIsle();
  }

  @override
  void dispose() {
    _hayvanAdController.dispose();
    _ekstraBilgiController.dispose();
    _konumController.dispose();
    _digerHayvanController.dispose();
    _aliskanlikController.dispose();
    super.dispose();
  }

  void _formuDoldur() {
    if (_isKayip || _isSahiplendirme) {
      _cinsiyet = widget.ilan.hayvanCinsiyeti;
      _cipli = widget.ilan.cipiVarMi;
    }

    if (_isSahiplendirme) {
      _kisirMi = widget.ilan.kisirMi;
      _kisirlastirmaSarti = widget.ilan.kisirlastirmaSarti;
    }

    String tur = widget.ilan.hayvanTuru;
    if (hayvanTurleri.contains(tur)) {
      _secilenHayvanTuru = tur;
      _mevcutRenkSecenekleri = List.of(renkSecenekleri[tur] ?? []);
    } else {
      _secilenHayvanTuru = 'Diğer';
      _digerHayvanController.text = tur;
      _mevcutRenkSecenekleri = List.of(renkSecenekleri['Diğer']!);
    }

    String renk = widget.ilan.hayvanRengi;
    if (_mevcutRenkSecenekleri.contains(renk)) {
      _secilenHayvanRengi = renk;
    } else {
      _mevcutRenkSecenekleri.add(renk);
      _secilenHayvanRengi = renk;
    }
  }

  void _konumVerisiniIsle() {
    _guncelKoordinat = _koordinatCozumle(widget.ilan.hamKonum);
    if (_guncelKoordinat != null) {
      _konumController.text = "Mevcut Konum Çözümleniyor...";
      _koordinatlariAdreseCevir(_guncelKoordinat!);
    } else {
      _konumController.text = "Konumu değiştirmek için tıklayınız";
    }
  }

  Future<void> _koordinatlariAdreseCevir(LatLng koordinat) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
          koordinat.latitude,
          koordinat.longitude
      );

      String adresGosterimi;
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        adresGosterimi = "Mevcut Konum: ${place.administrativeArea ?? '?'} / ${place.subAdministrativeArea ?? '?'}";
      } else {
        adresGosterimi = "Mevcut Koordinat: ${koordinat.latitude.toStringAsFixed(4)}, ${koordinat.longitude.toStringAsFixed(4)}";
      }

      if (mounted) setState(() => _konumController.text = adresGosterimi);

    } catch (e) {
      if (mounted) setState(() => _konumController.text = "Konum: ${koordinat.latitude.toStringAsFixed(4)}, ${koordinat.longitude.toStringAsFixed(4)}");
    }
  }

  Future<void> _asilariVeMevcutSecimleriYukle() async {
    try {
      final List<dynamic>? tumVeriler = await supabase.from('asilistesi').select('id, asi_adi, hayvan_turu');

      String tabloAdi = _isSahiplendirme ? 'sahiplendirme_ilan_asilar' : 'kayip_ilan_asilar';
      String kolonAdi = _isSahiplendirme ? 'sahiplendirme_ilan_id' : 'kayip_ilan_id';

      final List<dynamic>? mevcutVeriler = await supabase
          .from(tabloAdi)
          .select('asi_id')
          .eq(kolonAdi, widget.ilan.id);

      final List<String> mevcutAsiIdleri = mevcutVeriler?.map((e) => e['asi_id'] as String).toList() ?? [];

      if (mounted) {
        setState(() {
          _tumAsiSecenekleri = tumVeriler?.cast<Map<String, dynamic>>() ?? [];
          _secilenAsiIdleri = mevcutAsiIdleri;
          _asilariYukleniyor = false;
        });
      }
    } catch (e) {
      print('Aşı yükleme hatası: $e');
      if (mounted) setState(() { _asilariYukleniyor = false; });
    }
  }

  void _hayvanTuruDegisti(String? yeniTur) {
    setState(() {
      _secilenHayvanTuru = yeniTur;
      _digerHayvanController.clear();
      _secilenHayvanRengi = null;
      _secilenAsiIdleri.clear();

      if (yeniTur != null && renkSecenekleri.containsKey(yeniTur)) {
        _mevcutRenkSecenekleri = List.of(renkSecenekleri[yeniTur]!);
      } else {
        _mevcutRenkSecenekleri = List.of(renkSecenekleri['Diğer']!);
      }

      if (_isKayip || _isSahiplendirme) {
        _asilariYukleniyor = true;
        _asilariVeMevcutSecimleriYukle();
      }
    });
  }

  Future<void> _haritadanKonumGuncelle() async {
    final LatLng? yeniKonum = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => KonumSecSayfasi(
          baslangicKonumu: _guncelKoordinat,
        ),
      ),
    );

    if (yeniKonum != null) {
      setState(() {
        _guncelKoordinat = yeniKonum;
        _konumController.text = "Yeni Konum Seçildi ✅\n(${yeniKonum.latitude.toStringAsFixed(5)}, ${yeniKonum.longitude.toStringAsFixed(5)})";
      });
    }
  }

  Future<File?> _downloadFile(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/${DateTime.now().millisecondsSinceEpoch}_temp.jpg';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }
    } catch (e) {
      debugPrint("Fotoğraf indirme hatası: $e");
    }
    return null;
  }

  Future<XFile?> _resmiKirp(XFile dosya) async {
    CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: dosya.path,
      aspectRatioPresets: [
        CropAspectRatioPreset.square,
        CropAspectRatioPreset.ratio3x2,
        CropAspectRatioPreset.original,
        CropAspectRatioPreset.ratio4x3,
        CropAspectRatioPreset.ratio16x9
      ],
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Fotoğrafı Düzenle',
          toolbarColor: zeytinYesili,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          activeControlsWidgetColor: turuncuPastel,
        ),
        IOSUiSettings(
          title: 'Fotoğrafı Düzenle',
        ),
      ],
    );

    if (croppedFile != null) {
      return XFile(croppedFile.path);
    }
    return null;
  }

  Future<void> _mevcutFotografiKirp(String url, int index) async {
    setState(() => _fotografIsleniyor = true);

    File? tempFile = await _downloadFile(url);

    if (tempFile != null && mounted) {
      XFile? croppedFile = await _resmiKirp(XFile(tempFile.path));

      if (croppedFile != null && mounted) {
        setState(() {
          _eklenecekYeniFotograflar.add(croppedFile);
        });

        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: const Text('Kırpılan versiyon eklendi. İstemediğinizi silebilirsiniz.'),
                backgroundColor: zeytinYesili
            )
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf indirilemedi.'), backgroundColor: Colors.red)
      );
    }

    if(mounted) setState(() => _fotografIsleniyor = false);
  }

  Future<void> _fotoCekVeyaSec() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: beyaz,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.camera_alt, color: Color(0xFF007bff)), title: const Text('Kamera ile çek'), onTap: () => Navigator.pop(context, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library, color: Color(0xFF007bff)), title: const Text('Galeriden seç (Çoklu)'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
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
          if (kirpilmisFoto != null) {
            setState(() => _eklenecekYeniFotograflar.add(kirpilmisFoto));
          }
        }
      }
    } else {
      final XFile? foto = await _picker.pickImage(source: source, imageQuality: 85);
      if (foto != null) {
        XFile? kirpilmisFoto = await _resmiKirp(foto);
        if (kirpilmisFoto != null) {
          setState(() => _eklenecekYeniFotograflar.add(kirpilmisFoto));
        }
      }
    }
  }

  Future<void> _mevcutFotografiSil(String url, int index) async {
    if (_yukleniyor || _fotografIsleniyor) return;
    setState(() => _yukleniyor = true);

    if (_mevcutFotograflar.length + _eklenecekYeniFotograflar.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İlanda en az bir fotoğraf olmalıdır!'), backgroundColor: Colors.red));
      setState(() => _yukleniyor = false);
      return;
    }

    try {
      const String bucketAdi = 'hayvan_fotograflari';
      final Uri uri = Uri.parse(url);
      final String path = uri.path;
      final String bucketPathIdentifier = '/$bucketAdi/';
      final int startIndex = path.indexOf(bucketPathIdentifier);

      if (startIndex != -1) {
        final String dosyaYolu = path.substring(startIndex + bucketPathIdentifier.length);
        await supabase.storage.from(bucketAdi).remove([dosyaYolu]);
      }

      await supabase.from('ilan_fotograflari').delete().eq('foto_url', url);

      setState(() {
        _mevcutFotograflar.removeAt(index);
        _yukleniyor = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Fotoğraf silindi.'), backgroundColor: zeytinYesili));
    } catch (e) {
      setState(() => _yukleniyor = false);
      print("Silme Hatası Detay: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Silme hatası oluştu.'), backgroundColor: Colors.red));
    }
  }

  Future<void> _yeniFotograflariYukle(String ilanId, String ilanTipi) async {
    for (int i = 0; i < _eklenecekYeniFotograflar.length; i++) {
      final XFile foto = _eklenecekYeniFotograflar[i];
      try {
        final bytes = await File(foto.path).readAsBytes();
        final String ext = foto.name.split('.').last.toLowerCase().replaceAll('jpg', 'jpeg');
        const String bucketAdi = 'hayvan_fotograflari';

        String tipPath = 'diger';
        if (ilanTipi == 'kayip') tipPath = 'kayip';
        else if (ilanTipi == 'bulunan') tipPath = 'bulunan';
        else if (ilanTipi == 'sahiplendirme') tipPath = 'sahiplendirme';

        final String dosyaYolu = '$tipPath/$ilanId/yenieklenen_${DateTime.now().millisecondsSinceEpoch}_$i.$ext';

        await supabase.storage.from(bucketAdi).uploadBinary(
          dosyaYolu, bytes, fileOptions: FileOptions(upsert: false, contentType: 'image/$ext'),
        );

        final String publicUrl = supabase.storage.from(bucketAdi).getPublicUrl(dosyaYolu);

        await supabase.from('ilan_fotograflari').insert({
          'ilan_id': ilanId,
          'ilan_tipi': ilanTipi,
          'foto_url': publicUrl,
        });
      } catch (e) {
        print('Yeni fotoğraf yüklenemedi: $e');
      }
    }
  }

  Future<void> _ilanGuncelle() async {
    if (!_formKey.currentState!.validate() || _yukleniyor || _fotografIsleniyor) return;

    if (_mevcutFotograflar.isEmpty && _eklenecekYeniFotograflar.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('En az bir fotoğraf olmalı!'), backgroundColor: Colors.red));
      return;
    }

    setState(() { _yukleniyor = true; });

    try {
      final String ilanId = widget.ilan.id;
      final String? finalHayvanTuru = (_secilenHayvanTuru == 'Diğer' && _digerHayvanController.text.trim().isNotEmpty)
          ? _digerHayvanController.text.trim()
          : _secilenHayvanTuru;

      final Map<String, dynamic> params = {
        'p_ilan_id': ilanId,
        'p_hayvan_turu': finalHayvanTuru,
        'p_hayvan_rengi': _secilenHayvanRengi,
        'p_aciklama': _ekstraBilgiController.text.trim().isNotEmpty ? _ekstraBilgiController.text.trim() : null,
        'p_lat': _guncelKoordinat?.latitude,
        'p_lng': _guncelKoordinat?.longitude,
      };

      if (_isKayip) {
        params['p_hayvan_adi'] = _hayvanAdController.text.trim().isNotEmpty ? _hayvanAdController.text.trim() : null;
        params['p_hayvan_cinsiyeti'] = _cinsiyet;
        params['p_cipi_var_mi'] = _cipli;
        await supabase.rpc('kayip_ilan_guncelle', params: params);
      } else if (_isSahiplendirme) {
        await supabase.from('sahiplendirme_ilanlar').update({
          'hayvan_adi': _hayvanAdController.text.trim().isNotEmpty ? _hayvanAdController.text.trim() : "İsimsiz",
          'hayvan_turu': finalHayvanTuru,
          'hayvan_rengi': _secilenHayvanRengi,
          'ekstra_bilgi': _ekstraBilgiController.text.trim(),
          'hayvan_cinsiyeti': _cinsiyet,
          'cipi_var_mi': _cipli,
          'kisir_mi': _kisirMi,
          'kisirlastirma_sarti': _kisirlastirmaSarti,
          'aliskanliklar': _aliskanlikController.text.trim(),
          if (_guncelKoordinat != null)
            'konum': 'POINT(${_guncelKoordinat!.longitude} ${_guncelKoordinat!.latitude})',
        }).eq('id', ilanId);
      } else {
        await supabase.rpc('bulunan_ilan_guncelle', params: params);
      }

      if ((_isKayip || _isSahiplendirme) && _asiGereklidir) {
        await _ilanAsilariniGuncelle(ilanId, _secilenAsiIdleri, isSahiplendirme: _isSahiplendirme);
      }

      if (_eklenecekYeniFotograflar.isNotEmpty) {
        await _yeniFotograflariYukle(ilanId, widget.ilan.ilanTipi);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İlan güncellendi!'), backgroundColor: Color(0xFF558B2F)));
        Navigator.pop(context);
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() { _yukleniyor = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    String baslik = _isKayip ? 'Kayıp İlanı Düzenle' : (_isSahiplendirme ? 'Sahiplendirme İlanı Düzenle' : 'Bulunan İlanı Düzenle');

    return Scaffold(
      backgroundColor: beyaz,
      appBar: AppBar(title: Text(baslik), backgroundColor: beyaz, foregroundColor: zeytinYesili, elevation: 0),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFotoDuzenlemeAlani(),
                  if (_isKayip || _isSahiplendirme)
                    _buildTextField(controller: _hayvanAdController, label: 'Hayvan Adı', icon: Icons.pets, required: true),
                  _buildDropdown(value: _secilenHayvanTuru, label: 'Hayvan Türü', items: hayvanTurleri, onChanged: _hayvanTuruDegisti, required: true),
                  if (_secilenHayvanTuru == 'Diğer')
                    _buildTextField(controller: _digerHayvanController, label: 'Tür Belirtiniz', icon: Icons.edit, required: true),
                  _buildDropdown(value: _secilenHayvanRengi, label: 'Hayvan Rengi', items: _mevcutRenkSecenekleri, onChanged: (v) => setState(() => _secilenHayvanRengi = v), required: true),
                  if (_isKayip || _isSahiplendirme) _buildAsiDuzenlemeAlani(),
                  _buildLocationField(),
                  _buildTextField(controller: _ekstraBilgiController, label: 'Açıklama', icon: Icons.info, maxLines: 3),
                  if (_isSahiplendirme) ...[
                    _buildTextField(controller: _aliskanlikController, label: 'Alışkanlıklar', icon: Icons.psychology),
                    CheckboxListTile(title: const Text('Kısırlaştırılmış mı?'), value: _kisirMi, onChanged: (v) => setState(() => _kisirMi = v!), activeColor: turuncuPastel),
                    CheckboxListTile(title: const Text('Kısırlaştırma Şartı Var mı?'), value: _kisirlastirmaSarti, onChanged: (v) => setState(() => _kisirlastirmaSarti = v!), activeColor: turuncuPastel),
                  ],
                  if (_isKayip || _isSahiplendirme)
                    Row(children: [
                      Expanded(child: _buildDropdown(value: _cinsiyet, label: 'Cinsiyet', items: const ['Dişi', 'Erkek'], onChanged: (v) => setState(() => _cinsiyet = v ?? 'Dişi'))),
                      const SizedBox(width: 10),
                      Expanded(child: SwitchListTile(title: const Text('Çipli mi?', style: TextStyle(fontSize: 12)), value: _cipli, onChanged: (v) => setState(() => _cipli = v), activeColor: turuncuPastel)),
                    ]),
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: (_yukleniyor || _fotografIsleniyor) ? null : _ilanGuncelle, style: ElevatedButton.styleFrom(backgroundColor: zeytinYesili, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: _yukleniyor ? const CircularProgressIndicator(color: Colors.white) : const Text('Değişiklikleri Kaydet', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)))),
                ],
              ),
            ),
          ),
          if (_fotografIsleniyor)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text("Fotoğraf hazırlanıyor...", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, IconData icon = Icons.edit, bool required = false, int maxLines = 1}) {
    return Padding(padding: const EdgeInsets.only(bottom: 12.0), child: TextFormField(controller: controller, maxLines: maxLines, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, color: turuncuPastel), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: arkaPlan), validator: required ? (v) => v!.trim().isEmpty ? '$label zorunlu.' : null : null));
  }

  Widget _buildDropdown({required String? value, required String label, required List<String> items, required Function(String?) onChanged, bool required = false}) {
    List<String> uniqueItems = items.toSet().toList();
    if (value != null && !uniqueItems.contains(value)) uniqueItems.add(value);
    return Padding(padding: const EdgeInsets.only(bottom: 12.0), child: DropdownButtonFormField<String>(value: value, decoration: InputDecoration(labelText: label, prefixIcon: Icon(Icons.category, color: turuncuPastel), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: arkaPlan), isExpanded: true, items: uniqueItems.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: onChanged, validator: required ? (v) => v == null ? '$label zorunlu.' : null : null));
  }

  Widget _buildLocationField() {
    return Padding(padding: const EdgeInsets.only(bottom: 12.0), child: TextFormField(controller: _konumController, readOnly: true, onTap: _haritadanKonumGuncelle, maxLines: 2, decoration: InputDecoration(labelText: 'Konum', prefixIcon: const Icon(Icons.map, color: Color(0xFFFFB74D)), suffixIcon: const Icon(Icons.chevron_right), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: arkaPlan)));
  }

  Widget _buildFotoDuzenlemeAlani() {
    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _mevcutFotograflar.length + _eklenecekYeniFotograflar.length + 1,
        itemBuilder: (context, index) {
          if (index == _mevcutFotograflar.length + _eklenecekYeniFotograflar.length) {
            return GestureDetector(
              onTap: (_yukleniyor || _fotografIsleniyor) ? null : _fotoCekVeyaSec,
              child: Container(width: 100, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: arkaPlan, borderRadius: BorderRadius.circular(8), border: Border.all(color: turuncuPastel)), child: Icon(Icons.add_a_photo, color: turuncuPastel)),
            );
          }

          if (index < _mevcutFotograflar.length) {
            final url = _mevcutFotograflar[index];
            return Stack(children: [
              GestureDetector(
                onTap: (_yukleniyor || _fotografIsleniyor) ? null : () => _mevcutFotografiKirp(url, index),
                child: Container(width: 100, margin: const EdgeInsets.only(right: 8), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, fit: BoxFit.cover))),
              ),
              Positioned(top: 2, right: 10, child: GestureDetector(onTap: (_yukleniyor || _fotografIsleniyor) ? null : () => _mevcutFotografiSil(url, index), child: const CircleAvatar(radius: 10, backgroundColor: Colors.red, child: Icon(Icons.close, size: 14, color: Colors.white)))),
            ]);
          }

          final file = _eklenecekYeniFotograflar[index - _mevcutFotograflar.length];
          return Stack(children: [
            Container(width: 100, margin: const EdgeInsets.only(right: 8), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(file.path), fit: BoxFit.cover))),
            Positioned(top: 2, right: 10, child: GestureDetector(onTap: (_yukleniyor || _fotografIsleniyor) ? null : () => setState(() => _eklenecekYeniFotograflar.removeAt(index - _mevcutFotograflar.length)), child: const CircleAvatar(radius: 10, backgroundColor: Colors.orange, child: Icon(Icons.close, size: 14, color: Colors.white))))
          ]);
        },
      ),
    );
  }

  Widget _buildAsiDuzenlemeAlani() {
    if (!_asiGereklidir) return const SizedBox.shrink();
    if (_asilariYukleniyor) return const Center(child: CircularProgressIndicator());
    final ilgiliAsilar = _tumAsiSecenekleri.where((a) => a['hayvan_turu'] == _secilenHayvanTuru).toList();

    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: arkaPlan, borderRadius: BorderRadius.circular(12), border: Border.all(color: gri.withOpacity(0.3))),
      child: Column(children: ilgiliAsilar.map((asi) {
        final id = asi['id'] as String;
        return CheckboxListTile(title: Text(asi['asi_adi'], style: TextStyle(color: zeytinYesili)), value: _secilenAsiIdleri.contains(id), onChanged: (v) => setState(() => v! ? _secilenAsiIdleri.add(id) : _secilenAsiIdleri.remove(id)), activeColor: turuncuPastel, controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero);
      }).toList()),
    );
  }
}