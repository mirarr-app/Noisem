import 'dart:io';
import 'package:image_gallery_saver/image_gallery_saver.dart';

class GalleryService {
  static Future<bool> saveImage(String imagePath) async {
    try {
      final imageBytes = await File(imagePath).readAsBytes();
      final result = await ImageGallerySaver.saveImage(
        imageBytes,
        quality: 100,
        name: "LUT_image_${DateTime.now().millisecondsSinceEpoch}",
      );
      return result['isSuccess'] ?? false;
    } catch (e) {
      return false;
    }
  }
}
