import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/saved_item_data.dart';
import '../models/session_data.dart';

class RecentItemsRepository {
  RecentItemsRepository._();

  static Future<Directory> _savedDirectory() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final savedDir = Directory('${baseDir.path}/Stala/saved');

    if (!await savedDir.exists()) {
      await savedDir.create(recursive: true);
    }

    return savedDir;
  }

  static Future<List<SavedItemData>> getRecentItems() async {
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
        items.add(
          SavedItemData.fromFile(
            file: file,
            session: session,
          ),
        );
      } catch (_) {
        // Skip corrupted or old-format files.
      }
    }

    return items;
  }

  static Future<SessionData> loadSessionFromFile(File file) async {
    final content = await file.readAsString();
    final decoded = jsonDecode(content);

    final sessionJson = decoded['session'];

    if (sessionJson is! Map) {
      throw const FormatException('Invalid .stala file: missing session data.');
    }

    return SessionData.fromJson(
      Map<String, dynamic>.from(sessionJson),
    );
  }

  static Future<void> deleteItem(SavedItemData item) async {
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
    }).toList()
      ..sort((a, b) {
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

  static Future<void> renameItem(
      SavedItemData item,
      String newTitle,
      ) async {
    final file = File(item.filePath);

    final content = await file.readAsString();
    final decoded = jsonDecode(content);

    final sessionJson = decoded['session'];

    if (sessionJson is! Map) {
      throw const FormatException('Invalid .stala file: missing session data.');
    }

    final session = SessionData.fromJson(
      Map<String, dynamic>.from(sessionJson),
    );

    final updatedSession = session.copyWith(
      projectName: newTitle,
    );

    decoded['session'] = updatedSession.toJson();
    decoded['exportedAt'] = DateTime.now().toIso8601String();

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(decoded),
    );
  }
}