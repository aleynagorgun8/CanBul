import 'package:flutter/material.dart'; //flutterın arayüz bileşenleri için
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; //ikonlar için
import 'package:supabase_flutter/supabase_flutter.dart'; //supabase import
import 'giris_kayit.dart'; // giriş/kayıt ekranı import
import 'ana_ekran.dart'; // Giriş yapıldıysa yönlendirilecek ekran
import 'yapay_zeka_servisi.dart';

void main() async {    //uygulama buradan başlıyor
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(           //  Supabase bağlantısı
    url: 'https://rhlsacfixmnsdcfnchul.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJobHNhY2ZpeG1uc2RjZm5jaHVsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkzNDE0MzAsImV4cCI6MjA3NDkxNzQzMH0.5yCDlFL9er14Z5ZW7WgsaKrpd9o3At1_gbOMd9r0kd8',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {  //açılış sayfanın başlangıcı
    return MaterialApp(
      title: 'CanBul - Evcil Hayvan Buluşma Platformu',
      debugShowCheckedModeBanner: false,  //debug yazısını gizlemek için
      theme: ThemeData(   //renk paketini yazı fontunu vb belirliyoruz
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,  //genel tema yeşil tonlarda olacak
          primary: const Color(0xFF558B2F),
          secondary: const Color(0xFFFFB74D),
          surface: Colors.white,
        ),
        useMaterial3: true,   //modern arayüz
        fontFamily: 'Poppins',
      ),
      home: const SplashScreen(),   //uygulama açıldığında ilk gösterilecek ekran
    );
  }
}

// Splash Screen
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() { // DOĞRU KULLANIM: initState async olamaz, void dönmelidir.
    super.initState();

    // 1. Animasyon controller'ları
    _scaleController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _scaleAnimation = CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut);

    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _fadeController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);

    // 2. Animasyon akışını başlatan fonksiyonu tetikliyoruz
    _startAnimations();
  }

  // Animasyonların ve Model yüklemenin yapıldığı ana fonksiyon
  void _startAnimations() async {
    try {
      print("🚀 Animasyonlar başlıyor...");

      // 1. Logo büyüme animasyonunu başlat ve bitmesini bekle
      await _scaleController.forward();
      _pulseController.repeat(reverse: true);

      // 2. Yapay Zeka Modellerini Yükle
      print("🧠 [Yapay Zeka] Modeller yüklenmeye başlıyor...");
      try {
        YapayZekaServisi aiServisi = YapayZekaServisi();
        await aiServisi.modelleriBaslat();
        print("💡 [TEST SONUCU]: BAŞARILI! Modeller RAM'e alındı. 💛💙");
      } catch (aiError) {
        print("🚨 [Yapay Zeka Hatası]: $aiError");
      }

      // 3. Modeller yüklendikten sonra yazı animasyonunu başlat
      await _fadeController.forward();

      // Kısa bir bekleme (Görsellik için)
      await Future.delayed(const Duration(seconds: 1));

      // 4. Sayfa Yönlendirme Mantığı
      if (!mounted) return;

      Widget hedefSayfa;
      final session = Supabase.instance.client.auth.currentSession;

      if (session != null) {
        final user = Supabase.instance.client.auth.currentUser;
        String kullaniciAdi = user?.userMetadata?['tam_ad'] ?? 'Kullanıcı';
        hedefSayfa = AnaEkran(kullaniciAdi: kullaniciAdi);
      } else {
        hedefSayfa = const GirisKayitSayfasi();
      }

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => hedefSayfa,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOut;
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            var offsetAnimation = animation.drive(tween);
            return SlideTransition(
              position: offsetAnimation,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    } catch (e) {
      print("🚨 Genel bir hata oluştu: $e");
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color turuncuPastel = Color(0xFFFFB74D);
    const Color yesilPastel = Color(0xFF558B2F);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF1F8E9), Color(0xFFE8F5E8), Color(0xFFDCEDC8)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: yesilPastel.withOpacity(0.2), blurRadius: 20, spreadRadius: 5)],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        width: 140, height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: turuncuPastel.withOpacity(0.3), width: 3),
                        ),
                      ),
                    ),
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: Container(
                          width: 120, height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [turuncuPastel, turuncuPastel.withOpacity(0.8)],
                            ),
                            boxShadow: [BoxShadow(color: turuncuPastel.withOpacity(0.4), blurRadius: 15, spreadRadius: 2)],
                          ),
                          child: const Icon(FontAwesomeIcons.paw, size: 50, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    Text(
                      "CanBul",
                      style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: yesilPastel, letterSpacing: 1.5, fontFamily: 'Poppins'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Her şey evcil dostlarımız için",
                      style: TextStyle(fontSize: 14, color: yesilPastel.withOpacity(0.8), fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 50),
              FadeTransition(
                opacity: _fadeAnimation,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(yesilPastel),
                  strokeWidth: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}