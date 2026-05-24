import '../dummy_page.dart';

class BarlineRefinementResult {
  final List<Map<String, dynamic>> barLines;
  final List<Map<String, dynamic>> measures;

  const BarlineRefinementResult({
    required this.barLines,
    required this.measures,
  });
}

class BarlineRefinementService {
  const BarlineRefinementService();

  BarlineRefinementResult refine({
    required List<dynamic> rawBarLines,
    required List<dynamic> rawMeasures,
    required List<dynamic> rawValidatedStaffs,
    required List<SymbolClassItem> classItems,
    List<dynamic> rawStems = const [],
  }) {
    final barLines = _normalizeMaps(rawBarLines);
    if (barLines.isEmpty) {
      return BarlineRefinementResult(
        barLines: const [],
        measures: _normalizeMaps(rawMeasures),
      );
    }

    final staffOrder = _staffOrder(rawValidatedStaffs);
    final staffs = _normalizeMaps(rawValidatedStaffs);
    final stems = _normalizeMaps(rawStems);
    final noteheads = classItems
        .where((item) => item.className.trim().toLowerCase() == 'notehead')
        .toList();

    final kept = <Map<String, dynamic>>[];

    for (final barLine in barLines) {
      final alignedAcrossGrandStaff = _hasAdjacentStaffAlignment(
        barLine: barLine,
        barLines: barLines,
        staffOrder: staffOrder,
      );

      final spansGrandStaff = _spansGrandStaff(
        barLine: barLine,
        staffs: staffs,
        staffOrder: staffOrder,
      );

      final attachedToNotehead = _hasAttachedNotehead(
        barLine: barLine,
        noteheads: noteheads,
      );

      final overlapsStem = _overlapsStem(barLine: barLine, stems: stems);
      if (staffOrder.length < 2) {
        if (!attachedToNotehead && !overlapsStem) kept.add(barLine);
        continue;
      }

      final singleStaffOnly = _existsOnlyInsideSingleStaff(
        barLine: barLine,
        staffs: staffs,
      );

      if (!spansGrandStaff && !alignedAcrossGrandStaff) continue;
      if (attachedToNotehead || overlapsStem) continue;
      if (!alignedAcrossGrandStaff && singleStaffOnly) continue;

      kept.add(barLine);
    }

    return BarlineRefinementResult(
      barLines: kept,
      measures: _rebuildMeasures(
        barLines: kept,
        rawMeasures: rawMeasures,
        rawValidatedStaffs: rawValidatedStaffs,
      ),
    );
  }

  bool _hasAdjacentStaffAlignment({
    required Map<String, dynamic> barLine,
    required List<Map<String, dynamic>> barLines,
    required List<String> staffOrder,
  }) {
    if (staffOrder.length < 2) return false;

    final staffId = barLine['staffId']?.toString();
    final staffIndex = staffOrder.indexOf(staffId ?? '');
    final x = _toDouble(barLine['x']);
    if (staffIndex < 0 || x == null) return false;

    return barLines.any((other) {
      final otherStaffIndex = staffOrder.indexOf(
        other['staffId']?.toString() ?? '',
      );
      final otherX = _toDouble(other['x']);
      final otherY1 = _toDouble(other['y1']);
      final otherY2 = _toDouble(other['y2']);
      if (otherStaffIndex < 0 || otherX == null) return false;

      return (otherStaffIndex - staffIndex).abs() == 1 &&
          (otherX - x).abs() <= 8.0 &&
          otherY1 != null &&
          otherY2 != null &&
          otherY2 > otherY1;
    });
  }

  bool _spansGrandStaff({
    required Map<String, dynamic> barLine,
    required List<Map<String, dynamic>> staffs,
    required List<String> staffOrder,
  }) {
    if (staffOrder.length < 2) return true;

    final staffId = barLine['staffId']?.toString();
    final index = staffOrder.indexOf(staffId ?? '');
    if (index < 0) return false;

    final pairedIndex = index.isEven ? index + 1 : index - 1;
    if (pairedIndex < 0 || pairedIndex >= staffOrder.length) return false;

    final first = _staffById(staffs, staffOrder[index]);
    final second = _staffById(staffs, staffOrder[pairedIndex]);
    final y1 = _toDouble(barLine['y1']);
    final y2 = _toDouble(barLine['y2']);
    if (first == null || second == null || y1 == null || y2 == null) {
      return false;
    }

    final firstTop = _toDouble(first['topBoundary']) ?? _staffTop(first);
    final secondTop = _toDouble(second['topBoundary']) ?? _staffTop(second);
    final firstBottom =
        _toDouble(first['bottomBoundary']) ?? _staffBottom(first);
    final secondBottom =
        _toDouble(second['bottomBoundary']) ?? _staffBottom(second);
    if (firstTop == null ||
        secondTop == null ||
        firstBottom == null ||
        secondBottom == null) {
      return false;
    }

    final top = firstTop < secondTop ? firstTop : secondTop;
    final bottom = firstBottom > secondBottom ? firstBottom : secondBottom;

    return y1 <= top + 10.0 && y2 >= bottom - 10.0;
  }

  bool _existsOnlyInsideSingleStaff({
    required Map<String, dynamic> barLine,
    required List<Map<String, dynamic>> staffs,
  }) {
    final y1 = _toDouble(barLine['y1']);
    final y2 = _toDouble(barLine['y2']);
    if (y1 == null || y2 == null) return true;

    var crossingCount = 0;
    for (final staff in staffs) {
      final top = _toDouble(staff['topBoundary']) ?? _staffTop(staff);
      final bottom = _toDouble(staff['bottomBoundary']) ?? _staffBottom(staff);
      if (top == null || bottom == null) continue;
      if (y2 >= top && y1 <= bottom) crossingCount++;
    }

    return crossingCount <= 1;
  }

  bool _overlapsStem({
    required Map<String, dynamic> barLine,
    required List<Map<String, dynamic>> stems,
  }) {
    final x = _toDouble(barLine['x']);
    final y1 = _toDouble(barLine['y1']);
    final y2 = _toDouble(barLine['y2']);
    if (x == null || y1 == null || y2 == null) return false;

    return stems.any((stem) {
      final stemX = _toDouble(stem['x']);
      final stemY1 = _toDouble(stem['y1']);
      final stemY2 = _toDouble(stem['y2']);
      if (stemX == null || stemY1 == null || stemY2 == null) return false;
      return (stemX - x).abs() <= 4.0 && stemY2 >= y1 - 8 && stemY1 <= y2 + 8;
    });
  }

  bool _hasAttachedNotehead({
    required Map<String, dynamic> barLine,
    required List<SymbolClassItem> noteheads,
  }) {
    final x = _toDouble(barLine['x']);
    final y1 = _toDouble(barLine['y1']);
    final y2 = _toDouble(barLine['y2']);
    if (x == null || y1 == null || y2 == null) return false;

    return noteheads.any((notehead) {
      final bbox = notehead.bbox;
      if (bbox == null || bbox.length < 4) {
        return (notehead.x - x).abs() <= 8 &&
            notehead.y >= y1 - 12 &&
            notehead.y <= y2 + 12;
      }

      final xOverlaps = x >= bbox[0] - 6 && x <= bbox[2] + 6;
      final yOverlaps = bbox[3] >= y1 - 12 && bbox[1] <= y2 + 12;
      return xOverlaps && yOverlaps;
    });
  }

  List<Map<String, dynamic>> _rebuildMeasures({
    required List<Map<String, dynamic>> barLines,
    required List<dynamic> rawMeasures,
    required List<dynamic> rawValidatedStaffs,
  }) {
    final imageRight = _imageRight(rawMeasures, barLines);
    final staffIds = _staffOrder(rawValidatedStaffs);
    if (staffIds.isEmpty) {
      return _normalizeMaps(rawMeasures);
    }

    final measures = <Map<String, dynamic>>[];
    var measureId = 0;

    for (final staffId in staffIds) {
      final staffBars =
          barLines
              .where((bar) => bar['staffId']?.toString() == staffId)
              .toList()
            ..sort((a, b) {
              return (_toDouble(a['x']) ?? 0).compareTo(_toDouble(b['x']) ?? 0);
            });

      final boundaries = <double>[
        0,
        ...staffBars.map((bar) => _toDouble(bar['x']) ?? 0),
      ];
      if (boundaries.last < imageRight) boundaries.add(imageRight);

      for (int i = 0; i < boundaries.length - 1; i++) {
        final left = boundaries[i];
        final right = boundaries[i + 1];
        if (right - left < 12) continue;

        measures.add({
          'id': 'measure_${measureId++}',
          'staffId': staffId,
          'indexInStaff': i,
          'x1': left,
          'x2': right,
          'startBarLineId': i == 0 ? null : staffBars[i - 1]['id'],
          'endBarLineId': i < staffBars.length ? staffBars[i]['id'] : null,
          'source': 'barline_refined',
        });
      }
    }

    return measures;
  }

  List<String> _staffOrder(List<dynamic> rawValidatedStaffs) {
    final staffs = _normalizeMaps(rawValidatedStaffs);
    staffs.sort((a, b) {
      final aLines = (a['lines'] as List?) ?? const [];
      final bLines = (b['lines'] as List?) ?? const [];
      final aY = aLines.isEmpty ? 0.0 : _toDouble(aLines.first) ?? 0.0;
      final bY = bLines.isEmpty ? 0.0 : _toDouble(bLines.first) ?? 0.0;
      return aY.compareTo(bY);
    });

    return staffs
        .map((staff) => staff['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  Map<String, dynamic>? _staffById(
    List<Map<String, dynamic>> staffs,
    String staffId,
  ) {
    for (final staff in staffs) {
      if (staff['id']?.toString() == staffId) return staff;
    }
    return null;
  }

  double? _staffTop(Map<String, dynamic> staff) {
    final lines = (staff['lines'] as List?) ?? const [];
    if (lines.isEmpty) return null;
    return _toDouble(lines.first);
  }

  double? _staffBottom(Map<String, dynamic> staff) {
    final lines = (staff['lines'] as List?) ?? const [];
    if (lines.isEmpty) return null;
    return _toDouble(lines.last);
  }

  double _imageRight(
    List<dynamic> rawMeasures,
    List<Map<String, dynamic>> barLines,
  ) {
    final measureRight = _normalizeMaps(rawMeasures)
        .map((measure) => _toDouble(measure['x2']) ?? 0)
        .fold<double>(0, (max, value) => value > max ? value : max);
    final barRight = barLines
        .map((bar) => _toDouble(bar['x']) ?? 0)
        .fold<double>(0, (max, value) => value > max ? value : max);

    return [measureRight, barRight + 80, 1.0].reduce((a, b) => a > b ? a : b);
  }

  List<Map<String, dynamic>> _normalizeMaps(List<dynamic> items) {
    return items.whereType<Map>().map((item) {
      return Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
    }).toList();
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
