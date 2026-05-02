import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';

import '../services/generation_service.dart';
import '../models/session_data.dart';

class SaveExportService {
  const SaveExportService();

  Future<File> saveStalaFile({
    required SessionData session,
  }) async {
    final directory = await getApplicationDocumentsDirectory();

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

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
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
    final directory = await getApplicationDocumentsDirectory();

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
        tab: tab,
        page: page,
      );

      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) continue;

      final file = File(
        '${exportDir.path}/tab_${(page.pageIndex + 1).toString().padLeft(3, '0')}.png',
      );

      await file.writeAsBytes(byteData.buffer.asUint8List());
      files.add(file);
    }

    return files;
  }

  Future<ui.Image> _renderTabPageToImage({
    required GeneratedTabResult tab,
    required TabExportPage page,
  }) async {
    const double leftLabelWidth = 44;
    const double topPadding = 42;
    const double bottomPadding = 32;
    const double pageColumnWidth = 52;
    const double rowHeight = 38;

    final pageWidth =
        leftLabelWidth + (page.columns.length * pageColumnWidth) + 32;
    final pageHeight = topPadding + (6 * rowHeight) + bottomPadding;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final backgroundPaint = Paint()..color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, pageWidth, pageHeight),
      backgroundPaint,
    );

    final linePaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.2;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    final rows = GenerationService.standardGuitarRows;

    for (final row in rows) {
      final y = topPadding + row.visualIndex * rowHeight;

      textPainter.text = TextSpan(
        text: '${row.label}|',
        style: const TextStyle(
          color: Colors.black,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(12, y - 10));

      canvas.drawLine(
        Offset(leftLabelWidth, y),
        Offset(pageWidth - 16, y),
        linePaint,
      );
    }

    for (int localIndex = 0; localIndex < page.columns.length; localIndex++) {
      final column = page.columns[localIndex];
      final columnCenterX =
          leftLabelWidth + (localIndex * pageColumnWidth) + pageColumnWidth / 2;

      for (final number in column.numbers) {
        final y = topPadding + number.visualRowIndex * rowHeight;

        textPainter.text = TextSpan(
          text: number.fret.toString(),
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        );
        textPainter.layout();

        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(columnCenterX, y),
            width: textPainter.width + 10,
            height: 24,
          ),
          Paint()..color = Colors.white,
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

    final picture = recorder.endRecording();

    return picture.toImage(
      pageWidth.ceil(),
      pageHeight.ceil(),
    );
  }

  Future<File> saveZipPackage({
    required SessionData session,
    required int selectedModeIndex,
  }) async {
    final directory = await getApplicationDocumentsDirectory();

    final safeTitle = _safeFileName(
      session.projectName.isEmpty ? 'stala_output' : session.projectName,
    );
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final zipPath = '${directory.path}/${safeTitle}_$timestamp.zip';

    final stalaFile = await saveStalaFile(session: session);

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

    encoder.addFile(
      stalaFile,
      'project.stala',
    );

    for (int i = 0; i < pngFiles.length; i++) {
      encoder.addFile(
        pngFiles[i],
        'tablature/tab_${(i + 1).toString().padLeft(3, '0')}.png',
      );
    }

    encoder.close();

    return File(zipPath);
  }

  String _safeFileName(String input) {
    return input
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
  }
}