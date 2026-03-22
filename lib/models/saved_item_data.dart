import 'session_data.dart';

class SavedItemData {
  final String id;
  final String title;
  final String subtitle;
  final String fileType;
  final String createdAt;
  final String? thumbnailPath;
  final String? filePath;
  final bool isPinned;

  const SavedItemData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.fileType,
    required this.createdAt,
    this.thumbnailPath,
    this.filePath,
    this.isPinned = false,
  });

  SavedItemData copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? fileType,
    String? createdAt,
    String? thumbnailPath,
    String? filePath,
    bool? isPinned,
  }) {
    return SavedItemData(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      fileType: fileType ?? this.fileType,
      createdAt: createdAt ?? this.createdAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      filePath: filePath ?? this.filePath,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  factory SavedItemData.fromSession(
      SessionData session, {
        String fileType = '.stala',
        String? filePath,
      }) {
    return SavedItemData(
      id: session.id,
      title: session.projectName,
      subtitle: 'Saved music processing result',
      fileType: fileType,
      createdAt: session.processingTimestamp.toIso8601String(),
      thumbnailPath: session.croppedImagePath ?? session.originalImagePath,
      filePath: filePath,
    );
  }
}