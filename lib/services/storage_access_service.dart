import 'package:flutter/services.dart';

class StorageAccessInfo {
  final bool granted;
  final String? uri;
  final String? displayName;

  const StorageAccessInfo({required this.granted, this.uri, this.displayName});

  factory StorageAccessInfo.fromMap(Map<dynamic, dynamic>? map) {
    return StorageAccessInfo(
      granted: map?['granted'] == true,
      uri: map?['uri']?.toString(),
      displayName: map?['displayName']?.toString(),
    );
  }
}

class StorageWriteResult {
  final String uri;
  final String relativeDir;
  final String fileName;

  const StorageWriteResult({
    required this.uri,
    required this.relativeDir,
    required this.fileName,
  });

  factory StorageWriteResult.fromMap(Map<dynamic, dynamic> map) {
    return StorageWriteResult(
      uri: map['uri']?.toString() ?? '',
      relativeDir: map['relativeDir']?.toString() ?? '',
      fileName: map['fileName']?.toString() ?? '',
    );
  }
}

class StorageDocumentInfo {
  final String uri;
  final String fileName;
  final String? mimeType;
  final DateTime? modifiedAt;
  final int size;

  const StorageDocumentInfo({
    required this.uri,
    required this.fileName,
    this.mimeType,
    this.modifiedAt,
    this.size = 0,
  });

  factory StorageDocumentInfo.fromMap(Map<dynamic, dynamic> map) {
    final lastModified = map['lastModified'];

    return StorageDocumentInfo(
      uri: map['uri']?.toString() ?? '',
      fileName: map['fileName']?.toString() ?? '',
      mimeType: map['mimeType']?.toString(),
      modifiedAt: lastModified is int && lastModified > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastModified)
          : null,
      size: map['size'] is int ? map['size'] as int : 0,
    );
  }
}

class ImportDocumentData {
  final String fileName;
  final String? mimeType;
  final Uint8List bytes;

  const ImportDocumentData({
    required this.fileName,
    this.mimeType,
    required this.bytes,
  });

  factory ImportDocumentData.fromMap(Map<dynamic, dynamic> map) {
    return ImportDocumentData(
      fileName: map['fileName']?.toString() ?? '',
      mimeType: map['mimeType']?.toString(),
      bytes: map['bytes'] is Uint8List
          ? map['bytes'] as Uint8List
          : Uint8List(0),
    );
  }
}

class StorageAccessService {
  static const MethodChannel _channel = MethodChannel('stala/storage_access');

  const StorageAccessService();

  Future<StorageAccessInfo> pickStorageFolder() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'pickStorageFolder',
    );

    return StorageAccessInfo.fromMap(result);
  }

  Future<ImportDocumentData?> pickImportDocument() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>?>(
      'pickImportDocument',
    );

    if (result == null) return null;

    return ImportDocumentData.fromMap(result);
  }

  Future<StorageAccessInfo> getPublicStalaFolder() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getPublicStalaFolder',
    );

    return StorageAccessInfo.fromMap(result);
  }

  Future<List<StorageDocumentInfo>> listPublicFiles({
    required String relativeDir,
    String? extension,
  }) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'listPublicFiles',
      {'relativeDir': relativeDir, 'extension': extension},
    );

    return (result ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(StorageDocumentInfo.fromMap)
        .where((file) => file.uri.isNotEmpty && file.fileName.isNotEmpty)
        .toList();
  }

  Future<StorageWriteResult> writePublicTextFile({
    required String relativeDir,
    required String fileName,
    required String content,
  }) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'writePublicTextFile',
      {'relativeDir': relativeDir, 'fileName': fileName, 'content': content},
    );

    return StorageWriteResult.fromMap(result ?? const {});
  }

  Future<StorageWriteResult> writePublicBinaryFile({
    required String relativeDir,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'writePublicBinaryFile',
      {'relativeDir': relativeDir, 'fileName': fileName, 'bytes': bytes},
    );

    return StorageWriteResult.fromMap(result ?? const {});
  }

  Future<String> readPublicTextFile(String path) async {
    return await _channel.invokeMethod<String>('readPublicTextFile', {
          'path': path,
        }) ??
        '';
  }

  Future<void> deletePublicFile(String path) async {
    await _channel.invokeMethod<bool>('deletePublicFile', {'path': path});
  }

  Future<StorageAccessInfo> getStorageFolder() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getStorageFolder',
    );

    return StorageAccessInfo.fromMap(result);
  }

  Future<void> clearStorageFolder() async {
    await _channel.invokeMethod<bool>('clearStorageFolder');
  }

  Future<StorageWriteResult> writeTextFile({
    required String relativeDir,
    required String fileName,
    required String mimeType,
    required String content,
  }) async {
    final result = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('writeTextFile', {
          'relativeDir': relativeDir,
          'fileName': fileName,
          'mimeType': mimeType,
          'content': content,
        });

    return StorageWriteResult.fromMap(result ?? const {});
  }

  Future<StorageWriteResult> writeBinaryFile({
    required String relativeDir,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final result = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('writeBinaryFile', {
          'relativeDir': relativeDir,
          'fileName': fileName,
          'mimeType': mimeType,
          'bytes': bytes,
        });

    return StorageWriteResult.fromMap(result ?? const {});
  }

  Future<List<StorageDocumentInfo>> listFiles({
    required String relativeDir,
    String? extension,
  }) async {
    final result = await _channel.invokeMethod<List<dynamic>>('listFiles', {
      'relativeDir': relativeDir,
      'extension': extension,
    });

    return (result ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(StorageDocumentInfo.fromMap)
        .where((file) => file.uri.isNotEmpty && file.fileName.isNotEmpty)
        .toList();
  }

  Future<String> readTextFile(String uri) async {
    return await _channel.invokeMethod<String>('readTextFile', {'uri': uri}) ??
        '';
  }

  Future<void> writeTextToUri({
    required String uri,
    required String content,
  }) async {
    await _channel.invokeMethod<bool>('writeTextToUri', {
      'uri': uri,
      'content': content,
    });
  }

  Future<void> deleteDocument(String uri) async {
    await _channel.invokeMethod<bool>('deleteDocument', {'uri': uri});
  }

  Future<String?> renameDocument({
    required String uri,
    required String newName,
  }) async {
    return await _channel.invokeMethod<String>('renameDocument', {
      'uri': uri,
      'newName': newName,
    });
  }
}
