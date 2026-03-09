import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class KonumSecSayfasi extends StatefulWidget {
  final LatLng? baslangicKonumu;

  const KonumSecSayfasi({super.key, this.baslangicKonumu});

  @override
  State<KonumSecSayfasi> createState() => _KonumSecSayfasiState();
}

class _KonumSecSayfasiState extends State<KonumSecSayfasi> {
  LatLng? _secilenKonum;
  GoogleMapController? _mapController;

  // Varsayılan Ankara (GPS kapalıysa veya izin yoksa)
  final LatLng _varsayilanKonum = const LatLng(39.9334, 32.8597);

  @override
  void initState() {
    super.initState();

    // YENİ: Eğer dışarıdan bir konum geldiyse (Profil düzenlemeden) onu seçili yap
    if (widget.baslangicKonumu != null) {
      _secilenKonum = widget.baslangicKonumu;
    } else {
      _suankiKonumuBul();
    }
  }

  Future<void> _suankiKonumuBul() async {
    LocationPermission izin = await Geolocator.checkPermission();
    if (izin == LocationPermission.denied) {
      izin = await Geolocator.requestPermission();
    }

    if (izin == LocationPermission.whileInUse || izin == LocationPermission.always) {
      // Eğer düzenleme modundaysak (baslangicKonumu varsa) GPS'e zorla gitmesin, ilanın konumunda kalsın.
      if (widget.baslangicKonumu != null) return;

      try {
        Position position = await Geolocator.getCurrentPosition();
        if(mounted) {
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(LatLng(position.latitude, position.longitude), 15),
          );
          setState(() {
            _secilenKonum = LatLng(position.latitude, position.longitude);
          });
        }
      } catch (e) {
        debugPrint("Konum alınamadı: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Konumu Seç / Düzenle"),
        backgroundColor: const Color(0xFF558B2F),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.white),
            tooltip: "Seçimi Onayla",
            onPressed: () {
              // Seçilen konumu geri gönder
              if (_secilenKonum != null) {
                Navigator.pop(context, _secilenKonum);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Lütfen bir konum işaretleyin"))
                );
              }
            },
          )
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.baslangicKonumu ?? _varsayilanKonum,
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            onMapCreated: (controller) => _mapController = controller,
            // Harita her hareket ettiğinde ortadaki noktayı al
            onCameraMove: (CameraPosition position) {
              _secilenKonum = position.target;
            },
          ),
          // EKRANIN TAM ORTASINA SABİT İĞNE
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 40.0), // İğnenin ucu merkeze gelsin diye hafif yukarı
              child: Icon(Icons.location_on, size: 50, color: Colors.redAccent),
            ),
          ),
          // Bilgilendirme Kartı
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5)],
              ),
              child: const Text(
                "Haritayı kaydırarak iğneyi doğru konuma getirip sağ üstteki tike basınız.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}