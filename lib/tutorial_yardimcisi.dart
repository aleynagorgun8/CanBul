import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TutorialYardimcisi {
  /// Bu fonksiyon, eğitimi sadece ilk girişte veya butona özel olarak basıldığında gösterir.
  static Future<void> egitimiGoster({
    required BuildContext context,
    required List<TargetFocus> hedefler,
    required String sayfaAnahtari, // Hangi sayfanın eğitimi olduğunu anlamak için benzersiz bir isim
    bool zorlaGoster = false,      // Kullanıcı "bilgi" butonuna bastığında true göndereceğiz
    bool kaydetTamamlandi = true,
    bool skipGoster = true,
    VoidCallback? onFinish,
    VoidCallback? onSkip,
  }) async {
    // 1. Cihaz hafızasına (RAM) bağlan
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // 2. Bu sayfanın eğitimi daha önce gösterilmiş mi kontrol et
    bool gorulduMu = prefs.getBool(sayfaAnahtari) ?? false;

    // 3. Eğer daha önce görülmediyse VEYA kullanıcı butona bilerek bastıysa eğitimi başlat
    if (!gorulduMu || zorlaGoster) {
      TutorialCoachMark(
        targets: hedefler,
        colorShadow: const Color(0xFF002D72), // Temaya uygun Lacivert Karartma 💛💙
        textSkip: "GEÇ",
        alignSkip: Alignment.topLeft,
        hideSkip: !skipGoster,
        paddingFocus: 10,
        opacityShadow: 0.85,
        textStyleSkip: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
        // --- DÜZELTİLEN KISIM: async ve await kaldırıldı --- ✅
        onFinish: () {
          if (kaydetTamamlandi) {
            prefs.setBool(sayfaAnahtari, true);
          }
          debugPrint("✅ $sayfaAnahtari eğitimi tamamlandı ve kaydedildi.");
          onFinish?.call();
        },
        onSkip: () {
          if (kaydetTamamlandi) {
            prefs.setBool(sayfaAnahtari, true);
          }
          debugPrint("⏭️ $sayfaAnahtari eğitimi atlandı ve kaydedildi.");
          onSkip?.call();
          return true; // Paketin tam olarak beklediği anlık true değeri!
        },
      ).show(context: context);
    }
  }

  static Future<void> egitimHafizasiniSifirla(String sayfaAnahtari) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(sayfaAnahtari);
    debugPrint("🔄 $sayfaAnahtari eğitim hafızası sıfırlandı.");
  }
}