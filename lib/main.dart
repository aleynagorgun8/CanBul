import 'package:flutter/material.dart'; //flutterın arayüz bileşenleri için
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; //ikonlar için
import 'package:supabase_flutter/supabase_flutter.dart'; //supabase import
import 'giris_kayit.dart'; // giriş/kayıt ekranı import
import 'ana_ekran.dart'; // Giriş yapıldıysa yönlendirilecek ekran

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
          background: const Color(0xFFF1F8E9),
          surface: Colors.white,
          onSurface: const Color(0xFF558B2F),
        ),
        useMaterial3: true,   //butonlar kartlar gölgeler vb daha yumuşan görünsün diye modern arayüz
        fontFamily: 'Poppins',
      ),
      home: const SplashScreen(),   //uygulama açıldığında ilk gösterilecek ekran
    );
  }
}

// Splash Screen
class SplashScreen extends StatefulWidget {  //zamanla değişecek bir ekran olduğu için statefulWidget
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;   //büyüme küçülme animasyonu
  late AnimationController _fadeController;  //opaklık animasyonu için
  late AnimationController _pulseController; //logonun büyüyüp küçülmesi için nabız benzeri büyüyüp küçülme
  late Animation<double> _scaleAnimation;  //logonun o anda ne kadar büyüdüğünü gösterecek
  late Animation<double> _fadeAnimation;  //opaklık seviyesini gösterir
  late Animation<double> _pulseAnimation; //nabız efekti için dinamik büyüklük değeridir

  @override
  void initState() {
    super.initState();

    // Logo büyüme animasyonu
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),  //animasyon 2 saniye sürecek
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOut,  //yavaş başlar, ortada hızlanır, sonra tekrar yavaşlar
    );

    // Nabız atışı animasyonu
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // Yazı animasyonu
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    // Animasyonları sırayla başlat
    _startAnimations();
  }

  void _startAnimations() async {
    await _scaleController.forward();

    // Logo büyüdükten sonra nabız atışı başlasın
    _pulseController.repeat(reverse: true);   //İlk olarak logo yavaşça büyüsün, diğerleri beklesin

    // Yazı animasyonu başlasın
    await _fadeController.forward();

    // 2 saniye daha göster ve geçiş yap
    await Future.delayed(const Duration(seconds: 2));



    // Hedef sayfayı belirle
    Widget hedefSayfa;

    // Supabase'de kayıtlı bir oturum var mı kontrol et
    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      // Oturum varsa, kullanıcı bilgilerini al (AnaEkran isim istiyor)
      final user = Supabase.instance.client.auth.currentUser;
      String kullaniciAdi = user?.userMetadata?['tam_ad'] ?? 'Kullanıcı';

      // Ana Ekrana yönlendir
      hedefSayfa = AnaEkran(kullaniciAdi: kullaniciAdi);
    } else {
      // Oturum yoksa Giriş/Kayıt ekranına yönlendir
      hedefSayfa = const GirisKayitSayfasi();
    }

    if (mounted) {
      Navigator.pushReplacement(   //mevcut splash sayfasını kaldırıp hedef sayfaya gideceğiz
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
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  @override
  void dispose() {  //sayfa kapatılırken bellekte açık kalabilecek animasyonları kapamak için kullandık RAM gereksiz kullanılmasın diye
    _scaleController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color turuncuPastel = const Color(0xFFFFB74D);  //pastel turuncu ve yeşil renkler
    final Color yesilPastel = const Color(0xFF558B2F);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF1F8E9),
              Color(0xFFE8F5E8),
              Color(0xFFDCEDC8),
            ],
          ),
        ),
        child: Center(     //öğeler ekrana dikey eksende ortalanıyor
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Ana logo container'ı
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: yesilPastel.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Arka plan halkası
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: turuncuPastel.withOpacity(0.3),
                            width: 3,
                          ),
                        ),
                      ),
                    ),

                    // Ana logo
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                turuncuPastel,
                                turuncuPastel.withOpacity(0.8),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: turuncuPastel.withOpacity(0.4),
                                blurRadius: 15,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            FontAwesomeIcons.paw,
                            size: 50,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Uygulama adı
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    Text(
                      "CanBul",
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: yesilPastel,
                        letterSpacing: 1.5,
                        fontFamily: 'Poppins',
                        shadows: [
                          Shadow(
                            blurRadius: 10,
                            color: yesilPastel.withOpacity(0.2),
                            offset: const Offset(2, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Text(
                        "Her şey evcil dostlarımız için",
                        style: TextStyle(
                          fontSize: 14,
                          color: yesilPastel.withOpacity(0.8),
                          fontStyle: FontStyle.italic,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),

              // Yükleniyor göstergesi
              const SizedBox(height: 50),
              FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(yesilPastel),
                    strokeWidth: 3,
                    backgroundColor: yesilPastel.withOpacity(0.2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}