import 'dart:io';

import 'session_data.dart';

class SavedItemData {
  final String id;
  final String title;
  final String subtitle;
  final String fileType;
  final String createdAt;
  final String modifiedAt;
  final String? thumbnailPath;
  final String filePath;
  final bool isPinned;

  const SavedItemData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.fileType,
    required this.createdAt,
    required this.modifiedAt,
    required this.filePath,
    this.thumbnailPath,
    this.isPinned = false,
  });

  SavedItemData copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? fileType,
    String? createdAt,
    String? modifiedAt,
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
      modifiedAt: modifiedAt ?? this.modifiedAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      filePath: filePath ?? this.filePath,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  factory SavedItemData.fromSession(
      SessionData session, {
        required String filePath,
        String fileType = '.stala',
        DateTime? modifiedAt,
      }) {
    return SavedItemData(
      id: session.id,
      title: session.projectName,
      subtitle: 'Saved music processing result',
      fileType: fileType,
      createdAt: session.processingTimestamp.toIso8601String(),
      modifiedAt: (modifiedAt ?? DateTime.now()).toIso8601String(),
      thumbnailPath: session.croppedImagePath ?? session.originalImagePath,
      filePath: filePath,
    );
  }

  factory SavedItemData.fromFile({
    required File file,
    required SessionData session,
  }) {
    return SavedItemData.fromSession(
      session,
      filePath: file.path,
      fileType: '.stala',
      modifiedAt: file.lastModifiedSync(),
    );
  }
}