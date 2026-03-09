import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'akis.dart';
import 'harita.dart';
import 'ana_ekran.dart';
import 'ilanlar.dart';
import 'profil.dart';

final supabase = Supabase.instance.client;

class SharedBottomNavBar extends StatefulWidget {
  final int currentIndex;
  final Color turuncuPastel;
  final Color gri;
  final Color beyaz;

  const SharedBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.turuncuPastel,
    required this.gri,
    required this.beyaz,
  });

  @override
  State<SharedBottomNavBar> createState() => _SharedBottomNavBarState();
}

class _SharedBottomNavBarState extends State<SharedBottomNavBar> {
  // Akışları (Streams) hafızada tutmak için değişkenler
  late final Stream<int> _mesajStream;
  late final Stream<int> _bildirimStream;

  @override
  void initState() {
    super.initState();
    // Streamleri sayfa ilk açıldığında BİR KERE tanımlıyoruz.
    // Bu sayede bağlantı sürekli açık kalır ve anlık değişimleri kaçırmaz.
    _baslatStreamler();
  }

  void _baslatStreamler() {
    final myId = supabase.auth.currentUser?.id;

    if (myId == null) {
      _mesajStream = Stream.value(0);
      _bildirimStream = Stream.value(0);
      return;
    }

    //  MESAJ SAYISI AKIŞI
    _mesajStream = supabase
        .from('mesajlar')
        .stream(primaryKey: ['id'])
        .eq('alici_id', myId)
        .map((list) => list.where((m) => m['okundu'] == false).length);

    // BİLDİRİM SAYISI AKIŞI (Anasayfa için)
    _bildirimStream = supabase
        .from('bildirimler')
        .stream(primaryKey: ['id'])
        .eq('kullanici_id', myId)
        .map((list) => list.where((b) => b['goruldu'] == false).length);
  }

  void _handleTap(BuildContext context, int index) {
    if (index == widget.currentIndex) return;
    Widget page;
    switch (index) {
      case 0:
        page = const AkisSayfasi();
        break;
      case 1:
        page = const HaritaSayfasi();
        break;
      case 2:
        page = const AnaEkran(kullaniciAdi: '');
        break;
      case 3:
        page = const IlanlarSayfasi();
        break;
      case 4:
        page = const Profil();
        break;
      default:
        page = const AnaEkran(kullaniciAdi: '');
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: const Duration(milliseconds: 250),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: widget.gri.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      // StreamBuilder'ları iç içe kullanıyoruz ama stream kaynakları sabit (initState'ten geliyor)
      child: StreamBuilder<int>(
        stream: _mesajStream, // Sabit Stream
        initialData: 0,
        builder: (context, snapshotMesaj) {
          final int mesajSayisi = snapshotMesaj.data ?? 0;

          return StreamBuilder<int>(
            stream: _bildirimStream, // Sabit Stream
            initialData: 0,
            builder: (context, snapshotBildirim) {
              final int bildirimSayisi = snapshotBildirim.data ?? 0;

              return BottomNavigationBar(
                currentIndex: widget.currentIndex,
                backgroundColor: widget.beyaz,
                selectedItemColor: widget.turuncuPastel,
                unselectedItemColor: widget.gri,
                selectedLabelStyle: TextStyle(color: widget.turuncuPastel),
                unselectedLabelStyle: TextStyle(color: widget.gri),
                type: BottomNavigationBarType.fixed,
                onTap: (index) => _handleTap(context, index),
                items: [
                  // 0. AKIŞ
                  BottomNavigationBarItem(
                    icon: _buildIconWithBadge(
                      icon: Icons.timeline,
                      count: mesajSayisi,
                      badgeColor: Colors.blue,
                    ),
                    label: 'Akış',
                  ),

                  // 1. HARİTA
                  const BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Harita'),

                  // 2. ANA SAYFA 
                  BottomNavigationBarItem(
                    icon: _buildIconWithBadge(
                      icon: Icons.home,
                      count: bildirimSayisi,
                      badgeColor: const Color(0xFFFFB74D),
                    ),
                    label: 'Ana Sayfa',
                  ),

                  // 3. İLANLAR
                  const BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'İlanlar'),

                  // 4. PROFİL
                  const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // Rozet Oluşturucu
  Widget _buildIconWithBadge({
    required IconData icon,
    required int count,
    required Color badgeColor
  }) {
    if (count <= 0) {
      return Icon(icon);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          right: -4,
          top: -4,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            constraints: const BoxConstraints(
              minWidth: 18,
              minHeight: 18,
            ),
            child: Center(
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
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