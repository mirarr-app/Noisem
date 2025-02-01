import 'package:flutter/services.dart';
import 'dart:convert';

class LutService {
  static Future<List<Map<String, dynamic>>> loadLuts() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      final lutPaths = manifestMap.keys
          .where((String key) =>
              key.startsWith('assets/cubes/') && key.endsWith('.cube'))
          .toList();

      return lutPaths.map((String path) {
        final pathParts = path.split('/');
        final filename = pathParts.last;
        final category = pathParts[pathParts.length - 2]; // Get the folder name
        final name = filename.split('.').first;
        final prettyName = name
            .split('_')
            .map((word) =>
                word[0].toUpperCase() + word.substring(1).toLowerCase())
            .join(' ');

        return {
          'name': prettyName,
          'file': filename,
          'path': path,
          'category': category,
          'description': 'Film simulation',
        };
      }).toList();
    } catch (e) {
      print('Error loading LUTs: $e');
      return [];
    }
  }
}
