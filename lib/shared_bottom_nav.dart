import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'akis.dart';
import 'harita.dart';
import 'ana_ekran.dart';
import 'ilanlar.dart';
import 'profil.dart';

// MÜHENDİSLİK DOKUNUŞU: Sınıfı StatelessWidget yaptık.
// Artık ana ekran her yenilendiğinde, navbar da anında taze veriyi çekecek! ✅
class SharedBottomNavBar extends StatelessWidget {
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

  void _handleTap(BuildContext context, int index) {
    if (index == currentIndex) return;
    Widget page;
    switch (index) {
      case 0: page = const AkisSayfasi(); break;
      case 1: page = const HaritaSayfasi(); break;
      case 2: page = const AnaEkran(kullaniciAdi: ''); break;
      case 3: page = const IlanlarSayfasi(); break;
      case 4: page = const Profil(); break;
      default: page = const AnaEkran(kullaniciAdi: '');
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
    final myId = Supabase.instance.client.auth.currentUser?.id;

    if (myId == null) {
      return _buildBottomNav(context, 0, 0); // Giriş yapılmadıysa sıfır gönder
    }

    // 1. MESAJLAR AKIŞI
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('mesajlar')
          .stream(primaryKey: ['id'])
          .eq('alici_id', myId),
      builder: (context, mesajSnapshot) {

        // 2. SOSYAL BİLDİRİMLER AKIŞI
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client
              .from('bildirimler')
              .stream(primaryKey: ['id'])
              .eq('kullanici_id', myId),
          builder: (context, sosyalSnapshot) {

            // 3. EŞLEŞMELER AKIŞI (Ana ekrandaki mantığın birebir aynısı) ✅
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('eslesmeler')
                  .stream(primaryKey: ['id'])
                  .eq('kontrol_edildi', false)
                  .asyncMap((tumEslesmeler) async {
                final benimIlanlarim = await Supabase.instance.client
                    .from('kayip_ilanlar')
                    .select('id')
                    .eq('kullanici_id', myId);
                final benimIdSetim = benimIlanlarim.map((e) => e['id'].toString()).toSet();
                return tumEslesmeler.where((e) => benimIdSetim.contains(e['kayip_ilan_id'].toString())).toList();
              }),
              builder: (context, eslesmeSnapshot) {

                // --- SAYIM İŞLEMLERİ ---
                int mesajSayisi = 0;
                if (mesajSnapshot.hasData) {
                  mesajSayisi = mesajSnapshot.data!.where((m) => m['okundu'] == false).length;
                }

                int bildirimSayisi = 0;
                if (sosyalSnapshot.hasData) {
                  bildirimSayisi = sosyalSnapshot.data!.where((b) => b['goruldu'] == false).length;
                }

                int eslesmeSayisi = 0;
                if (eslesmeSnapshot.hasData) {
                  final benzersizBasliklar = eslesmeSnapshot.data!.map((e) => e['kayip_ilan_id'].toString()).toSet();
                  eslesmeSayisi = benzersizBasliklar.length;
                }

                // Ana Ekranda Görünecek Toplam Sayı (Sosyal + Eşleşme)
                int anaEkranToplamBildirim = bildirimSayisi + eslesmeSayisi;

                return _buildBottomNav(context, mesajSayisi, anaEkranToplamBildirim);
              },
            );
          },
        );
      },
    );
  }

  // --- ARAYÜZ OLUŞTURUCU (Tasarım kısmı) ---
  Widget _buildBottomNav(BuildContext context, int mesajSayisi, int anaEkranToplamBildirim) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: gri.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        backgroundColor: beyaz,
        selectedItemColor: turuncuPastel,
        unselectedItemColor: gri,
        selectedLabelStyle: TextStyle(color: turuncuPastel),
        unselectedLabelStyle: TextStyle(color: gri),
        type: BottomNavigationBarType.fixed,
        onTap: (index) => _handleTap(context, index),
        items: [
          BottomNavigationBarItem(
            icon: _buildIconWithBadge(icon: Icons.timeline, count: mesajSayisi, badgeColor: Colors.blue),
            label: 'Akış',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Harita'),
          BottomNavigationBarItem(
            icon: _buildIconWithBadge(
                icon: Icons.home,
                count: anaEkranToplamBildirim,
                badgeColor: const Color(0xFFFFB74D) // Sarı pastel rengimiz
            ),
            label: 'Ana Sayfa',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'İlanlar'),
          const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }

  // Rozet (Badge) Tasarımı
  Widget _buildIconWithBadge({required IconData icon, required int count, required Color badgeColor}) {
    if (count <= 0) return Icon(icon);
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
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            child: Center(
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}