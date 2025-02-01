import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:nes_ui/nes_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'services/image_processing_service.dart';
import 'services/lut_service.dart';
import 'services/permission_service.dart';
import 'services/gallery_service.dart';
import 'utils/file_utils.dart';
import 'services/preview_service.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage>
    with SingleTickerProviderStateMixin {
  String? processedImagePath;
  String? selectedImagePath;
  String? previewSourcePath;
  bool isProcessing = false;
  bool showingOriginal = false;
  final ImagePicker _picker = ImagePicker();
  String? selectedLut;
  List<Map<String, dynamic>> luts = [];
  Map<String, String> lutPreviews = {};
  double previewProgress = 0.0;
  late TabController _tabController;
  final List<String> _categories = [
    'AGFA',
    'FUJI',
    'KODAK',
    'ILFORD',
    'OTHERS'
  ];
  double grainAmount = 0.0;
  double pixelateAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _loadLuts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _generatePreviews() async {
    if (previewSourcePath == null) return;

    setState(() {
      lutPreviews.clear();
      previewProgress = 0.0;
    });

    await PreviewService.generatePreviews(
      previewSourcePath: previewSourcePath!,
      luts: luts,
      onPreviewGenerated: (Map<String, String> preview) {
        setState(() {
          lutPreviews.addAll(preview);
        });
      },
      onProgressUpdate: (double progress) {
        setState(() {
          previewProgress = progress;
        });
      },
    );
  }

  Future<void> _loadLuts() async {
    final loadedLuts = await LutService.loadLuts();
    setState(() {
      luts = loadedLuts;
      if (selectedLut == null && luts.isNotEmpty) {
        selectedLut = luts.first['file'];
      }
    });
  }

  Future<void> pickImage() async {
    try {
      // Clear previous paths before picking new image
      final previousImagePath = selectedImagePath;
      final previousProcessedPath = processedImagePath;

      final result = await ImageProcessingService.pickAndProcessImage(_picker);

      if (result.isNotEmpty) {
        setState(() {
          selectedImagePath = result['selectedImagePath'];
          previewSourcePath = result['previewSourcePath'];
          processedImagePath = null;
          showingOriginal = false;
          lutPreviews.clear();
        });

        // Delete previous files after setting new paths
        if (previousImagePath != null) {
          try {
            await File(previousImagePath).delete();
          } catch (e) {
            throw Exception("Error deleting previous image: $e");
          }
        }
        if (previousProcessedPath != null) {
          try {
            await File(previousProcessedPath).delete();
          } catch (e) {
            throw Exception("Error deleting previous processed image: $e");
          }
        }
        await processImage();

        await _generatePreviews();
        await Posthog().capture(
          eventName: 'image_picked',
        );
      }
    } catch (e) {
      print("Error in pickImage: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to pick image')),
        );
      }
    }
  }

  Future<void> processImage() async {
    if (selectedImagePath == null || selectedLut == null) return;

    try {
      final lutPath =
          luts.firstWhere((lut) => lut['file'] == selectedLut)['path'];
      final lutFile = await FileUtils.copyAssetToTemp(lutPath, selectedLut!);

      await ImageProcessingService.processImage(
        inputImagePath: selectedImagePath!,
        lutFilePath: lutFile.path,
        grainAmount: grainAmount,
        pixelateAmount: pixelateAmount,
        onSuccess: (String outputPath) {
          setState(() {
            processedImagePath = outputPath;
          });
        },
        onError: (String error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error)),
            );
          }
        },
        setProcessing: (bool processing) {
          setState(() {
            isProcessing = processing;
          });
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing image: $e')),
        );
      }
    }
  }

  Future<void> _saveImage() async {
    try {
      if (processedImagePath == null) return;

      final hasPermission = await PermissionService.requestPhotoPermissions();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please grant photos permission to save images'),
              duration: Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: openAppSettings,
              ),
            ),
          );
        }
        return;
      }

      final success = await GalleryService.saveImage(processedImagePath!);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image saved to gallery'),
            duration: Duration(seconds: 2),
          ),
        );
        await Posthog().capture(
          eventName: 'image_saved',
        );
      } else if (mounted) {
        await Posthog().capture(
          eventName: 'image_save_failed',
        );
        throw Exception('Failed to save image to gallery');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save image: $e')),
        );
      }
      await Posthog().capture(
        eventName: 'image_saved_failed',
      );
    }
  }

  List<Map<String, dynamic>> _getFilteredLuts(String category) {
    return luts
        .where((lut) =>
            lut['category'].toString().toLowerCase() == category.toLowerCase())
        .toList();
  }

  Widget _buildLutList(String category) {
    final filteredLuts = _getFilteredLuts(category);

    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filteredLuts.length,
        itemBuilder: (context, index) {
          final lut = filteredLuts[index];
          final isSelected = selectedLut == lut['file'];
          final hasPreview = lutPreviews.containsKey(lut['file']);

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: () async {
                setState(() {
                  selectedLut = lut['file'];
                  processedImagePath = null;
                  isProcessing = true;
                  previewProgress = 0.0;
                });
                await processImage();
              },
              child: Container(
                width: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : Colors.grey[300]!,
                    width: 2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        child: hasPreview
                            ? Image.file(
                                File(lutPreviews[lut['file']]!),
                                fit: BoxFit.cover,
                              )
                            : Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    NesJumpingIconsLoadingIndicator(
                                      icons: [
                                        NesIcons.gallery,
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).primaryColor.withOpacity(0.1)
                            : null,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(6),
                        ),
                      ),
                      child: SizedBox(
                        height: 20,
                        child: Text(
                          lut['name'],
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 7,
                            overflow: TextOverflow.clip,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (processedImagePath != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 0),
              child: NesIconButton(
                icon: NesIcons.saveFile,
                onPress: _saveImage,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 0),
            child: NesIconButton(
              icon: NesIcons.add,
              onPress: pickImage,
            ),
          ),
        ],
      ),
      body: selectedImagePath == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: NesIcon(iconData: NesIcons.gallery),
                  ),
                  const NesRunningText(
                    text: 'No image selected',
                  ),
                  const SizedBox(height: 20),
                  NesButton.iconText(
                      type: NesButtonType.normal,
                      icon: NesIcons.chest,
                      text: 'Select Image',
                      onPressed: pickImage),
                ],
              ),
            )
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: isProcessing
                        ? const Center(child: NesHourglassLoadingIndicator())
                        : processedImagePath != null
                            ? Center(
                                child: GestureDetector(
                                  onLongPressStart: (_) {
                                    setState(() => showingOriginal = true);
                                  },
                                  onLongPressEnd: (_) {
                                    setState(() => showingOriginal = false);
                                  },
                                  child: Stack(
                                    children: [
                                      NesWindow(
                                        title: 'Hold to see original',
                                        child: SizedBox(
                                          width: double.infinity,
                                          height: 450,
                                          child: Image.file(
                                            File(processedImagePath!),
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                      if (showingOriginal)
                                        NesWindow(
                                          title: 'Let go to see edited',
                                          child: SizedBox(
                                            child: SizedBox(
                                              width: double.infinity,
                                              height: 450,
                                              child: Image.file(
                                                File(selectedImagePath!),
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              )
                            : const Center(
                                child: NesHourglassLoadingIndicator()),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      children: [
                        const Text('Pixel:'),
                        Expanded(
                          child: Slider(
                            value: pixelateAmount,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (value) {
                              setState(() {
                                pixelateAmount = value;
                              });
                            },
                            onChangeEnd: (value) {
                              processImage();
                            },
                          ),
                        ),
                        Text('${(pixelateAmount * 100).toInt()}%'),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      children: [
                        const Text('Grain:'),
                        Expanded(
                          child: Slider(
                            value: grainAmount,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (value) {
                              setState(() {
                                grainAmount = value;
                              });
                            },
                            onChangeEnd: (value) {
                              processImage();
                            },
                          ),
                        ),
                        Text('${(grainAmount * 100).toInt()}%'),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          tabs: _categories
                              .map((category) => Tab(text: category))
                              .toList(),
                          labelStyle: const TextStyle(
                              fontSize: 10, fontFamily: 'PressStart2P'),
                        ),
                        SizedBox(
                          height: 120,
                          child: TabBarView(
                            controller: _tabController,
                            children: _categories
                                .map((category) => _buildLutList(category))
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
