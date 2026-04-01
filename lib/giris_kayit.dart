import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ana_ekran.dart';

class GirisKayitSayfasi extends StatefulWidget {
  const GirisKayitSayfasi({super.key});

  @override
  State<GirisKayitSayfasi> createState() => _GirisKayitSayfasiState();
}

class _GirisKayitSayfasiState extends State<GirisKayitSayfasi> {
  @override
  void initState() {
    super.initState();

    _supabase.auth.onAuthStateChange.listen((data) {
      final session = data.session;


      if (session != null && mounted) {


        String kAdi = session.user.userMetadata?['tam_ad'] ?? 'Kullanıcı';


        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => AnaEkran(kullaniciAdi: kAdi)),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Giriş yapıldı!")),
        );
      }
    });
  }
  bool showSignUp = false;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _adController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _sifreController = TextEditingController();
  final TextEditingController _sifreTekrarController = TextEditingController();
  final TextEditingController _telefonController = TextEditingController();

  final Color turuncuPastel = const Color(0xFFFFB74D);
  final Color zeytinYesili = const Color(0xFF558B2F);
  final Color arkaPlan = const Color(0xFFF1F8E9);
  final Color beyaz = Colors.white;
  final Color gri = const Color(0xFF9E9E9E);

  final SupabaseClient _supabase = Supabase.instance.client;



  Future<void> _kayitOl() async {
    final ad = _adController.text.trim();
    final email = _emailController.text.trim();
    final sifre = _sifreController.text.trim();
    final sifreTekrar = _sifreTekrarController.text.trim();
    final telefon = _telefonController.text.trim();

    if (ad.isEmpty || email.isEmpty || sifre.isEmpty || sifreTekrar.isEmpty || telefon.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Lütfen tüm alanları doldurun"),
          backgroundColor: zeytinYesili,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (sifre != sifreTekrar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Şifreler eşleşmiyor"),
          backgroundColor: zeytinYesili,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {


      final response = await _supabase.auth.signUp(
        email: email,
        password: sifre,
        data: {
          'tam_ad': ad,
          'telefon': telefon,
        },
        emailRedirectTo: 'canbulMailDogrulama://login-callback/',
      );


      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Kayıt işleminizi tamamlamak için lütfen ${email} adresinize gönderilen doğrulama linkine tıklayın. Linke tıkladıktan sonra uygulamaya geri dönerek giriş yapabilirsiniz."),
          backgroundColor: turuncuPastel,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (mounted) {
        setState(() {
          showSignUp = false;
          _emailController.text = email;
          _sifreController.clear();
          _sifreTekrarController.clear();
        });
      }

    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Kayıt hatası: ${e.message}"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Bir hata oluştu: $e"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }



  Future<void> _girisYap() async {
    final email = _emailController.text.trim();
    final sifre = _sifreController.text.trim();

    if (email.isEmpty || sifre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Lütfen e-posta ve şifrenizi girin"),
          backgroundColor: zeytinYesili,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: sifre,
      );

      if (response.user != null) {
        final user = response.user!;
        String ad = "Kullanıcı";


        if (user.emailConfirmedAt == null) {

          await _supabase.auth.signOut();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Giriş Başarısız: E-posta adresiniz doğrulanmadı. Lütfen mail kutunuzu kontrol edin ve linke tıklayın."),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }




        var userData = await _supabase
            .from('profiles')
            .select('tam_ad')
            .eq('id', user.id)
            .maybeSingle();

        if (userData == null) {

          final metadata = user.userMetadata;

          final profilVerisi = {
            'id': user.id,
            'tam_ad': metadata?['tam_ad'] ?? 'Bilinmiyor',
            'email': user.email,
            'telefon': metadata?['telefon'] ?? '',
          };

          await _supabase.from('profiles').insert(profilVerisi);
          ad = metadata?['tam_ad'] ?? "Kullanıcı";
        } else {

          ad = userData['tam_ad'] ?? "Kullanıcı";
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Giriş başarılı! 🐾"),
            backgroundColor: zeytinYesili,
            behavior: SnackBarBehavior.floating,
          ),
        );

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => AnaEkran(kullaniciAdi: ad),
            ),
          );
        }
      }
    } on AuthException catch (e) {

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Giriş hatası: ${e.message}"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Bir hata oluştu: $e"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: arkaPlan,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              const SizedBox(height: 10),


              CircleAvatar(
                radius: 30,
                backgroundColor: turuncuPastel,
                child: FaIcon(
                  FontAwesomeIcons.paw,
                  size: 30,
                  color: beyaz,
                ),
              ),
              const SizedBox(height: 15),


              Text(
                showSignUp ? 'Hesap Oluştur' : 'Hoş Geldiniz',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: zeytinYesili,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                showSignUp
                    ? 'Kayıp dostları bulmaya başlayalım!'
                    : 'Hesabınıza giriş yapın',
                style: TextStyle(
                  fontSize: 14,
                  color: gri,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),


              Container(
                decoration: BoxDecoration(
                  color: beyaz,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: gri.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [

                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            showSignUp = true;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: showSignUp ? turuncuPastel : beyaz,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(15),
                              bottomLeft: Radius.circular(15),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.person_add,
                                color: showSignUp ? beyaz : gri,
                                size: 20,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Hesap Oluştur',
                                style: TextStyle(
                                  color: showSignUp ? beyaz : zeytinYesili,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),


                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            showSignUp = false;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: !showSignUp ? turuncuPastel : beyaz,
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(15),
                              bottomRight: Radius.circular(15),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.login,
                                color: !showSignUp ? beyaz : gri,
                                size: 20,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Giriş Yap',
                                style: TextStyle(
                                  color: !showSignUp ? beyaz : zeytinYesili,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),


              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: beyaz,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: gri.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      if (showSignUp)
                        _buildTextField(
                          controller: _adController,
                          label: 'Tam Adınız',
                          icon: Icons.person,
                        ),
                      if (showSignUp) const SizedBox(height: 12),


                      if (showSignUp)
                        _buildTextField(
                          controller: _telefonController,
                          label: 'Telefon Numarası',
                          icon: Icons.phone,
                          keyboardType: TextInputType.phone,
                          hintText: '0 (5XX) XXX XX XX',
                        ),
                      if (showSignUp) const SizedBox(height: 12),

                      _buildTextField(
                        controller: _emailController,
                        label: 'E-posta',
                        icon: Icons.email,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),

                      _buildTextField(
                        controller: _sifreController,
                        label: 'Şifre',
                        icon: Icons.lock,
                        obscureText: true,
                      ),
                      if (showSignUp) const SizedBox(height: 12),

                      if (showSignUp)
                        _buildTextField(
                          controller: _sifreTekrarController,
                          label: 'Şifre Tekrar',
                          icon: Icons.lock_outline,
                          obscureText: true,
                        ),

                      const SizedBox(height: 20),


                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: turuncuPastel,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          onPressed: showSignUp ? _kayitOl : _girisYap,
                          child: Text(
                            showSignUp ? 'Hesap Oluştur' : 'Giriş Yap',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),


                      TextButton(
                        onPressed: () {
                          setState(() {
                            showSignUp = !showSignUp;
                          });
                        },
                        child: RichText(
                          text: TextSpan(
                            text: showSignUp
                                ? 'Zaten hesabınız var mı? '
                                : 'Hesabınız yok mu? ',
                            style: TextStyle(color: gri, fontSize: 13),
                            children: [
                              TextSpan(
                                text: showSignUp ? 'Giriş Yap' : 'Hesap Oluştur',
                                style: TextStyle(
                                  color: zeytinYesili,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(
                height: showSignUp ? 5 : 190,
              ),

              Container(
                height: showSignUp ? 170 : 160,
                width: double.infinity,
                margin: EdgeInsets.only(
                  bottom: showSignUp ? 0 : 30,
                ),
                child: Image.asset(
                  showSignUp
                      ? 'assets/images/dog.png'
                      : 'assets/images/cat.png',
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    String? hintText,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: zeytinYesili, fontSize: 14),
        hintText: hintText,
        hintStyle: TextStyle(fontSize: 12, color: gri),
        prefixIcon: Icon(icon, color: turuncuPastel, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: gri.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: turuncuPastel, width: 1.5),
        ),
        filled: true,
        fillColor: arkaPlan,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      style: const TextStyle(fontSize: 14),
    );
  }
}
