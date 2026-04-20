import '../models/translation_group_models.dart';
import '../dummy_page.dart';

class TranslationGroupingService {
  /// Builds staff_n groups using segmented staff lines and detected symbols.
  ///
  /// Current behavior:
  /// - groups every 5 detected staff lines into one staff_n
  /// - creates line_0 to line_4 and space_0 to space_3
  /// - assigns symbols to the nearest staff group
  /// - assigns each symbol to nearest line/space segment
  /// - shows default note mapping like "F / A" while clef detection and
  ///   accidental rules are still pending
  ///
  /// Future-ready notes:
  /// - accidentalState is reserved for accidental logic
  /// - clefStatusLabel is reserved for real clef resolution
  /// - defaultKeyLabel can later be replaced by resolved pitch output
  List<StaffTranslateGroup> buildGroups({
    required List<SymbolClassItem> classItems,
    required List<dynamic> staffLines,
  }) {
    final normalizedLines = _normalizeStaffLines(staffLines);
    if (normalizedLines.length < 5) {
      return const [];
    }

    final staffGroups = _buildStaffLineGroups(normalizedLines);
    final result = <StaffTranslateGroup>[];

    for (int staffIndex = 0; staffIndex < staffGroups.length; staffIndex++) {
      final lines = staffGroups[staffIndex];
      if (lines.length < 5) continue;

      final segmentMap = _buildSegmentMap(lines);

      final topBoundary = _computeTopBoundary(lines);
      final bottomBoundary = _computeBottomBoundary(lines);

      final symbolsInStaff = classItems
          .where((item) => item.y >= topBoundary && item.y <= bottomBoundary)
          .toList()
        ..sort((a, b) => a.x.compareTo(b.x));

      final translatedSymbols = symbolsInStaff.map((item) {
        final location = _findNearestSegment(item.y, segmentMap);

        return TranslatedSymbolViewItem(
          className: item.className,
          centerX: item.x,
          centerY: item.y,
          score: item.score,
          bbox: item.bbox,
          locationId: location.id,
          locationType: location.type,
          defaultKeyLabel:
          item.className.trim().toLowerCase() == 'notehead'
              ? location.defaultKeyLabel
              : null,
          accidentalState: _defaultAccidentalState(item.className),
        );
      }).toList();

      result.add(
        StaffTranslateGroup(
          staffId: 'staff_$staffIndex',
          summary: StaffSummary(
            lineCount: lines.length,
            symbolCount: translatedSymbols.length,
            clefStatusLabel: 'Clef pending — showing default F / A mapping',
          ),
          segmentMap: segmentMap,
          symbols: translatedSymbols,
        ),
      );
    }

    return result;
  }

  List<double> _normalizeStaffLines(List<dynamic> rawStaffLines) {
    final values = <double>[];

    for (final item in rawStaffLines) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(
          item.map((key, value) => MapEntry(key.toString(), value)),
        );

        final y = _toDouble(map['y']);
        if (y != null) {
          values.add(y);
        }
      } else {
        final y = _toDouble(item);
        if (y != null) {
          values.add(y);
        }
      }
    }

    values.sort();
    return values;
  }

  List<List<double>> _buildStaffLineGroups(List<double> lines) {
    final grouped = <List<double>>[];

    for (int i = 0; i < lines.length; i += 5) {
      final end = (i + 5 < lines.length) ? i + 5 : lines.length;
      final chunk = lines.sublist(i, end);

      if (chunk.length == 5) {
        grouped.add(chunk);
      }
    }

    return grouped;
  }

  List<SegmentMapItem> _buildSegmentMap(List<double> lines) {
    final items = <SegmentMapItem>[];

    const lineLabels = ['line_0', 'line_1', 'line_2', 'line_3', 'line_4'];
    const spaceLabels = ['space_0', 'space_1', 'space_2', 'space_3'];

    const defaultMap = [
      'F / A',
      'E / G',
      'D / F',
      'C / E',
      'B / D',
      'A / C',
      'G / B',
      'F / A',
      'E / G',
    ];

    // line_0
    items.add(
      SegmentMapItem(
        id: lineLabels[0],
        type: 'line',
        centerY: lines[0],
        defaultKeyLabel: defaultMap[0],
      ),
    );

    // space_0, line_1, ...
    for (int i = 0; i < 4; i++) {
      final spaceStart = lines[i];
      final spaceEnd = lines[i + 1];
      final spaceCenter = (spaceStart + spaceEnd) / 2.0;

      items.add(
        SegmentMapItem(
          id: spaceLabels[i],
          type: 'space',
          centerY: spaceCenter,
          startY: spaceStart,
          endY: spaceEnd,
          defaultKeyLabel: defaultMap[(i * 2) + 1],
        ),
      );

      items.add(
        SegmentMapItem(
          id: lineLabels[i + 1],
          type: 'line',
          centerY: lines[i + 1],
          defaultKeyLabel: defaultMap[(i * 2) + 2],
        ),
      );
    }

    return items;
  }

  SegmentMapItem _findNearestSegment(
      double symbolY,
      List<SegmentMapItem> segmentMap,
      ) {
    SegmentMapItem nearest = segmentMap.first;
    double minDistance = (symbolY - nearest.centerY).abs();

    for (final item in segmentMap.skip(1)) {
      final dist = (symbolY - item.centerY).abs();
      if (dist < minDistance) {
        minDistance = dist;
        nearest = item;
      }
    }

    return nearest;
  }

  double _computeTopBoundary(List<double> lines) {
    final spacing = _averageSpacing(lines);
    return lines.first - (spacing * 0.8);
  }

  double _computeBottomBoundary(List<double> lines) {
    final spacing = _averageSpacing(lines);
    return lines.last + (spacing * 0.8);
  }

  double _averageSpacing(List<double> lines) {
    if (lines.length < 2) return 0;
    double total = 0;

    for (int i = 0; i < lines.length - 1; i++) {
      total += (lines[i + 1] - lines[i]);
    }

    return total / (lines.length - 1);
  }

  String? _defaultAccidentalState(String className) {
    final key = className.trim().toLowerCase();
    if (key == 'sharp' || key == 'flat' || key == 'natural') {
      return key;
    }
    return null;
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}