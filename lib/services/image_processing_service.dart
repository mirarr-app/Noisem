import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

class ImageProcessingService {
  static Future<void> processImage({
    required String inputImagePath,
    required String lutFilePath,
    required double grainAmount,
    required double pixelateAmount,
    required Function(String) onSuccess,
    required Function(String) onError,
    required Function(bool) setProcessing,
  }) async {
    if (inputImagePath.isEmpty || lutFilePath.isEmpty) return;

    setProcessing(true);

    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath =
          '${tempDir.path}/output_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Verify input file exists
      if (!File(inputImagePath).existsSync()) {
        throw Exception('Input file does not exist: $inputImagePath');
      }

      // Verify LUT file exists
      if (!File(lutFilePath).existsSync()) {
        throw Exception('LUT file does not exist: $lutFilePath');
      }

      // Calculate pixelation scale
      final pixelScale = pixelateAmount > 0
          ? (1 + (pixelateAmount * 150)).toInt()
          : 1; // Scale from 1 to 50

      // Apply LUT and pixelation using FFmpeg
      final lutCommand = '-y -i "$inputImagePath" '
          '-vf "scale=iw/${pixelScale}:-1,scale=iw*${pixelScale}:-1:flags=neighbor,lut3d=$lutFilePath" '
          '"$outputPath"';

      await Posthog().capture(
        eventName: 'applied_lut',
        properties: {
          'lut_file_name': lutFilePath,
          'pixel_scale': pixelScale,
        },
      );

      final session = await FFmpegKit.execute(lutCommand);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        if (grainAmount > 0) {
          // Apply grain effect using the image package
          final bytes = await File(outputPath).readAsBytes();
          var image = img.decodeImage(bytes);

          if (image != null) {
            // Add noise/grain effect
            image = await applyGrainInIsolate(image, grainAmount);

            // Save the processed image
            final processed = img.encodeJpg(image, quality: 100);
            await File(outputPath).writeAsBytes(processed);
          }
        }

        if (!File(outputPath).existsSync()) {
          throw Exception('Output file was not created: $outputPath');
        }
        onSuccess(outputPath);
      } else {
        throw Exception(
            'FFmpeg process failed with return code: ${returnCode?.getValue()}');
      }
    } catch (e) {
      onError(e.toString());
    } finally {
      setProcessing(false);
    }
  }

  static Future<img.Image> applyGrainInIsolate(
      img.Image image, double amount) async {
    // Create message to send to isolate
    final message = {
      'image': image,
      'amount': amount,
    };
    await Posthog().capture(
      eventName: 'image_grain_applied',
    );
    // Run the grain processing in an isolate
    return await compute(_isolateGrainProcessor, message);
  }

  // Static function that runs in the isolate
  static img.Image _isolateGrainProcessor(Map<String, dynamic> message) {
    final image = message['image'] as img.Image;
    final amount = message['amount'] as double;

    final random = Random();
    final intensity = (amount * 100).round();

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);

        // Get RGB channels
        var r = pixel.r.toInt();
        var g = pixel.g.toInt();
        var b = pixel.b.toInt();

        // Add random noise to each channel
        r = (r + (random.nextInt(intensity) - intensity ~/ 2)).clamp(0, 255);
        g = (g + (random.nextInt(intensity) - intensity ~/ 2)).clamp(0, 255);
        b = (b + (random.nextInt(intensity) - intensity ~/ 2)).clamp(0, 255);

        // Set the modified pixel
        image.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }

    return image;
  }

  static Future<Map<String, String>> generatePreview({
    required String sourceImagePath,
    required String lutFilePath,
    required String lutFileName,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final previewPath =
          '${tempDir.path}/preview_${lutFileName}_$timestamp.jpg';

      final command =
          '-y -i "$sourceImagePath" -vf "scale=200:-1,lut3d=$lutFilePath" "$previewPath"';
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        return {lutFileName: previewPath};
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  static Future<Map<String, String>> pickAndProcessImage(
      ImagePicker picker) async {
    try {
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (image != null) {
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final File tempImage =
            File('${tempDir.path}/input_image_$timestamp.jpg');
        await tempImage.writeAsBytes(await image.readAsBytes());

        // Create low-res version for previews
        final previewFile =
            File('${tempDir.path}/preview_source_$timestamp.jpg');
        final command =
            '-y -i "${tempImage.path}" -vf scale=200:-1 "${previewFile.path}"';
        final session = await FFmpegKit.execute(command);
        final returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
          return {
            'selectedImagePath': tempImage.path,
            'previewSourcePath': previewFile.path,
          };
        }
      }
      return {};
    } catch (e) {
      return {};
    }
  }
}
