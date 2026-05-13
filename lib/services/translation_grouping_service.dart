import '../models/translation_group_models.dart';
import '../dummy_page.dart';
import 'clef_resolution_service.dart';
import 'pitch_mapping_service.dart';
import 'accidental_service.dart';
import 'key_signature_service.dart';

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

  final ClefResolutionService _clefResolutionService = ClefResolutionService();
  final PitchMappingService _pitchMappingService = PitchMappingService();
  final AccidentalService _accidentalService = AccidentalService();
  final KeySignatureService _keySignatureService = KeySignatureService();

  static const int _virtualLedgerSteps = 5;
  static const double _virtualLedgerPadding = 0.75;

  List<StaffTranslateGroup> buildGroups({
    required List<SymbolClassItem> classItems,
    required List<dynamic> staffLines,
    List<dynamic> validatedStaffs = const [],
    List<dynamic> ledgerLines = const [],
    List<dynamic> measures = const [],
  }) {
    final staffGeometries = _normalizeStaffGeometries(
      validatedStaffs: validatedStaffs,
      staffLines: staffLines,
    );
    final normalizedLedgerLines = _normalizeLedgerLines(ledgerLines);
    final measureRegions = _normalizeMeasures(measures);

    if (staffGeometries.isEmpty) {
      return const [];
    }

    final staffLineMap = <String, List<double>>{
      for (final geometry in staffGeometries) geometry.staffId: geometry.lines,
    };

    final clefResults = _clefResolutionService.resolveClefs(
      classItems: classItems,
      staffLineGroups: staffLineMap,
    );

    final clefByStaffId = {
      for (final result in clefResults) result.staffId: result,
    };

    final result = <StaffTranslateGroup>[];

    for (final geometry in staffGeometries) {
      final staffId = geometry.staffId;
      final clefResult = clefByStaffId[staffId];

      final lines = geometry.lines;
      if (lines.length < 5) continue;

      final segmentMap = _buildSegmentMap(lines);

      final topBoundary = geometry.topBoundary ?? _computeTopBoundary(lines);
      final bottomBoundary =
          geometry.bottomBoundary ?? _computeBottomBoundary(lines);
      final spacing = geometry.spacing ?? _averageSpacing(lines);

      final extendedTopBoundary =
          lines.first -
          (spacing * (_virtualLedgerSteps + _virtualLedgerPadding));

      final extendedBottomBoundary =
          lines.last +
          (spacing * (_virtualLedgerSteps + _virtualLedgerPadding));

      final symbolsInStaff = classItems.where((item) {
        final className = item.className.trim().toLowerCase();

        final insideNormalStaff =
            item.y >= topBoundary && item.y <= bottomBoundary;

        final insideVirtualExtension =
            item.y >= extendedTopBoundary && item.y <= extendedBottomBoundary;

        if (insideNormalStaff) return true;

        if (className == 'notehead' && insideVirtualExtension) {
          return true;
        }

        return false;
      }).toList()..sort((a, b) => a.x.compareTo(b.x));

      final keySignature = _keySignatureService.resolveKeySignature(
        staffId: staffId,
        symbolsInStaff: symbolsInStaff,
        spacing: spacing,
      );

      final staffRole = _resolveStaffRole(clefResult?.label);

      final translatedSymbols = symbolsInStaff.map((item) {
        final location = _findNearestSegment(item.y, segmentMap);
        final measure = _measureForSymbol(
          symbol: item,
          staffId: staffId,
          measures: measureRegions,
        );

        // Computes pitch
        final pitch = item.className.trim().toLowerCase() == 'notehead'
            ? _pitchMappingService.resolvePitch(
                segment: location,
                clef: clefResult?.clef ?? ResolvedClef.unknown,
              )
            : null;

        final pitchWithKey = pitch != null
            ? _keySignatureService.applyToPitch(
                pitch: pitch,
                keySignature: keySignature,
              )
            : null;

        // Add accidental effect to pitch
        final isNotehead = item.className.trim().toLowerCase() == 'notehead';

        final accidentalResult = isNotehead && pitchWithKey != null
            ? _accidentalService.applyMeasureAwareAccidental(
                basePitch: pitchWithKey,
                notehead: item,
                symbolsInStaff: symbolsInStaff,
                spacing: spacing,
                measureStartX: measure?.x1,
                measureEndX: measure?.x2,
              )
            : null;

        // Ledger line
        final insideNormalStaff =
            item.y >= topBoundary && item.y <= bottomBoundary;

        String assignmentStatus;

        if (insideNormalStaff) {
          assignmentStatus = 'normal';
        } else {
          final confirmed =
              _isNearLedgerLine(
                symbol: item,
                staffId: staffId,
                ledgerLines: normalizedLedgerLines,
                spacing: spacing,
              ) ||
              _isSupportedLedgerSpace(
                location: location,
                symbol: item,
                staffId: staffId,
                ledgerLines: normalizedLedgerLines,
                spacing: spacing,
              );

          assignmentStatus = confirmed ? 'ledgerConfirmed' : 'ledgerCandidate';
        }

        return TranslatedSymbolViewItem(
          className: item.className,
          centerX: item.x,
          centerY: item.y,
          score: item.score,
          bbox: item.bbox,
          staffId: staffId,
          staffRole: staffRole,
          locationId: location.id,
          locationType: location.type,
          assignmentStatus: assignmentStatus,
          measureId: measure?.id,
          measureIndex: measure?.indexInStaff,
          defaultKeyLabel: accidentalResult?.pitch,
          accidentalState:
              accidentalResult?.accidental.name ??
              _defaultAccidentalState(item.className),
        );
      }).toList();

      result.add(
        StaffTranslateGroup(
          staffId: staffId,
          summary: StaffSummary(
            lineCount: lines.length,
            symbolCount: translatedSymbols.length,
            clefStatusLabel:
                '${clefResult?.label ?? 'Unknown clef'} • ${keySignature.label}',
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

  List<_StaffGeometry> _normalizeStaffGeometries({
    required List<dynamic> validatedStaffs,
    required List<dynamic> staffLines,
  }) {
    final fromValidated = <_StaffGeometry>[];

    for (final item in validatedStaffs) {
      if (item is! Map) continue;

      final map = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );

      final staffId = map['id']?.toString();
      final rawLines = map['lines'];
      if (staffId == null || rawLines is! List) continue;

      final lines = rawLines.map(_toDouble).whereType<double>().toList()
        ..sort();

      if (lines.length != 5) continue;

      fromValidated.add(
        _StaffGeometry(
          staffId: staffId,
          lines: lines,
          spacing: _toDouble(map['spacing']),
          topBoundary: _toDouble(map['topBoundary']),
          bottomBoundary: _toDouble(map['bottomBoundary']),
        ),
      );
    }

    if (fromValidated.isNotEmpty) {
      fromValidated.sort((a, b) => a.lines.first.compareTo(b.lines.first));
      return fromValidated;
    }

    final normalizedLines = _normalizeStaffLines(staffLines);
    if (normalizedLines.length < 5) return const [];

    final grouped = _buildStaffLineGroups(normalizedLines);
    return grouped.asMap().entries.map((entry) {
      final staffId = 'staff_${entry.key}';
      final lines = entry.value;
      return _StaffGeometry(
        staffId: staffId,
        lines: lines,
        spacing: _averageSpacing(lines),
        topBoundary: _computeTopBoundary(lines),
        bottomBoundary: _computeBottomBoundary(lines),
      );
    }).toList();
  }

  List<_LedgerLineItem> _normalizeLedgerLines(List<dynamic> rawLedgerLines) {
    final result = <_LedgerLineItem>[];

    for (final item in rawLedgerLines) {
      if (item is! Map) continue;

      final map = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );

      final staffId = map['staffId']?.toString();
      final x1 = _toDouble(map['x1']);
      final x2 = _toDouble(map['x2']);
      final y = _toDouble(map['y']);
      final position = map['position']?.toString() ?? 'unknown';

      if (staffId == null || x1 == null || x2 == null || y == null) continue;

      result.add(
        _LedgerLineItem(
          staffId: staffId,
          x1: x1,
          x2: x2,
          y: y,
          position: position,
        ),
      );
    }

    return result;
  }

  List<_MeasureRegion> _normalizeMeasures(List<dynamic> rawMeasures) {
    final result = <_MeasureRegion>[];

    for (final item in rawMeasures) {
      if (item is! Map) continue;

      final map = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );

      final id = map['id']?.toString();
      final staffId = map['staffId']?.toString();
      final indexInStaff = _toInt(map['indexInStaff']);
      final x1 = _toDouble(map['x1']);
      final x2 = _toDouble(map['x2']);

      if (id == null ||
          staffId == null ||
          indexInStaff == null ||
          x1 == null ||
          x2 == null) {
        continue;
      }

      result.add(
        _MeasureRegion(
          id: id,
          staffId: staffId,
          indexInStaff: indexInStaff,
          x1: x1,
          x2: x2,
        ),
      );
    }

    return result;
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

    final spacing = _averageSpacing(lines);

    const aboveVirtualMap = {
      1: 'G / B',
      2: 'A / C',
      3: 'B / D',
      4: 'C / E',
      5: 'D / F',
    };

    const belowVirtualMap = {
      1: 'D / F',
      2: 'C / E',
      3: 'B / D',
      4: 'A / C',
      5: 'G / B',
    };

    // Virtual lines above staff
    for (int i = _virtualLedgerSteps; i >= 1; i--) {
      final lineY = lines.first - (spacing * i);
      final spaceY = lines.first - (spacing * (i - 0.5));

      items.insert(
        0,
        SegmentMapItem(
          id: 'v_line_above_$i',
          type: 'virtual_line',
          centerY: lineY,
          defaultKeyLabel: aboveVirtualMap[i] ?? 'virtual',
        ),
      );

      items.insert(
        0,
        SegmentMapItem(
          id: 'v_space_above_$i',
          type: 'virtual_space',
          centerY: spaceY,
          defaultKeyLabel: 'virtual',
        ),
      );
    }

    // Virtual lines below staff
    for (int i = 1; i <= _virtualLedgerSteps; i++) {
      final spaceY = lines.last + (spacing * (i - 0.5));
      final lineY = lines.last + (spacing * i);

      items.add(
        SegmentMapItem(
          id: 'v_space_below_$i',
          type: 'virtual_space',
          centerY: spaceY,
          defaultKeyLabel: 'virtual',
        ),
      );

      items.add(
        SegmentMapItem(
          id: 'v_line_below_$i',
          type: 'virtual_line',
          centerY: lineY,
          defaultKeyLabel: belowVirtualMap[i] ?? 'virtual',
        ),
      );
    }

    items.sort((a, b) => a.centerY.compareTo(b.centerY));
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

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  _MeasureRegion? _measureForSymbol({
    required SymbolClassItem symbol,
    required String staffId,
    required List<_MeasureRegion> measures,
  }) {
    final staffMeasures =
        measures.where((measure) => measure.staffId == staffId).toList()
          ..sort((a, b) => a.x1.compareTo(b.x1));

    for (final measure in staffMeasures) {
      final inside = symbol.x >= measure.x1 && symbol.x <= measure.x2;
      if (inside) return measure;
    }

    return null;
  }

  bool _isNearLedgerLine({
    required SymbolClassItem symbol,
    required String staffId,
    required List<_LedgerLineItem> ledgerLines,
    required double spacing,
  }) {
    final xTolerance = spacing * 0.95;
    final yTolerance = spacing * 0.8;

    for (final ledger in ledgerLines) {
      if (ledger.staffId != staffId) continue;

      final yClose = (symbol.y - ledger.y).abs() <= yTolerance;

      final symbolLeft = symbol.bbox != null
          ? symbol.bbox![0]
          : symbol.x - spacing;
      final symbolRight = symbol.bbox != null
          ? symbol.bbox![2]
          : symbol.x + spacing;

      final xOverlaps =
          symbolRight >= (ledger.x1 - xTolerance) &&
          symbolLeft <= (ledger.x2 + xTolerance);

      final ledgerCenterX = (ledger.x1 + ledger.x2) / 2.0;
      final centerClose = (symbol.x - ledgerCenterX).abs() <= spacing * 1.6;

      if (yClose && xOverlaps && centerClose) {
        return true;
      }
    }

    return false;
  }

  bool _isSupportedLedgerSpace({
    required SegmentMapItem location,
    required SymbolClassItem symbol,
    required String staffId,
    required List<_LedgerLineItem> ledgerLines,
    required double spacing,
  }) {
    if (location.type != 'virtual_space') return false;

    final adjacentToStaff =
        location.id == 'v_space_above_1' || location.id == 'v_space_below_1';
    if (adjacentToStaff) return true;

    return ledgerLines.any((ledger) {
      if (ledger.staffId != staffId) return false;

      final yClose = (symbol.y - ledger.y).abs() <= spacing * 1.35;
      final symbolLeft = symbol.bbox != null
          ? symbol.bbox![0]
          : symbol.x - spacing;
      final symbolRight = symbol.bbox != null
          ? symbol.bbox![2]
          : symbol.x + spacing;

      final xTolerance = spacing * 1.1;
      final xOverlaps =
          symbolRight >= ledger.x1 - xTolerance &&
          symbolLeft <= ledger.x2 + xTolerance;

      return yClose && xOverlaps;
    });
  }

  String _resolveStaffRole(String? clefLabel) {
    final label = clefLabel?.toLowerCase() ?? '';

    if (label.contains('treble')) return 'treble';
    if (label.contains('bass')) return 'bass';

    return 'unknown';
  }
}

class _StaffGeometry {
  final String staffId;
  final List<double> lines;
  final double? spacing;
  final double? topBoundary;
  final double? bottomBoundary;

  const _StaffGeometry({
    required this.staffId,
    required this.lines,
    this.spacing,
    this.topBoundary,
    this.bottomBoundary,
  });
}

class _LedgerLineItem {
  final String staffId;
  final double x1;
  final double x2;
  final double y;
  final String position;

  const _LedgerLineItem({
    required this.staffId,
    required this.x1,
    required this.x2,
    required this.y,
    required this.position,
  });
}

class _MeasureRegion {
  final String id;
  final String staffId;
  final int indexInStaff;
  final double x1;
  final double x2;

  const _MeasureRegion({
    required this.id,
    required this.staffId,
    required this.indexInStaff,
    required this.x1,
    required this.x2,
  });
}
