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
  }) {
    final barLines = _normalizeMaps(rawBarLines);
    if (barLines.isEmpty) {
      return BarlineRefinementResult(
        barLines: const [],
        measures: _normalizeMaps(rawMeasures),
      );
    }

    final staffOrder = _staffOrder(rawValidatedStaffs);
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

      final attachedToNotehead = _hasAttachedNotehead(
        barLine: barLine,
        noteheads: noteheads,
      );

      if (alignedAcrossGrandStaff || !attachedToNotehead) {
        kept.add(barLine);
      }
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
      if (otherStaffIndex < 0 || otherX == null) return false;

      return (otherStaffIndex - staffIndex).abs() == 1 &&
          (otherX - x).abs() <= 8.0;
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
