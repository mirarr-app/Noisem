import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class FileUtils {
  static Future<File> copyAssetToTemp(String assetPath, String filename) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/$filename');

    try {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      final byteData = await rootBundle.load(assetPath);
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());

      if (!await tempFile.exists()) {
        throw Exception('Failed to create temporary file: ${tempFile.path}');
      }

      return tempFile;
    } catch (e) {
      rethrow;
    }
  }
}
