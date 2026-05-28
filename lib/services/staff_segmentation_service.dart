import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';

class StaffSegmentationService {
  static const _visionPipelineChannel = MethodChannel('stala/python_bridge');

  Future<Map<String, dynamic>> segmentStaffLines({
    required String imagePath,
    List<dynamic> symbolDetections = const [],
  }) async {
    try {
      print('SEGMENT: trying native OpenCV segmentation');

      final result = await _visionPipelineChannel.invokeMethod(
        'segmentStaffLines',
        {
          'imagePath': imagePath,
          'symbolDetections': symbolDetections,
        },
      );

      final nativeResult = Map<String, dynamic>.from(result);

      if (nativeResult['status'] == 'success') {
        print('SEGMENT: native OpenCV segmentation success');
        return _withStableContract(nativeResult);
      }

      print('SEGMENT: native failed, falling back to Dart');
      return _segmentStaffLinesFallback(
        imagePath: imagePath,
        symbolDetections: symbolDetections,
      );
    } catch (e) {
      print('SEGMENT: native exception, falling back to Dart: $e');
      return _segmentStaffLinesFallback(
        imagePath: imagePath,
        symbolDetections: symbolDetections,
      );
    }
  }

  Future<Map<String, dynamic>> _segmentStaffLinesFallback({
    required String imagePath,
    List<dynamic> symbolDetections = const [],
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

      final lineCandidates = _deduplicateRows(rawRows.map((row) => row.y).toList());
      print('SEGMENT FALLBACK: lineCandidates = ${lineCandidates.length}');
      print('SEGMENT FALLBACK: candidate ys = $lineCandidates');

      final metricsByY = {for (final row in rawRows) row.y: row};
      final validatedStaffs = _buildValidatedStaffs(
        lineCandidates,
        metricsByY,
        symbolDetections,
      );
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
        'imageWidth': original.width,
        'imageHeight': original.height,
        'staffLineCount': validatedStaffs.fold<int>(
          0,
          (sum, staff) => sum + ((staff['lines'] as List).length),
        ),
        'staffLines': validatedStaffs.expand((staff) {
          final staffId = staff['id'] as String;
          final topBoundary = staff['topBoundary'] as double;
          final bottomBoundary = staff['bottomBoundary'] as double;
          final spacing = staff['spacing'] as double;
          final confidence = (staff['confidence'] as num?)?.toDouble() ?? 1.0;
          final lines = (staff['lines'] as List).cast<double>();

          return lines.asMap().entries.map((entry) {
            return {
              'id': '${staffId}_line_${entry.key}',
              'staffId': staffId,
              'y': entry.value,
              'topBoundary': topBoundary,
              'bottomBoundary': bottomBoundary,
              'spacing': spacing,
              'confidence': confidence,
            };
          });
        }).toList(),
        'ledgerLines': const [],
        'ledgerDiagnostics': const {
          'rawCandidates': 0,
          'validatedLedgers': 0,
          'rejectedFragments': 0,
          'rejectionReasons': {},
        },
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
        'ledgerDiagnostics': const {
          'rawCandidates': 0,
          'validatedLedgers': 0,
          'rejectedFragments': 0,
          'rejectionReasons': {},
        },
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
      'ledgerDiagnostics': result['ledgerDiagnostics'] ?? const {
        'rawCandidates': 0,
        'validatedLedgers': 0,
        'rejectedFragments': 0,
        'rejectionReasons': {},
      },
      'barLines': result['barLines'] ?? const [],
      'stems': result['stems'] ?? const [],
      'beams': result['beams'] ?? const [],
      'measures': result['measures'] ?? const [],
      'imageWidth': result['imageWidth'],
      'imageHeight': result['imageHeight'],
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

  List<_RowCandidate> _collectRawHorizontalRows(img.Image binary) {
    final rows = <_RowCandidate>[];
    final minCoverage = (binary.width * 0.42).toInt();

    for (int y = 0; y < binary.height; y++) {
      int whiteCount = 0;
      int segmentCount = 0;
      int longestRun = 0;
      int currentRun = 0;
      bool inSegment = false;

      for (int x = 0; x < binary.width; x++) {
        final pixel = binary.getPixel(x, y);
        final isInk = img.getLuminance(pixel) > 200;
        if (isInk) {
          whiteCount++;
          currentRun++;
          if (!inSegment) {
            segmentCount++;
            inSegment = true;
          }
        } else {
          if (currentRun > longestRun) longestRun = currentRun;
          currentRun = 0;
          inSegment = false;
        }
      }

      if (currentRun > longestRun) longestRun = currentRun;

      final coverage = whiteCount / binary.width;
      final longestRunRatio = longestRun / binary.width;
      final fragmentationPenalty =
          ((segmentCount - 1).clamp(0, 18)).toDouble() / 18.0;
      final continuity =
          (longestRunRatio * 0.70 +
                  coverage * 0.30 -
                  fragmentationPenalty * 0.30)
              .clamp(0.0, 1.0)
              .toDouble();

      if (whiteCount >= minCoverage &&
          coverage >= 0.42 &&
          longestRunRatio >= 0.34 &&
          continuity >= 0.52 &&
          segmentCount <= 18) {
        rows.add(
          _RowCandidate(
            y: y,
            coverage: coverage,
            longestRunRatio: longestRunRatio,
            continuity: continuity,
          ),
        );
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

  List<Map<String, dynamic>> _buildValidatedStaffs(
    List<double> lines,
    Map<int, _RowCandidate> metricsByY,
    List<dynamic> symbolDetections,
  ) {
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

      if (avgSpacing < 6 || avgSpacing > 40) {
        continue;
      }

      final isConsistent = spacings.every(
        (s) => (s - avgSpacing).abs() <= avgSpacing * 0.22,
      );

      print(
        'SEGMENT FALLBACK WINDOW: $candidate spacings=$spacings avg=$avgSpacing consistent=$isConsistent',
      );

      if (!isConsistent) continue;

      final lineMetrics = candidate.map((line) {
        final center = line.round();
        return metricsByY[center] ??
            metricsByY[center - 1] ??
            metricsByY[center + 1] ??
            const _RowCandidate(
              y: -1,
              coverage: 0,
              longestRunRatio: 0,
              continuity: 0,
            );
      }).toList();

      final avgCoverage =
          lineMetrics.map((item) => item.coverage).reduce((a, b) => a + b) /
              lineMetrics.length;
      final avgRun = lineMetrics
              .map((item) => item.longestRunRatio)
              .reduce((a, b) => a + b) /
          lineMetrics.length;
      final avgContinuity =
          lineMetrics.map((item) => item.continuity).reduce((a, b) => a + b) /
              lineMetrics.length;

      if (avgCoverage < 0.42 || avgRun < 0.34 || avgContinuity < 0.52) {
        continue;
      }

      final symbolSupport = _symbolSupportForStaff(
        lines: candidate,
        spacing: avgSpacing,
        symbolDetections: symbolDetections,
      );

      if (symbolDetections.isNotEmpty &&
          symbolSupport <= 0 &&
          avgCoverage < 0.72) {
        continue;
      }

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
        'validatedStaffSpacing': avgSpacing,
        'locked': true,
        'coordinateSpace': 'original_image',
        'topBoundary': topBoundary,
        'bottomBoundary': bottomBoundary,
        'confidence': 0.72,
        'matchedLineCount': 5,
        'repairedLineCount': 0,
        'projectionStrength': avgCoverage,
        'continuity': avgContinuity,
        'symbolSupport': symbolSupport,
      });

      for (int offset = 0; offset < 5; offset++) {
        used.add(i + offset);
      }
    }

    return staffs;
  }

  double _symbolSupportForStaff({
    required List<double> lines,
    required double spacing,
    required List<dynamic> symbolDetections,
  }) {
    if (symbolDetections.isEmpty) return 0.0;

    final top = lines.first - spacing * 3.0;
    final bottom = lines.last + spacing * 3.0;
    double support = 0;

    for (final item in symbolDetections) {
      if (item is! Map) continue;
      final className =
          (item['className'] ?? item['labelName'] ?? item['label'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
      if (!{
        'notehead',
        'treble_clef',
        'bass_clef',
        'sharp',
        'flat',
        'natural',
      }.contains(className)) {
        continue;
      }

      final centerY = _symbolCenterY(item);
      if (centerY == null || centerY < top || centerY > bottom) continue;

      if (className == 'treble_clef' || className == 'bass_clef') {
        support += 0.28;
      } else if (className == 'notehead') {
        support += 0.08;
      } else {
        support += 0.05;
      }
    }

    return support.clamp(0.0, 1.0).toDouble();
  }

  double? _symbolCenterY(Map<dynamic, dynamic> item) {
    final direct = item['centerY'] ?? item['y'];
    if (direct is num) return direct.toDouble();
    final parsed = double.tryParse(direct?.toString() ?? '');
    if (parsed != null) return parsed;

    final bbox = item['bbox'];
    if (bbox is! List || bbox.length < 4) return null;
    final y1 = bbox[1] is num
        ? (bbox[1] as num).toDouble()
        : double.tryParse(bbox[1].toString());
    final y2 = bbox[3] is num
        ? (bbox[3] as num).toDouble()
        : double.tryParse(bbox[3].toString());
    if (y1 == null || y2 == null) return null;
    return (y1 + y2) / 2.0;
  }
}

class _RowCandidate {
  final int y;
  final double coverage;
  final double longestRunRatio;
  final double continuity;

  const _RowCandidate({
    required this.y,
    required this.coverage,
    required this.longestRunRatio,
    required this.continuity,
  });
}
