class SessionData {
  final String originalImagePath;
  final String? croppedImagePath;
  final String? detectionImagePath;
  final String? segmentationImagePath;

  final List<dynamic>? detectedSymbols;
  final List<dynamic>? pitchMappingResult;
  final List<dynamic>? tablatureResult;
  final List<dynamic>? fretboardEvents;

  final DateTime processingTimestamp;
  final String modelVersion;

  const SessionData({
    required this.originalImagePath,
    this.croppedImagePath,
    this.detectionImagePath,
    this.segmentationImagePath,
    this.detectedSymbols,
    this.pitchMappingResult,
    this.tablatureResult,
    this.fretboardEvents,
    required this.processingTimestamp,
    required this.modelVersion,
  });

  SessionData copyWith({
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
}