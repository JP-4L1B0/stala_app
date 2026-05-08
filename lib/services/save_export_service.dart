import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:path/path.dart' as p;
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';

import '../services/generation_service.dart';
import '../models/session_data.dart';
import '../models/saved_item_data.dart';
import '../data/recent_items_repository.dart';
import 'storage_access_service.dart';

class SaveExportService {
  const SaveExportService();

  static const StorageAccessService _storageAccessService =
      StorageAccessService();

  Future<File> saveStalaFile({required SessionData session}) async {
    final directory = await _getExportDirectory('saved');

    final safeTitle = _safeFileName(
      session.projectName.isEmpty ? 'stala_output' : session.projectName,
    );

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final file = File('${directory.path}/${safeTitle}_$timestamp.stala');

    final data = {
      'format': 'stala',
      'formatVersion': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'session': session.toJson(),
    };

    final content = const JsonEncoder.withIndent('  ').convert(data);

    await file.writeAsString(content);
    await _writeSafTextIfAvailable(
      relativeDir: 'saved',
      fileName: p.basename(file.path),
      mimeType: 'application/json',
      content: content,
    );

    return file;
  }

  Future<SessionData> loadStalaFile(File file) async {
    final content = await file.readAsString();
    final json = jsonDecode(content);

    final sessionJson = json['session'] as Map<String, dynamic>;

    return SessionData.fromJson(sessionJson);
  }

  Future<List<File>> saveTabPngPages({
    required String title,
    required GeneratedTabResult tab,
  }) async {
    final directory = await _getExportDirectory('photo');

    final safeTitle = _safeFileName(title.isEmpty ? 'tablature' : title);
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final exportDir = Directory(
      '${directory.path}/${safeTitle}_png_$timestamp',
    );

    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final files = <File>[];

    for (final page in tab.exportPages) {
      final image = await _renderTabPageToImage(
        title: title,
        tab: tab,
        page: page,
        totalPages: tab.exportPages.length,
      );

      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) continue;

      final file = File(
        '${exportDir.path}/tab_${(page.pageIndex + 1).toString().padLeft(3, '0')}.png',
      );

      await file.writeAsBytes(byteData.buffer.asUint8List());
      files.add(file);

      await _writeSafBytesIfAvailable(
        relativeDir: 'photo/${p.basename(exportDir.path)}',
        fileName: p.basename(file.path),
        mimeType: 'image/png',
        bytes: byteData.buffer.asUint8List(),
      );

      // Save to gallery (VISIBLE TO USER)
      await GallerySaver.saveImage(file.path);
    }

    return files;
  }

  Future<ui.Image> _renderTabPageToImage({
    required String title,
    required GeneratedTabResult tab,
    required TabExportPage page,
    required int totalPages,
  }) async {
    const double pageWidth = 1400;
    const double margin = 80;
    const double titleHeight = 120;
    const double infoHeight = 54;
    const double topPadding = titleHeight + infoHeight + 50;
    const double rowHeight = 58;
    const double bottomPadding = 100;
    const double labelWidth = 54;

    final usableWidth = pageWidth - (margin * 2) - labelWidth;
    final columnWidth = page.columns.isEmpty
        ? 52.0
        : (usableWidth / page.columns.length).clamp(42.0, 72.0);

    final pageHeight = topPadding + (6 * rowHeight) + bottomPadding;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, pageWidth, pageHeight),
      Paint()..color = Colors.white,
    );

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    void drawText(
      String text,
      Offset offset, {
      double fontSize = 24,
      FontWeight fontWeight = FontWeight.normal,
      Color color = Colors.black,
    }) {
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      );
      textPainter.layout(maxWidth: pageWidth - (margin * 2));
      textPainter.paint(canvas, offset);
    }

    drawText(
      title.isEmpty ? 'STALA Tablature Export' : title,
      Offset(margin, 44),
      fontSize: 34,
      fontWeight: FontWeight.w800,
    );

    drawText(
      'Mode: ${tab.mode.name}   •   Page ${page.pageIndex + 1} of $totalPages',
      Offset(margin, 92),
      fontSize: 20,
      color: Colors.black54,
    );

    final linePaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.8;

    final borderPaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final tabArea = Rect.fromLTWH(
      margin - 24,
      topPadding - 42,
      pageWidth - (margin * 2) + 48,
      (6 * rowHeight) + 84,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(tabArea, const Radius.circular(18)),
      borderPaint,
    );

    final rows = GenerationService.standardGuitarRows;

    for (final row in rows) {
      final y = topPadding + row.visualIndex * rowHeight;

      drawText(
        '${row.label}|',
        Offset(margin, y - 16),
        fontSize: 24,
        fontWeight: FontWeight.w700,
      );

      canvas.drawLine(
        Offset(margin + labelWidth, y),
        Offset(pageWidth - margin, y),
        linePaint,
      );
    }

    for (int localIndex = 0; localIndex < page.columns.length; localIndex++) {
      final column = page.columns[localIndex];

      final columnCenterX =
          margin + labelWidth + (localIndex * columnWidth) + (columnWidth / 2);

      if (column.isChord && column.label.isNotEmpty) {
        drawText(
          column.label,
          Offset(columnCenterX - 22, topPadding - 34),
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.black54,
        );
      }

      for (final number in column.numbers) {
        final y = topPadding + number.visualRowIndex * rowHeight;

        final fretText = number.fret.toString();

        textPainter.text = TextSpan(
          text: fretText,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        );
        textPainter.layout();

        final bgRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(columnCenterX, y),
            width: textPainter.width + 18,
            height: 34,
          ),
          const Radius.circular(8),
        );

        canvas.drawRRect(bgRect, Paint()..color = Colors.white);

        canvas.drawRRect(
          bgRect,
          Paint()
            ..color = Colors.black12
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );

        textPainter.paint(
          canvas,
          Offset(
            columnCenterX - textPainter.width / 2,
            y - textPainter.height / 2,
          ),
        );
      }
    }

    drawText(
      'Generated by STALA',
      Offset(margin, pageHeight - 52),
      fontSize: 18,
      color: Colors.black45,
    );

    final picture = recorder.endRecording();

    return picture.toImage(pageWidth.ceil(), pageHeight.ceil());
  }

  Future<File> saveZipPackage({
    required SessionData session,
    required int selectedModeIndex,
  }) async {
    final directory = await _getExportDirectory('zip');

    final safeTitle = _safeFileName(
      session.projectName.isEmpty ? 'stala_output' : session.projectName,
    );
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final zipPath = '${directory.path}/${safeTitle}_$timestamp.zip';

    final tempStalaFile = File(
      '${directory.path}/${safeTitle}_temp_$timestamp.stala',
    );

    final data = {
      'format': 'stala',
      'formatVersion': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'session': session.toJson(),
    };

    await tempStalaFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );

    final generatedTabs = GenerationService().generateAll(
      results: session.tablatureResults,
    );

    final selectedTab = generatedTabs[selectedModeIndex];

    final pngFiles = await saveTabPngPages(
      title: session.projectName,
      tab: selectedTab,
    );

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);

    encoder.addFile(tempStalaFile, 'project.stala');

    for (int i = 0; i < pngFiles.length; i++) {
      encoder.addFile(
        pngFiles[i],
        'tablature/tab_${(i + 1).toString().padLeft(3, '0')}.png',
      );
    }

    encoder.close();

    final zipFile = File(zipPath);

    if (await zipFile.exists()) {
      await _writeSafBytesIfAvailable(
        relativeDir: 'zip',
        fileName: p.basename(zipFile.path),
        mimeType: 'application/zip',
        bytes: await zipFile.readAsBytes(),
      );
    }

    if (await tempStalaFile.exists()) {
      await tempStalaFile.delete();
    }

    return zipFile;
  }

  Future<File> saveBulkStalaZip({required List<SavedItemData> items}) async {
    final directory = await _getExportDirectory('zip');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final zipFile = File('${directory.path}/stala_bulk_export_$timestamp.zip');
    final exportedAt = DateTime.now().toIso8601String();

    final archive = Archive();
    final manifestFiles = <Map<String, dynamic>>[];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final content = await RecentItemsRepository.readItemContent(item);
      final fileName = _safeBulkFileName(item, i);
      final archivePath = 'saved/$fileName';
      final bytes = utf8.encode(content);

      archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
      manifestFiles.add({
        'path': archivePath,
        'title': item.title,
        'originalFileName': item.fileName ?? p.basename(item.filePath),
        'exportedAt': exportedAt,
      });
    }

    final manifest = const JsonEncoder.withIndent('  ').convert({
      'format': 'stala_bulk_zip',
      'formatVersion': 1,
      'exportedAt': exportedAt,
      'fileCount': manifestFiles.length,
      'files': manifestFiles,
    });
    final manifestBytes = utf8.encode(manifest);

    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

    final zipBytes = ZipEncoder().encode(archive);

    await zipFile.writeAsBytes(zipBytes);

    await _writeSafBytesIfAvailable(
      relativeDir: 'zip',
      fileName: p.basename(zipFile.path),
      mimeType: 'application/zip',
      bytes: Uint8List.fromList(zipBytes),
    );

    return zipFile;
  }

  Future<void> _writeSafTextIfAvailable({
    required String relativeDir,
    required String fileName,
    required String mimeType,
    required String content,
  }) async {
    try {
      final folder = await _storageAccessService.getStorageFolder();
      if (!folder.granted) return;

      await _storageAccessService.writeTextFile(
        relativeDir: relativeDir,
        fileName: fileName,
        mimeType: mimeType,
        content: content,
      );
    } catch (_) {
      // App-private export still succeeds if the selected SAF folder is missing
      // or the provider rejects the write.
    }
  }

  Future<void> _writeSafBytesIfAvailable({
    required String relativeDir,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    try {
      final folder = await _storageAccessService.getStorageFolder();
      if (!folder.granted) return;

      await _storageAccessService.writeBinaryFile(
        relativeDir: relativeDir,
        fileName: fileName,
        mimeType: mimeType,
        bytes: bytes,
      );
    } catch (_) {
      // App-private export still succeeds if the selected SAF folder is missing
      // or the provider rejects the write.
    }
  }

  String _safeFileName(String input) {
    return input
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
  }

  String _safeBulkFileName(SavedItemData item, int index) {
    final title = _safeFileName(item.title);
    final fallback = 'stala_project_${(index + 1).toString().padLeft(3, '0')}';
    final base = title.isEmpty ? fallback : title;
    final suffix = (index + 1).toString().padLeft(3, '0');

    return '${base}_$suffix.stala';
  }

  Future<Directory> _getStalaRootDirectory() async {
    final baseDir = await getApplicationDocumentsDirectory();

    final rootDir = Directory('${baseDir.path}/Stala');

    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }

    return rootDir;
  }

  Future<Directory> _getExportDirectory(String folderName) async {
    final rootDir = await _getStalaRootDirectory();

    final targetDir = Directory('${rootDir.path}/$folderName');

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    return targetDir;
  }
}
