import 'dart:io';
import 'dart:math';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img; 

class YapayZekaServisi {
  
  static final YapayZekaServisi _nesne = YapayZekaServisi._dahili();
  factory YapayZekaServisi() => _nesne;
  YapayZekaServisi._dahili();

  Interpreter? _yoloYorumlayici;
  Interpreter? _resnetYorumlayici;

  
  Future<bool> modelleriBaslat() async {
    try {
      _yoloYorumlayici = await Interpreter.fromAsset('assets/yolov8n_float16.tflite');
      _resnetYorumlayici = await Interpreter.fromAsset('assets/resnet50_feature_extractor.tflite');
      print("✅ Modeller başarıyla yüklendi!");
      return true;
    } catch (e) {
      print("❌ Modeller yüklenirken hata: $e");
      return false;
    }
  }

  
  Future<List<double>> fotografiVektoreDonustur(File dosya) async {
    try {
      if (_resnetYorumlayici == null) await modelleriBaslat();

      final baytlar = await dosya.readAsBytes();
      final hamResim = img.decodeImage(baytlar);
      if (hamResim == null) return [];

      
      final yeniResim = img.copyResize(hamResim, width: 224, height: 224);

      
      var girdi = List.generate(1, (i) => List.generate(224, (j) => List.generate(224, (k) => List.filled(3, 0.0))));

      
      for (var y = 0; y < 224; y++) {
        for (var x = 0; x < 224; x++) {
          final piksel = yeniResim.getPixel(x, y);
          
          
          girdi[0][y][x][0] = (piksel.r - 123.68);
          girdi[0][y][x][1] = (piksel.g - 116.779);
          girdi[0][y][x][2] = (piksel.b - 103.939);
        }
      }


      var modelCiktisi = List<double>.filled(2048, 0).reshape([1, 2048]);
      _resnetYorumlayici!.run(girdi, modelCiktisi);

      List<double> hamVektor = List<double>.from(modelCiktisi[0]);

      
      return [...hamVektor, ...hamVektor];
    } catch (e) {
      print("❌ Saf Vektör Hatası: $e");
      return [];
    }
  }  double kosinusBenzerligiHesapla(List<double> vektorA, List<double> vektorB) {
    if (vektorA.length != vektorB.length) return 0.0;

    double noktaCarpim = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < vektorA.length; i++) {
      noktaCarpim += vektorA[i] * vektorB[i];
      normA += vektorA[i] * vektorA[i];
      normB += vektorB[i] * vektorB[i];
    }

    
    double payda = sqrt(normA) * sqrt(normB);

    if (payda < 1e-10) return 0.0; 

    return noktaCarpim / payda;
  }}