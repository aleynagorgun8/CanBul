import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TutorialYardimcisi {
  
  static Future<void> egitimiGoster({
    required BuildContext context,
    required List<TargetFocus> hedefler,
    required String sayfaAnahtari, 
    bool zorlaGoster = false,      
    bool kaydetTamamlandi = true,
    bool skipGoster = true,
    VoidCallback? onFinish,
    VoidCallback? onSkip,
  }) async {
    
    SharedPreferences prefs = await SharedPreferences.getInstance();

    
    bool gorulduMu = prefs.getBool(sayfaAnahtari) ?? false;

    
    if (!gorulduMu || zorlaGoster) {
      TutorialCoachMark(
        targets: hedefler,
        colorShadow: const Color(0xFF002D72), 
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
          return true; 
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