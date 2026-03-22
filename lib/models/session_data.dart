class SessionData {
  final String id;
  final String projectName;

  final String originalImagePath;
  final String? croppedImagePath;
  final String? detectionImagePath;
  final String? segmentationImagePath;

  final List<dynamic> detectedSymbols;
  final List<dynamic> pitchMappingResult;
  final List<dynamic> tablatureResult;
  final List<dynamic> fretboardEvents;

  final DateTime processingTimestamp;
  final String modelVersion;

  const SessionData({
    required this.id,
    required this.projectName,
    required this.originalImagePath,
    this.croppedImagePath,
    this.detectionImagePath,
    this.segmentationImagePath,
    this.detectedSymbols = const [],
    this.pitchMappingResult = const [],
    this.tablatureResult = const [],
    this.fretboardEvents = const [],
    required this.processingTimestamp,
    required this.modelVersion,
  });

  SessionData copyWith({
    String? id,
    String? projectName,
    String? originalImagePath,
    String? croppedImagePath,
    String? detectionImagePath,
    String? segmentationImagePath,
    List<dynamic>? detectedSymbols,
    List<dynamic>? pitchMappingResult,
    List<dynamic>? tablatureResult,
    List<dynamic>? fretboardEvents,
    DateTime? processingTimestamp,
    String? modelVersion,
  }) {
    return SessionData(
      id: id ?? this.id,
      projectName: projectName ?? this.projectName,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      croppedImagePath: croppedImagePath ?? this.croppedImagePath,
      detectionImagePath: detectionImagePath ?? this.detectionImagePath,
      segmentationImagePath: segmentationImagePath ?? this.segmentationImagePath,
      detectedSymbols: detectedSymbols ?? this.detectedSymbols,
      pitchMappingResult: pitchMappingResult ?? this.pitchMappingResult,
      tablatureResult: tablatureResult ?? this.tablatureResult,
      fretboardEvents: fretboardEvents ?? this.fretboardEvents,
      processingTimestamp: processingTimestamp ?? this.processingTimestamp,
      modelVersion: modelVersion ?? this.modelVersion,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'project_name': projectName,
      'original_image_path': originalImagePath,
      'cropped_image_path': croppedImagePath,
      'detection_image_path': detectionImagePath,
      'segmentation_image_path': segmentationImagePath,
      'detected_symbols': detectedSymbols,
      'pitch_mapping_result': pitchMappingResult,
      'tablature_result': tablatureResult,
      'fretboard_events': fretboardEvents,
      'processing_timestamp': processingTimestamp.toIso8601String(),
      'model_version': modelVersion,
    };
  }

  factory SessionData.fromJson(Map<String, dynamic> json) {
    return SessionData(
      id: json['id'] as String,
      projectName: json['project_name'] as String,
      originalImagePath: json['original_image_path'] as String,
      croppedImagePath: json['cropped_image_path'] as String?,
      detectionImagePath: json['detection_image_path'] as String?,
      segmentationImagePath: json['segmentation_image_path'] as String?,
      detectedSymbols: List<dynamic>.from(json['detected_symbols'] ?? const []),
      pitchMappingResult: List<dynamic>.from(json['pitch_mapping_result'] ?? const []),
      tablatureResult: List<dynamic>.from(json['tablature_result'] ?? const []),
      fretboardEvents: List<dynamic>.from(json['fretboard_events'] ?? const []),
      processingTimestamp: DateTime.parse(json['processing_timestamp'] as String),
      modelVersion: json['model_version'] as String,
    );
  }
}