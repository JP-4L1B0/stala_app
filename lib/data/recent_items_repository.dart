import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/saved_item_data.dart';
import '../models/session_data.dart';
import '../services/storage_access_service.dart';

class RecentItemsRepository {
  RecentItemsRepository._();

  static const StorageAccessService _storageAccessService =
      StorageAccessService();

  static Future<Directory> _stalaRootDirectory() async {
    final externalDir = await getExternalStorageDirectory();
    final baseDir = externalDir ?? await getApplicationDocumentsDirectory();
    final rootDir = Directory('${baseDir.path}/Stala');

    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }

    return rootDir;
  }

  static Future<String> getDefaultStoragePath() async {
    final publicFolder = await _storageAccessService.getPublicStalaFolder();
    if (publicFolder.granted && publicFolder.uri != null) {
      return publicFolder.uri!;
    }

    return (await _stalaRootDirectory()).path;
  }

  static Future<Directory> _savedDirectory() async {
    final rootDir = await _stalaRootDirectory();
    final savedDir = Directory('${rootDir.path}/saved');

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

    return const [];
  }

  static List<SavedItemData> _mergeRecentItems({
    required List<SavedItemData> primaryItems,
    required List<SavedItemData> fallbackItems,
  }) {
    final mergedItems = <SavedItemData>[];
    final seenKeys = <String>{};

    for (final item in [...primaryItems, ...fallbackItems]) {
      final key = _dedupeKey(item);
      if (seenKeys.add(key)) {
        mergedItems.add(item);
      }
    }

    mergedItems.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return mergedItems;
  }

  static Future<List<SavedItemData>> _getSafRecentItems() async {
    try {
      final documents = await _storageAccessService.listFiles(
        relativeDir: 'saved',
        extension: null,
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
    return loadSessionFromContent(await readItemContent(item));
  }

  static Future<String> readItemContent(SavedItemData item) async {
    if (item.isSafDocument && item.storageUri != null) {
      return _storageAccessService.readTextFile(item.storageUri!);
    }

    if (_isPublicStalaPath(item.filePath)) {
      return _storageAccessService.readPublicTextFile(item.filePath);
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

    if (_isPublicStalaPath(item.filePath)) {
      await _storageAccessService.deletePublicFile(item.filePath);
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
    await updateItemTitle(item, newTitle);
  }

  static Future<ImportArchiveResult> importStalaBytes({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final content = utf8.decode(bytes);
    loadSessionFromContent(content);

    final safeFileName = _safeImportedFileName(fileName);
    await _assertUniqueFileName(safeFileName);

    await _writeSelectedSavedFile(fileName: safeFileName, content: content);

    return const ImportArchiveResult(importedCount: 1);
  }

  static Future<ImportArchiveResult> importZipBytes({
    required Uint8List bytes,
  }) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    var importedCount = 0;
    var duplicateCount = 0;
    var invalidCount = 0;

    for (final file in archive.files) {
      if (!file.isFile || !file.name.toLowerCase().endsWith('.stala')) {
        continue;
      }

      try {
        final contentBytes = file.content is Uint8List
            ? file.content as Uint8List
            : Uint8List.fromList((file.content as List).cast<int>());
        final content = utf8.decode(contentBytes);
        loadSessionFromContent(content);

        final safeFileName = _safeImportedFileName(file.name);

        try {
          await _assertUniqueFileName(safeFileName);
        } on DuplicateFileNameException {
          duplicateCount++;
          continue;
        }

        await _writeSelectedSavedFile(fileName: safeFileName, content: content);
        importedCount++;
      } catch (_) {
        invalidCount++;
      }
    }

    if (importedCount == 0 && duplicateCount == 0 && invalidCount == 0) {
      throw const FormatException('ZIP does not contain any .stala files.');
    }

    return ImportArchiveResult(
      importedCount: importedCount,
      duplicateCount: duplicateCount,
      invalidCount: invalidCount,
    );
  }

  static Future<List<SavedItemData>> getLocalRecentItems() async {
    final publicItems = await _getPublicRecentItems();
    if (publicItems.isNotEmpty) {
      return publicItems;
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

  static Future<List<SavedItemData>> _getPublicRecentItems() async {
    try {
      final documents = await _storageAccessService.listPublicFiles(
        relativeDir: 'saved',
        extension: '.stala',
      );

      final items = <SavedItemData>[];

      for (final document in documents) {
        final lowerName = document.fileName.toLowerCase();
        if (!lowerName.endsWith('.stala') &&
            !lowerName.endsWith('.stala.json')) {
          continue;
        }

        try {
          final content = await _storageAccessService.readPublicTextFile(
            document.uri,
          );
          final session = loadSessionFromContent(content);

          items.add(
            SavedItemData.fromSession(
              session,
              filePath: document.uri,
              fileType: '.stala',
              modifiedAt: document.modifiedAt,
              fileName: document.fileName,
            ),
          );
        } catch (_) {
          // Skip corrupted or unreadable public files.
        }
      }

      items.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      return items;
    } catch (_) {
      return const [];
    }
  }

  static Future<SavedItemData> updateItemTitle(
    SavedItemData item,
    String newTitle,
  ) async {
    await _assertUniqueTitle(newTitle: newTitle, currentItem: item);

    final content = await readItemContent(item);
    final updatedContent = _updatedTitleContent(content, newTitle);

    if (item.isSafDocument && item.storageUri != null) {
      final nextFileName = _safeFileNameForTitle(newTitle);
      var targetUri = item.storageUri!;

      if (item.fileName?.toLowerCase() != nextFileName) {
        targetUri =
            await _storageAccessService.renameDocument(
              uri: item.storageUri!,
              newName: nextFileName,
            ) ??
            item.storageUri!;
      }

      await _storageAccessService.writeTextToUri(
        uri: targetUri,
        content: updatedContent,
      );
      return item.copyWith(
        title: newTitle,
        filePath: targetUri,
        storageUri: targetUri,
        fileName: nextFileName,
      );
    }

    if (_isPublicStalaPath(item.filePath)) {
      await _storageAccessService.writePublicTextFile(
        relativeDir: 'saved',
        fileName: item.fileName ?? _safeFileNameForTitle(newTitle),
        content: updatedContent,
      );
      return item.copyWith(title: newTitle);
    }

    await File(item.filePath).writeAsString(updatedContent);
    return item.copyWith(title: newTitle);
  }

  static Future<String?> updateFileTitle({
    required String filePath,
    required String newTitle,
  }) async {
    if (filePath.startsWith('content://')) {
      await _assertUniqueTitle(newTitle: newTitle, currentFilePath: filePath);

      final content = await _storageAccessService.readTextFile(filePath);
      final updatedContent = _updatedTitleContent(content, newTitle);
      final targetUri =
          await _storageAccessService.renameDocument(
            uri: filePath,
            newName: _safeFileNameForTitle(newTitle),
          ) ??
          filePath;

      await _storageAccessService.writeTextToUri(
        uri: targetUri,
        content: updatedContent,
      );
      return targetUri;
    }

    if (_isPublicStalaPath(filePath)) {
      await _assertUniqueTitle(newTitle: newTitle, currentFilePath: filePath);

      final content = await _storageAccessService.readPublicTextFile(filePath);
      final updatedContent = _updatedTitleContent(content, newTitle);
      await _storageAccessService.writePublicTextFile(
        relativeDir: 'saved',
        fileName: filePath.split('/').last.split('\\').last,
        content: updatedContent,
      );
      return filePath;
    }

    final file = File(filePath);
    if (!await file.exists()) return null;

    await _assertUniqueTitle(newTitle: newTitle, currentFilePath: filePath);

    final content = await file.readAsString();
    final updatedContent = _updatedTitleContent(content, newTitle);
    await file.writeAsString(updatedContent);
    return filePath;
  }

  static Future<void> _writeSelectedSavedFile({
    required String fileName,
    required String content,
  }) async {
    final storage = await _storageAccessService.getStorageFolder();
    if (!storage.granted) {
      throw const StoragePathRequiredException();
    }

    await _storageAccessService.writeTextFile(
      relativeDir: 'saved',
      fileName: fileName,
      mimeType: 'application/octet-stream',
      content: content,
    );
  }

  static Future<void> _assertUniqueTitle({
    required String newTitle,
    SavedItemData? currentItem,
    String? currentFilePath,
  }) async {
    final candidateFileName = _safeFileNameForTitle(newTitle);
    final currentKey = currentItem == null ? null : _itemKey(currentItem);
    final normalizedCurrentPath = currentFilePath == null
        ? null
        : _normalizePath(currentFilePath);

    final items = await getRecentItems();

    for (final item in items) {
      final isSameItem =
          (currentKey != null && _itemKey(item) == currentKey) ||
          (normalizedCurrentPath != null &&
              _normalizePath(item.filePath) == normalizedCurrentPath);

      if (isSameItem) continue;

      final existingTitleFileName = _safeFileNameForTitle(item.title);
      final existingStoredFileName = item.fileName?.toLowerCase();

      if (existingTitleFileName == candidateFileName ||
          existingStoredFileName == candidateFileName) {
        throw DuplicateFileNameException(newTitle);
      }
    }
  }

  static Future<void> _assertUniqueFileName(String fileName) async {
    final normalizedFileName = fileName.toLowerCase();
    final items = await getRecentItems();

    for (final item in items) {
      final existingFileName = item.fileName?.toLowerCase();
      final existingTitleFileName = _safeFileNameForTitle(item.title);

      if (existingFileName == normalizedFileName ||
          existingTitleFileName == normalizedFileName) {
        throw DuplicateFileNameException(fileName);
      }
    }
  }

  static String _itemKey(SavedItemData item) {
    return item.storageUri ?? item.filePath;
  }

  static String _dedupeKey(SavedItemData item) {
    final fileName = item.fileName;
    if (fileName != null && fileName.isNotEmpty) {
      return fileName.toLowerCase();
    }

    return _safeFileNameForTitle(item.title);
  }

  static String _normalizePath(String path) {
    return path.replaceAll('\\', '/').toLowerCase();
  }

  static bool _isPublicStalaPath(String path) {
    return _normalizePath(path).contains('/storage/emulated/0/stala/');
  }

  static String _updatedTitleContent(String content, String newTitle) {
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

    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  static String _safeFileNameForTitle(String title) {
    final safeTitle = title
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();

    return '${safeTitle.isEmpty ? 'stala_output' : safeTitle}.stala';
  }

  static String _safeImportedFileName(String fileName) {
    final rawName = fileName.split('/').last.split('\\').last;
    final baseName = rawName.toLowerCase().endsWith('.stala')
        ? rawName.substring(0, rawName.length - 6)
        : rawName;
    final safeBaseName = baseName
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();

    return '${safeBaseName.isEmpty ? 'imported_stala' : safeBaseName}.stala';
  }
}

class ImportArchiveResult {
  final int importedCount;
  final int duplicateCount;
  final int invalidCount;

  const ImportArchiveResult({
    required this.importedCount,
    this.duplicateCount = 0,
    this.invalidCount = 0,
  });

  String get message {
    final parts = <String>['Imported $importedCount STALA file(s).'];

    if (duplicateCount > 0) {
      parts.add('Skipped $duplicateCount duplicate(s).');
    }

    if (invalidCount > 0) {
      parts.add('Skipped $invalidCount invalid file(s).');
    }

    return parts.join(' ');
  }
}

class DuplicateFileNameException implements Exception {
  final String title;

  const DuplicateFileNameException(this.title);

  @override
  String toString() {
    return 'A file named "$title" already exists.';
  }
}

class StoragePathRequiredException implements Exception {
  const StoragePathRequiredException();

  @override
  String toString() {
    return 'Choose a storage folder before importing or saving files.';
  }
}
