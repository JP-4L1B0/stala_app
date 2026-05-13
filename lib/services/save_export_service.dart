import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../services/generation_service.dart';
import '../models/session_data.dart';
import '../models/saved_item_data.dart';
import '../data/recent_items_repository.dart';
import 'storage_access_service.dart';

enum TablatureExportOrientation { portrait, landscape }

class SaveExportService {
  const SaveExportService();

  static const StorageAccessService _storageAccessService =
      StorageAccessService();

  Future<File> saveStalaFile({required SessionData session}) async {
    final safeTitle = _safeFileName(
      session.projectName.isEmpty ? 'stala_output' : session.projectName,
    );

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final fileName = '${safeTitle}_$timestamp.stala';

    final data = {
      'format': 'stala',
      'formatVersion': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'session': session.toJson(),
    };

    final content = const JsonEncoder.withIndent('  ').convert(data);

    final storage = await _storageAccessService.getStorageFolder();
    if (!storage.granted) {
      throw const StoragePathRequiredException();
    }

    final writeResult = await _storageAccessService.writeTextFile(
      relativeDir: 'saved',
      fileName: fileName,
      mimeType: 'application/octet-stream',
      content: content,
    );

    return File(writeResult.uri);
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
    TablatureExportOrientation orientation = TablatureExportOrientation.portrait,
  }) async {
    await _requireStorageFolder();
    final safeTitle = _safeFileName(title.isEmpty ? 'tablature' : title);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final exportDirName = '${safeTitle}_png_$timestamp';
    final files = <File>[];
    final pngBytes = await _renderTabPngBytes(
      title: title,
      tab: tab,
      orientation: orientation,
    );

    for (int index = 0; index < pngBytes.length; index++) {
      final fileName = 'tab_${(index + 1).toString().padLeft(3, '0')}.png';
      final bytes = pngBytes[index];

      final writeResult = await _storageAccessService.writeBinaryFile(
        relativeDir: 'photo/$exportDirName',
        fileName: fileName,
        mimeType: 'image/png',
        bytes: bytes,
      );
      files.add(File(writeResult.uri));
    }

    return files;
  }

  Future<List<Uint8List>> _renderTabPngBytes({
    required String title,
    required GeneratedTabResult tab,
    required TablatureExportOrientation orientation,
  }) async {
    final pagesToRender = orientation == TablatureExportOrientation.portrait
        ? [
            await _renderPortraitTabPagesToImage(
              title: title,
              tab: tab,
            ),
          ]
        : <ui.Image>[];

    if (orientation == TablatureExportOrientation.landscape) {
      for (final page in tab.exportPages) {
        pagesToRender.add(
          await _renderTabPageToImage(
            title: title,
            tab: tab,
            page: page,
            totalPages: tab.exportPages.length,
            orientation: orientation,
          ),
        );
      }
    }

    final pngBytes = <Uint8List>[];
    for (final image in pagesToRender) {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) continue;

      pngBytes.add(byteData.buffer.asUint8List());
    }

    return pngBytes;
  }

  Future<File> saveTabPdf({
    required String title,
    required GeneratedTabResult tab,
    TablatureExportOrientation orientation = TablatureExportOrientation.portrait,
  }) async {
    await _requireStorageFolder();
    final safeTitle = _safeFileName(title.isEmpty ? 'tablature' : title);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '${safeTitle}_$timestamp.pdf';

    final pageImages = <_PdfImagePage>[];

    final renderedPages = orientation == TablatureExportOrientation.portrait
        ? [
            await _renderPortraitTabPagesToImage(
              title: title,
              tab: tab,
            ),
          ]
        : <ui.Image>[];

    if (orientation == TablatureExportOrientation.landscape) {
      for (final page in tab.exportPages) {
        renderedPages.add(
          await _renderTabPageToImage(
            title: title,
            tab: tab,
            page: page,
            totalPages: tab.exportPages.length,
            orientation: orientation,
          ),
        );
      }
    }

    for (final rendered in renderedPages) {
      final byteData = await rendered.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) continue;

      final decoded = img.decodePng(byteData.buffer.asUint8List());
      if (decoded == null) continue;

      pageImages.add(
        _PdfImagePage(
          bytes: Uint8List.fromList(img.encodeJpg(decoded, quality: 92)),
          width: rendered.width,
          height: rendered.height,
        ),
      );
    }

    final pdfBytes = _buildImagePdf(pageImages);
    final writeResult = await _storageAccessService.writeBinaryFile(
      relativeDir: 'pdf',
      fileName: fileName,
      mimeType: 'application/pdf',
      bytes: pdfBytes,
    );

    return File(writeResult.uri);
  }

  Future<ui.Image> _renderTabPageToImage({
    required String title,
    required GeneratedTabResult tab,
    required TabExportPage page,
    required int totalPages,
    required TablatureExportOrientation orientation,
  }) async {
    final pageWidth =
        orientation == TablatureExportOrientation.landscape ? 2100.0 : 1400.0;
    final pageHeight =
        orientation == TablatureExportOrientation.landscape ? 1180.0 : 1980.0;
    const double margin = 80;
    const double titleHeight = 120;
    const double infoHeight = 54;
    final topPadding = orientation == TablatureExportOrientation.landscape
        ? titleHeight + infoHeight + 110
        : titleHeight + infoHeight + 360;
    const double rowHeight = 58;
    const double labelWidth = 54;

    final usableWidth = pageWidth - (margin * 2) - labelWidth;
    final columnWidth = page.columns.isEmpty
        ? 52.0
        : (usableWidth / page.columns.length).clamp(42.0, 72.0);

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

  Future<ui.Image> _renderPortraitTabPagesToImage({
    required String title,
    required GeneratedTabResult tab,
  }) async {
    const double pageWidth = 1400;
    const double pageHeight = 1980;
    const double margin = 80;
    const double labelWidth = 54;
    const double headerTop = 44;
    const double firstTabTop = 210;
    const double footerHeight = 80;
    const double sectionGap = 26;

    final pages = tab.exportPages;
    if (pages.isEmpty) {
      return _renderEmptyPortraitPage(title: title, tab: tab);
    }

    final usableHeight =
        pageHeight - firstTabTop - footerHeight - (sectionGap * (pages.length - 1));
    final sectionHeight = usableHeight / pages.length;
    final rowHeight = ((sectionHeight - 84) / 6).clamp(24.0, 58.0);
    final tabAreaHeight = (6 * rowHeight) + 72;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, pageWidth, pageHeight),
      Paint()..color = Colors.white,
    );

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    void drawText(
      String text,
      Offset offset, {
      double fontSize = 24,
      FontWeight fontWeight = FontWeight.normal,
      Color color = Colors.black,
      double? maxWidth,
    }) {
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      );
      textPainter.layout(maxWidth: maxWidth ?? pageWidth - (margin * 2));
      textPainter.paint(canvas, offset);
    }

    drawText(
      title.isEmpty ? 'STALA Tablature Export' : title,
      const Offset(margin, headerTop),
      fontSize: 34,
      fontWeight: FontWeight.w800,
    );

    drawText(
      'Mode: ${tab.mode.name}   -   ${pages.length} tablature section(s)',
      const Offset(margin, 92),
      fontSize: 20,
      color: Colors.black54,
    );

    final linePaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.5;

    final borderPaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    for (int sectionIndex = 0; sectionIndex < pages.length; sectionIndex++) {
      final page = pages[sectionIndex];
      final sectionTop =
          firstTabTop + (sectionIndex * (sectionHeight + sectionGap));
      final tabTop = sectionTop + 42;
      final usableWidth = pageWidth - (margin * 2) - labelWidth;
      final columnWidth = page.columns.isEmpty
          ? 52.0
          : (usableWidth / page.columns.length).clamp(34.0, 72.0);

      drawText(
        'Tablature ${sectionIndex + 1}',
        Offset(margin, sectionTop),
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.black54,
      );

      final tabArea = Rect.fromLTWH(
        margin - 24,
        tabTop - 36,
        pageWidth - (margin * 2) + 48,
        tabAreaHeight,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(tabArea, const Radius.circular(16)),
        borderPaint,
      );

      for (final row in GenerationService.standardGuitarRows) {
        final y = tabTop + row.visualIndex * rowHeight;

        drawText(
          '${row.label}|',
          Offset(margin, y - 14),
          fontSize: 20,
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

        if (column.isChord && column.label.isNotEmpty && rowHeight >= 32) {
          drawText(
            column.label,
            Offset(columnCenterX - 18, tabTop - 30),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.black54,
            maxWidth: 48,
          );
        }

        for (final number in column.numbers) {
          final y = tabTop + number.visualRowIndex * rowHeight;

          textPainter.text = TextSpan(
            text: number.fret.toString(),
            style: const TextStyle(
              color: Colors.black,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          );
          textPainter.layout();

          final bgRect = RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(columnCenterX, y),
              width: textPainter.width + 14,
              height: 30,
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
    }

    drawText(
      'Generated by STALA',
      const Offset(margin, pageHeight - 52),
      fontSize: 18,
      color: Colors.black45,
    );

    final picture = recorder.endRecording();
    return picture.toImage(pageWidth.ceil(), pageHeight.ceil());
  }

  Future<ui.Image> _renderEmptyPortraitPage({
    required String title,
    required GeneratedTabResult tab,
  }) {
    return _renderTabPageToImage(
      title: title,
      tab: tab,
      page: const TabExportPage(
        pageIndex: 0,
        startEventIndex: 0,
        endEventIndex: 0,
        columns: [],
      ),
      totalPages: 1,
      orientation: TablatureExportOrientation.portrait,
    );
  }

  Future<File> saveZipPackage({
    required SessionData session,
    required int selectedModeIndex,
  }) async {
    await _requireStorageFolder();
    final safeTitle = _safeFileName(
      session.projectName.isEmpty ? 'stala_output' : session.projectName,
    );
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '${safeTitle}_$timestamp.zip';

    final data = {
      'format': 'stala',
      'formatVersion': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'session': session.toJson(),
    };
    final stalaBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(data),
    );

    final generatedTabs = GenerationService().generateAll(
      results: session.tablatureResults,
    );

    final selectedTab = generatedTabs[selectedModeIndex];
    final pngBytes = await _renderTabPngBytes(
      title: session.projectName,
      tab: selectedTab,
      orientation: TablatureExportOrientation.portrait,
    );

    final archive = Archive();
    archive.addFile(ArchiveFile('project.stala', stalaBytes.length, stalaBytes));

    for (int i = 0; i < pngBytes.length; i++) {
      archive.addFile(
        ArchiveFile(
          'tablature/tab_${(i + 1).toString().padLeft(3, '0')}.png',
          pngBytes[i].length,
          pngBytes[i],
        ),
      );
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw const FormatException('Unable to create ZIP package.');
    }

    final writeResult = await _storageAccessService.writeBinaryFile(
      relativeDir: 'zip',
      fileName: fileName,
      mimeType: 'application/zip',
      bytes: Uint8List.fromList(zipBytes),
    );

    return File(writeResult.uri);
  }

  Future<File> saveBulkStalaZip({required List<SavedItemData> items}) async {
    await _requireStorageFolder();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'stala_bulk_export_$timestamp.zip';
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
    if (zipBytes == null) {
      throw const FormatException('Unable to create ZIP package.');
    }

    final writeResult = await _storageAccessService.writeBinaryFile(
      relativeDir: 'zip',
      fileName: fileName,
      mimeType: 'application/zip',
      bytes: Uint8List.fromList(zipBytes),
    );

    return File(writeResult.uri);
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

  Future<void> _requireStorageFolder() async {
    final storage = await _storageAccessService.getStorageFolder();
    if (!storage.granted) {
      throw const StoragePathRequiredException();
    }
  }

  Uint8List _buildImagePdf(List<_PdfImagePage> pages) {
    if (pages.isEmpty) {
      throw const FormatException('No tablature pages available for PDF.');
    }

    final objects = <List<int>>[];
    final pageObjectNumbers = <int>[];

    List<int> ascii(String value) => latin1.encode(value);

    for (int index = 0; index < pages.length; index++) {
      final page = pages[index];
      final imageObjectNumber = 4 + (index * 3);
      final contentObjectNumber = imageObjectNumber + 1;
      final pageObjectNumber = imageObjectNumber + 2;
      final imageName = 'Im${index + 1}';

      objects.add(
        _pdfStreamObject(
          dictionary:
              '<< /Type /XObject /Subtype /Image /Width ${page.width} /Height ${page.height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${page.bytes.length} >>',
          bytes: page.bytes,
        ),
      );

      final content =
          'q\n${page.width} 0 0 ${page.height} 0 0 cm\n/$imageName Do\nQ\n';
      final contentBytes = ascii(content);

      objects.add(
        _pdfStreamObject(
          dictionary: '<< /Length ${contentBytes.length} >>',
          bytes: Uint8List.fromList(contentBytes),
        ),
      );

      objects.add(
        ascii(
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${page.width} ${page.height}] /Resources << /XObject << /$imageName $imageObjectNumber 0 R >> >> /Contents $contentObjectNumber 0 R >>',
        ),
      );

      pageObjectNumbers.add(pageObjectNumber);
    }

    final kids = pageObjectNumbers.map((number) => '$number 0 R').join(' ');
    final catalog = ascii('<< /Type /Catalog /Pages 2 0 R >>');
    final pageTree = ascii(
      '<< /Type /Pages /Kids [$kids] /Count ${pages.length} >>',
    );
    final metadata = ascii(
      '<< /Producer (STALA) /CreationDate (D:${_pdfTimestamp(DateTime.now())}) >>',
    );

    final allObjects = <List<int>>[
      catalog,
      pageTree,
      metadata,
      ...objects,
    ];

    final output = BytesBuilder();
    output.add(ascii('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n'));

    final offsets = <int>[0];

    for (int i = 0; i < allObjects.length; i++) {
      offsets.add(output.length);
      output.add(ascii('${i + 1} 0 obj\n'));
      output.add(allObjects[i]);
      output.add(ascii('\nendobj\n'));
    }

    final xrefOffset = output.length;
    output.add(ascii('xref\n0 ${allObjects.length + 1}\n'));
    output.add(ascii('0000000000 65535 f \n'));

    for (int i = 1; i < offsets.length; i++) {
      output.add(ascii('${offsets[i].toString().padLeft(10, '0')} 00000 n \n'));
    }

    output.add(
      ascii(
        'trailer\n<< /Size ${allObjects.length + 1} /Root 1 0 R /Info 3 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n',
      ),
    );

    return output.toBytes();
  }

  List<int> _pdfStreamObject({
    required String dictionary,
    required Uint8List bytes,
  }) {
    final builder = BytesBuilder();
    builder.add(latin1.encode('$dictionary\nstream\n'));
    builder.add(bytes);
    builder.add(latin1.encode('\nendstream'));
    return builder.toBytes();
  }

  String _pdfTimestamp(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }
}

class _PdfImagePage {
  final Uint8List bytes;
  final int width;
  final int height;

  const _PdfImagePage({
    required this.bytes,
    required this.width,
    required this.height,
  });
}
