import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/saved_item_data.dart';
import '../models/session_data.dart';
import '../services/storage_access_service.dart';

class RecentItemsRepository {
  RecentItemsRepository._();

  static const StorageAccessService _storageAccessService =
      StorageAccessService();

  static Future<Directory> _savedDirectory() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final savedDir = Directory('${baseDir.path}/Stala/saved');

    if (!await savedDir.exists()) {
      await savedDir.create(recursive: true);
    }

    return savedDir;
  }

  static Future<List<SavedItemData>> getRecentItems() async {
    final storage = await _storageAccessService.getStorageFolder();
    if (storage.granted) {
      return _getSafRecentItems();
    }

    final directory = await _savedDirectory();

    if (!await directory.exists()) {
      return const [];
    }

    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.stala'))
        .toList();

    files.sort((a, b) {
      return b.lastModifiedSync().compareTo(a.lastModifiedSync());
    });

    final items = <SavedItemData>[];

    for (final file in files) {
      try {
        final session = await loadSessionFromFile(file);
        items.add(SavedItemData.fromFile(file: file, session: session));
      } catch (_) {
        // Skip corrupted or old-format files.
      }
    }

    return items;
  }

  static Future<List<SavedItemData>> _getSafRecentItems() async {
    try {
      final documents = await _storageAccessService.listFiles(
        relativeDir: 'saved',
        extension: '.stala',
      );

      final items = <SavedItemData>[];

      for (final document in documents) {
        try {
          final session = await loadSessionFromStorageUri(document.uri);

          items.add(
            SavedItemData.fromSession(
              session,
              filePath: document.uri,
              fileType: '.stala',
              modifiedAt: document.modifiedAt,
              isSafDocument: true,
              storageUri: document.uri,
              fileName: document.fileName,
            ),
          );
        } catch (_) {
          // Skip corrupted or old-format SAF documents.
        }
      }

      items.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      return items;
    } catch (_) {
      return const [];
    }
  }

  static Future<SessionData> loadSessionFromFile(File file) async {
    final content = await file.readAsString();
    return loadSessionFromContent(content);
  }

  static Future<SessionData> loadSessionFromItem(SavedItemData item) async {
    if (item.isSafDocument && item.storageUri != null) {
      return loadSessionFromStorageUri(item.storageUri!);
    }

    return loadSessionFromFile(File(item.filePath));
  }

  static Future<String> readItemContent(SavedItemData item) async {
    if (item.isSafDocument && item.storageUri != null) {
      return _storageAccessService.readTextFile(item.storageUri!);
    }

    return File(item.filePath).readAsString();
  }

  static Future<SessionData> loadSessionFromStorageUri(String uri) async {
    final content = await _storageAccessService.readTextFile(uri);
    return loadSessionFromContent(content);
  }

  static SessionData loadSessionFromContent(String content) {
    final decoded = jsonDecode(content);

    final sessionJson = decoded['session'];

    if (sessionJson is! Map) {
      throw const FormatException('Invalid .stala file: missing session data.');
    }

    return SessionData.fromJson(Map<String, dynamic>.from(sessionJson));
  }

  static Future<void> deleteItem(SavedItemData item) async {
    if (item.isSafDocument && item.storageUri != null) {
      await _storageAccessService.deleteDocument(item.storageUri!);
      return;
    }

    final file = File(item.filePath);

    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<List<SavedItemData>> togglePinned(
    List<SavedItemData> items,
    SavedItemData target,
  ) async {
    return items.map((item) {
      if (item.id == target.id) {
        return item.copyWith(isPinned: !item.isPinned);
      }
      return item;
    }).toList()..sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.modifiedAt.compareTo(a.modifiedAt);
    });
  }

  static Future<List<SavedItemData>> searchItems(String query) async {
    final items = await getRecentItems();
    final normalized = query.trim().toLowerCase();

    if (normalized.isEmpty) return items;

    return items.where((item) {
      return item.title.toLowerCase().contains(normalized) ||
          item.fileType.toLowerCase().contains(normalized);
    }).toList();
  }

  static Future<void> renameItem(SavedItemData item, String newTitle) async {
    final content = await readItemContent(item);
    final decoded = jsonDecode(content);

    final sessionJson = decoded['session'];

    if (sessionJson is! Map) {
      throw const FormatException('Invalid .stala file: missing session data.');
    }

    final session = SessionData.fromJson(
      Map<String, dynamic>.from(sessionJson),
    );

    final updatedSession = session.copyWith(projectName: newTitle);

    decoded['session'] = updatedSession.toJson();
    decoded['exportedAt'] = DateTime.now().toIso8601String();

    final updatedContent = const JsonEncoder.withIndent('  ').convert(decoded);

    if (item.isSafDocument && item.storageUri != null) {
      await _storageAccessService.writeTextFile(
        relativeDir: 'saved',
        fileName: item.fileName ?? _safeFileNameForTitle(newTitle),
        mimeType: 'application/json',
        content: updatedContent,
      );
      return;
    }

    await File(item.filePath).writeAsString(updatedContent);
  }

  static String _safeFileNameForTitle(String title) {
    final safeTitle = title
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();

    return '${safeTitle.isEmpty ? 'stala_output' : safeTitle}.stala';
  }
}
