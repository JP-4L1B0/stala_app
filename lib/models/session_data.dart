import 'tablature_result.dart';

class SessionData {
  final String id;
  final String projectName;

  // Images
  final String originalImagePath;
  final String? croppedImagePath;
  final String? preprocessedImagePath;
  final String? detectionImagePath;
  final String? segmentationImagePath;

  // Optional pipeline snapshot
  final List<Map<String, dynamic>> detectedSymbols;
  final List<Map<String, dynamic>> segmentationData;
  final List<Map<String, dynamic>> pitchMappingData;
  final List<Map<String, dynamic>> fretboardEvents;

  // Final source-of-truth result
  final List<TablatureResult> tablatureResults;

  // Metadata
  final DateTime processingTimestamp;
  final String modelVersion;
  final bool hasPipelineSnapshot;

  // Auto-save
  final String? autoSavedFilePath;
  final DateTime? autoSavedAt;
  final bool autoSaveFailed;

  const SessionData({
    required this.id,
    required this.projectName,
    required this.originalImagePath,
    this.croppedImagePath,
    this.preprocessedImagePath,
    this.detectionImagePath,
    this.segmentationImagePath,
    this.detectedSymbols = const [],
    this.segmentationData = const [],
    this.pitchMappingData = const [],
    this.fretboardEvents = const [],
    this.tablatureResults = const [],
    required this.processingTimestamp,
    required this.modelVersion,
    this.hasPipelineSnapshot = false,
    this.autoSavedFilePath,
    this.autoSavedAt,
    this.autoSaveFailed = false,
  });

  SessionData copyWith({
    String? id,
    String? projectName,
    String? originalImagePath,
    String? croppedImagePath,
    String? preprocessedImagePath,
    String? detectionImagePath,
    String? segmentationImagePath,
    List<Map<String, dynamic>>? detectedSymbols,
    List<Map<String, dynamic>>? segmentationData,
    List<Map<String, dynamic>>? pitchMappingData,
    List<Map<String, dynamic>>? fretboardEvents,
    List<TablatureResult>? tablatureResults,
    DateTime? processingTimestamp,
    String? modelVersion,
    bool? hasPipelineSnapshot,
    String? autoSavedFilePath,
    DateTime? autoSavedAt,
    bool? autoSaveFailed,
  }) {
    return SessionData(
      id: id ?? this.id,
      projectName: projectName ?? this.projectName,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      croppedImagePath: croppedImagePath ?? this.croppedImagePath,
      preprocessedImagePath:
          preprocessedImagePath ?? this.preprocessedImagePath,
      detectionImagePath: detectionImagePath ?? this.detectionImagePath,
      segmentationImagePath:
          segmentationImagePath ?? this.segmentationImagePath,
      detectedSymbols: detectedSymbols ?? this.detectedSymbols,
      segmentationData: segmentationData ?? this.segmentationData,
      pitchMappingData: pitchMappingData ?? this.pitchMappingData,
      fretboardEvents: fretboardEvents ?? this.fretboardEvents,
      tablatureResults: tablatureResults ?? this.tablatureResults,
      processingTimestamp: processingTimestamp ?? this.processingTimestamp,
      modelVersion: modelVersion ?? this.modelVersion,
      hasPipelineSnapshot: hasPipelineSnapshot ?? this.hasPipelineSnapshot,
      autoSavedFilePath: autoSavedFilePath ?? this.autoSavedFilePath,
      autoSavedAt: autoSavedAt ?? this.autoSavedAt,
      autoSaveFailed: autoSaveFailed ?? this.autoSaveFailed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'project_name': projectName,
      'original_image_path': originalImagePath,
      'cropped_image_path': croppedImagePath,
      'preprocessed_image_path': preprocessedImagePath,
      'detection_image_path': detectionImagePath,
      'segmentation_image_path': segmentationImagePath,

      'detected_symbols': detectedSymbols,
      'segmentation_data': segmentationData,
      'pitch_mapping_data': pitchMappingData,
      'fretboard_events': fretboardEvents,

      'tablature_results': tablatureResults.map((r) => r.toJson()).toList(),

      'processing_timestamp': processingTimestamp.toIso8601String(),
      'model_version': modelVersion,
      'has_pipeline_snapshot': hasPipelineSnapshot,

      'auto_saved_file_path': autoSavedFilePath,
      'auto_saved_at': autoSavedAt?.toIso8601String(),
      'auto_save_failed': autoSaveFailed,
    };
  }

  factory SessionData.fromJson(Map<String, dynamic> json) {
    return SessionData(
      id: json['id']?.toString() ?? '',
      projectName: json['project_name']?.toString() ?? 'Untitled',
      originalImagePath: json['original_image_path']?.toString() ?? '',
      croppedImagePath: json['cropped_image_path']?.toString(),
      preprocessedImagePath: json['preprocessed_image_path']?.toString(),
      detectionImagePath: json['detection_image_path']?.toString(),
      segmentationImagePath: json['segmentation_image_path']?.toString(),

      detectedSymbols: _mapList(json['detected_symbols']),
      segmentationData: _mapList(json['segmentation_data']),
      pitchMappingData: _mapList(json['pitch_mapping_data']),
      fretboardEvents: _mapList(json['fretboard_events']),

      tablatureResults: (json['tablature_results'] as List? ?? const []).map((
        item,
      ) {
        return TablatureResult.fromJson(Map<String, dynamic>.from(item as Map));
      }).toList(),

      processingTimestamp:
          DateTime.tryParse(json['processing_timestamp']?.toString() ?? '') ??
          DateTime.now(),

      modelVersion: json['model_version']?.toString() ?? 'unknown',
      hasPipelineSnapshot: json['has_pipeline_snapshot'] == true,

      autoSavedFilePath: json['auto_saved_file_path']?.toString(),
      autoSavedAt: DateTime.tryParse(json['auto_saved_at']?.toString() ?? ''),
      autoSaveFailed: json['auto_save_failed'] == true,
    );
  }

  static List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}
