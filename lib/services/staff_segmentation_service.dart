import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';

class StaffSegmentationService {
  static const _visionPipelineChannel = MethodChannel('stala/python_bridge');

  Future<Map<String, dynamic>> segmentStaffLines({
    required String imagePath,
  }) async {
    try {
      print('SEGMENT: trying native OpenCV segmentation');

      final result = await _visionPipelineChannel.invokeMethod(
        'segmentStaffLines',
        {'imagePath': imagePath},
      );

      final nativeResult = Map<String, dynamic>.from(result);

      if (nativeResult['status'] == 'success') {
        print('SEGMENT: native OpenCV segmentation success');
        return _withStableContract(nativeResult);
      }

      print('SEGMENT: native failed, falling back to Dart');
      return _segmentStaffLinesFallback(imagePath: imagePath);
    } catch (e) {
      print('SEGMENT: native exception, falling back to Dart: $e');
      return _segmentStaffLinesFallback(imagePath: imagePath);
    }
  }

  Future<Map<String, dynamic>> _segmentStaffLinesFallback({
    required String imagePath,
  }) async {
    try {
      print('SEGMENT FALLBACK: input imagePath = $imagePath');

      final file = File(imagePath);
      print('SEGMENT FALLBACK: file exists = ${file.existsSync()}');

      if (!file.existsSync()) {
        throw Exception('Image not found: $imagePath');
      }

      final bytes = await file.readAsBytes();
      final original = img.decodeImage(bytes);

      print('SEGMENT FALLBACK: image decoded = ${original != null}');

      if (original == null) {
        throw Exception('Failed to decode image');
      }

      final gray = img.grayscale(original);
      final binary = img.Image.from(gray);

      const threshold = 170;

      for (int y = 0; y < binary.height; y++) {
        for (int x = 0; x < binary.width; x++) {
          final pixel = binary.getPixel(x, y);
          final l = img.getLuminance(pixel);

          if (l < threshold) {
            binary.setPixel(x, y, img.ColorRgb8(255, 255, 255));
          } else {
            binary.setPixel(x, y, img.ColorRgb8(0, 0, 0));
          }
        }
      }

      final rawRows = _collectRawHorizontalRows(binary);
      print('SEGMENT FALLBACK: rawRows = ${rawRows.length}');

      final lineCandidates = _deduplicateRows(rawRows);
      print('SEGMENT FALLBACK: lineCandidates = ${lineCandidates.length}');
      print('SEGMENT FALLBACK: candidate ys = $lineCandidates');

      final validatedStaffs = _buildValidatedStaffs(lineCandidates);
      print('SEGMENT FALLBACK: validatedStaffs = ${validatedStaffs.length}');

      final overlay = img.Image.from(original);

      // draw only validated staff lines
      for (final staff in validatedStaffs) {
        final lines = (staff['lines'] as List).cast<double>();

        for (final yVal in lines) {
          final y = yVal.round();

          for (int dy = -1; dy <= 1; dy++) {
            final yy = y + dy;
            if (yy < 0 || yy >= overlay.height) continue;

            for (int x = 0; x < overlay.width; x++) {
              overlay.setPixel(x, yy, img.ColorRgb8(255, 0, 0));
            }
          }
        }

        // optional: draw boundaries in blue for debugging
        final topBoundary = (staff['topBoundary'] as double).round();
        final bottomBoundary = (staff['bottomBoundary'] as double).round();

        for (int x = 0; x < overlay.width; x++) {
          if (topBoundary >= 0 && topBoundary < overlay.height) {
            overlay.setPixel(x, topBoundary, img.ColorRgb8(0, 140, 255));
          }
          if (bottomBoundary >= 0 && bottomBoundary < overlay.height) {
            overlay.setPixel(x, bottomBoundary, img.ColorRgb8(0, 140, 255));
          }
        }
      }

      final tempDir = Directory.systemTemp;
      final outputPath = p.join(
        tempDir.path,
        'segmented_${DateTime.now().millisecondsSinceEpoch}.png',
      );

      print('SEGMENT FALLBACK: outputPath = $outputPath');

      final outFile = File(outputPath);
      await outFile.writeAsBytes(img.encodePng(overlay));

      return {
        'status': 'success',
        'message': 'Fallback Dart segmentation completed',
        'segmentedImagePath': outputPath,
        'staffLineCount': validatedStaffs.fold<int>(
          0,
          (sum, staff) => sum + ((staff['lines'] as List).length),
        ),
        'staffLines': validatedStaffs.expand((staff) {
          final staffId = staff['id'] as String;
          final topBoundary = staff['topBoundary'] as double;
          final bottomBoundary = staff['bottomBoundary'] as double;
          final spacing = staff['spacing'] as double;
          final lines = (staff['lines'] as List).cast<double>();

          return lines.asMap().entries.map((entry) {
            return {
              'id': '${staffId}_line_${entry.key}',
              'staffId': staffId,
              'y': entry.value,
              'topBoundary': topBoundary,
              'bottomBoundary': bottomBoundary,
              'spacing': spacing,
            };
          });
        }).toList(),
        'ledgerLines': const [],
        'barLines': const [],
        'stems': const [],
        'beams': const [],
        'measures': _buildImplicitMeasures(
          staffs: validatedStaffs,
          imageWidth: original.width,
        ),
        'validatedStaffs': validatedStaffs,
      };
    } catch (e) {
      print('SEGMENT FALLBACK ERROR: $e');
      return {
        'status': 'error',
        'message': e.toString(),
        'segmentedImagePath': null,
        'staffLineCount': 0,
        'staffLines': [],
        'ledgerLines': [],
        'barLines': [],
        'stems': [],
        'beams': [],
        'measures': [],
        'validatedStaffs': [],
      };
    }
  }

  Map<String, dynamic> _withStableContract(Map<String, dynamic> result) {
    return {
      ...result,
      'staffLines': result['staffLines'] ?? const [],
      'ledgerLines': result['ledgerLines'] ?? const [],
      'barLines': result['barLines'] ?? const [],
      'stems': result['stems'] ?? const [],
      'beams': result['beams'] ?? const [],
      'measures': result['measures'] ?? const [],
      'validatedStaffs': result['validatedStaffs'] ?? const [],
    };
  }

  List<Map<String, dynamic>> _buildImplicitMeasures({
    required List<Map<String, dynamic>> staffs,
    required int imageWidth,
  }) {
    return staffs.asMap().entries.map((entry) {
      final staff = entry.value;
      final staffId = staff['id']?.toString() ?? 'staff_${entry.key}';

      return {
        'id': 'measure_${entry.key}',
        'staffId': staffId,
        'indexInStaff': 0,
        'x1': 0.0,
        'x2': imageWidth.toDouble(),
        'startBarLineId': null,
        'endBarLineId': null,
        'source': 'implicit_full_staff',
      };
    }).toList();
  }

  List<int> _collectRawHorizontalRows(img.Image binary) {
    final rows = <int>[];
    final minCoverage = (binary.width * 0.18).toInt();

    for (int y = 0; y < binary.height; y++) {
      int whiteCount = 0;

      for (int x = 0; x < binary.width; x++) {
        final pixel = binary.getPixel(x, y);
        if (img.getLuminance(pixel) > 200) {
          whiteCount++;
        }
      }

      if (whiteCount >= minCoverage) {
        rows.add(y);
      }
    }

    return rows;
  }

  List<double> _deduplicateRows(List<int> rawRows) {
    if (rawRows.isEmpty) return const [];

    final groups = <List<int>>[];
    var current = <int>[rawRows.first];

    for (int i = 1; i < rawRows.length; i++) {
      if (rawRows[i] - rawRows[i - 1] <= 2) {
        current.add(rawRows[i]);
      } else {
        groups.add(current);
        current = [rawRows[i]];
      }
    }
    groups.add(current);

    return groups
        .map((group) => group.reduce((a, b) => a + b) / group.length)
        .toList()
      ..sort();
  }

  List<Map<String, dynamic>> _buildValidatedStaffs(List<double> lines) {
    final staffs = <Map<String, dynamic>>[];
    final used = <int>{};

    for (int i = 0; i <= lines.length - 5; i++) {
      if (used.contains(i)) continue;

      final candidate = lines.sublist(i, i + 5);
      final spacings = <double>[
        candidate[1] - candidate[0],
        candidate[2] - candidate[1],
        candidate[3] - candidate[2],
        candidate[4] - candidate[3],
      ];

      final avgSpacing = spacings.reduce((a, b) => a + b) / spacings.length;

      // reject very tiny or huge spacing
      if (avgSpacing < 6 || avgSpacing > 40) {
        continue;
      }

      // require spacing consistency
      final isConsistent = spacings.every(
        (s) => (s - avgSpacing).abs() <= avgSpacing * 0.30,
      );

      print(
        'SEGMENT FALLBACK WINDOW: $candidate spacings=$spacings avg=$avgSpacing consistent=$isConsistent',
      );

      if (!isConsistent) continue;

      // avoid overlapping duplicate staff windows
      final overlapsUsed = List.generate(
        5,
        (offset) => i + offset,
      ).any((idx) => used.contains(idx));
      if (overlapsUsed) continue;

      final topBoundary = candidate.first - (avgSpacing * 1.2);
      final bottomBoundary = candidate.last + (avgSpacing * 1.2);

      final staffId = 'staff_${staffs.length}';

      staffs.add({
        'id': staffId,
        'lines': candidate,
        'spacing': avgSpacing,
        'topBoundary': topBoundary,
        'bottomBoundary': bottomBoundary,
      });

      for (int offset = 0; offset < 5; offset++) {
        used.add(i + offset);
      }
    }

    return staffs;
  }
}
