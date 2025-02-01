import '../utils/file_utils.dart';
import 'image_processing_service.dart';

class PreviewService {
  static Future<Map<String, String>> generatePreviews({
    required String previewSourcePath,
    required List<Map<String, dynamic>> luts,
    required Function(Map<String, String>) onPreviewGenerated,
    required Function(double) onProgressUpdate,
  }) async {
    Map<String, String> allPreviews = {};
    const int batchSize = 3; // Process 3 LUTs at a time

    for (var i = 0; i < luts.length; i += batchSize) {
      final batch = luts.skip(i).take(batchSize);
      final futures = batch.map((lut) async {
        try {
          final lutFile =
              await FileUtils.copyAssetToTemp(lut['path'], lut['file']);
          final preview = await ImageProcessingService.generatePreview(
            sourceImagePath: previewSourcePath,
            lutFilePath: lutFile.path,
            lutFileName: lut['file'],
          );

          allPreviews.addAll(preview);
          onPreviewGenerated(preview);
        } catch (e) {
          throw Exception("Error generating preview for ${lut['file']}: $e");
        }
      });

      await Future.wait(futures);

      // Update progress
      final progress = (i + batchSize) / luts.length;
      onProgressUpdate(progress > 1.0 ? 1.0 : progress);
    }

    return allPreviews;
  }
}
