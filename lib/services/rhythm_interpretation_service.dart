import '../models/translation_group_models.dart';

class RhythmEvent {
  final String staffId;
  final String? measureId;
  final int? measureIndex;
  final double sourceX;
  final String label;
  final double durationBeats;
  final String timingSource;
  final double confidence;
  final bool hasStem;
  final bool hasBeam;

  const RhythmEvent({
    required this.staffId,
    this.measureId,
    this.measureIndex,
    required this.sourceX,
    required this.label,
    required this.durationBeats,
    required this.timingSource,
    required this.confidence,
    required this.hasStem,
    required this.hasBeam,
  });
}

class RhythmInterpretationResult {
  final List<RhythmEvent> events;

  const RhythmInterpretationResult({required this.events});

  RhythmEvent? nearestEvent({
    required int? measureIndex,
    required double? sourceX,
  }) {
    if (measureIndex == null || sourceX == null) return null;

    final candidates = events
        .where((event) => event.measureIndex == measureIndex)
        .toList();
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      return (a.sourceX - sourceX).abs().compareTo((b.sourceX - sourceX).abs());
    });

    return candidates.first;
  }

  double durationFor({
    required int? measureIndex,
    required double? sourceX,
    double fallback = 1.0,
  }) {
    final event = nearestEvent(measureIndex: measureIndex, sourceX: sourceX);
    if (event == null) return fallback;
    return event.durationBeats.clamp(0.25, 4.0).toDouble();
  }
}

class RhythmInterpretationService {
  const RhythmInterpretationService();

  RhythmInterpretationResult interpret({
    required Map<String, List<List<TranslatedSymbolViewItem>>> groupedNotes,
    required List<dynamic> rawStems,
    required List<dynamic> rawBeams,
  }) {
    final stems = _normalizeStems(rawStems);
    final beams = _normalizeBeams(rawBeams);
    final events = <RhythmEvent>[];

    groupedNotes.forEach((staffId, groups) {
      final orderedGroups = groups.where((group) => group.isNotEmpty).toList()
        ..sort((a, b) {
          final measureCompare = (a.first.measureIndex ?? 0).compareTo(
            b.first.measureIndex ?? 0,
          );
          if (measureCompare != 0) return measureCompare;
          return _centerX(a).compareTo(_centerX(b));
        });

      for (int i = 0; i < orderedGroups.length; i++) {
        final group = orderedGroups[i];
        final first = group.first;
        final sourceX = _centerX(group);
        final hasBeam = _hasAttachedBeam(group, beams);
        final hasStem = _hasAttachedStem(group, stems);
        final spacingDuration = _spacingDuration(
          current: group,
          next: i + 1 < orderedGroups.length ? orderedGroups[i + 1] : null,
        );

        final duration = hasBeam
            ? 0.5
            : hasStem
            ? spacingDuration.clamp(0.75, 2.0)
            : spacingDuration.clamp(1.0, 4.0);

        final timingSource = hasBeam
            ? 'beam_geometry'
            : hasStem
            ? 'stem_spacing_estimate'
            : 'spacing_estimate';

        final confidence = hasBeam
            ? 0.72
            : hasStem
            ? 0.58
            : 0.38;

        events.add(
          RhythmEvent(
            staffId: staffId,
            measureId: first.measureId,
            measureIndex: first.measureIndex,
            sourceX: sourceX,
            label: group
                .map((note) => note.defaultKeyLabel ?? 'Unresolved')
                .join(' + '),
            durationBeats: duration.toDouble(),
            timingSource: timingSource,
            confidence: confidence,
            hasStem: hasStem,
            hasBeam: hasBeam,
          ),
        );
      }
    });

    return RhythmInterpretationResult(events: events);
  }

  double _centerX(List<TranslatedSymbolViewItem> notes) {
    return notes.map((note) => note.centerX).reduce((a, b) => a + b) /
        notes.length;
  }

  double _spacingDuration({
    required List<TranslatedSymbolViewItem> current,
    required List<TranslatedSymbolViewItem>? next,
  }) {
    if (next == null) return 1.0;
    if (current.first.measureIndex != next.first.measureIndex) return 1.0;

    final currentX = _centerX(current);
    final nextX = _centerX(next);
    final dx = (nextX - currentX).abs();

    if (dx <= 18) return 0.5;
    if (dx <= 42) return 1.0;
    if (dx <= 84) return 2.0;
    return 3.0;
  }

  bool _hasAttachedStem(
    List<TranslatedSymbolViewItem> notes,
    List<_StemGeometry> stems,
  ) {
    return notes.any((note) {
      final bbox = note.bbox;
      if (bbox == null || bbox.length < 4) return false;

      return stems.any((stem) {
        if (stem.staffId != note.staffId) return false;
        final nearX = stem.x >= bbox[0] - 4 && stem.x <= bbox[2] + 4;
        final overlapsY = stem.y2 >= bbox[1] - 8 && stem.y1 <= bbox[3] + 56;
        return nearX && overlapsY;
      });
    });
  }

  bool _hasAttachedBeam(
    List<TranslatedSymbolViewItem> notes,
    List<_BeamGeometry> beams,
  ) {
    return notes.any((note) {
      return beams.any((beam) {
        if (beam.staffId != note.staffId) return false;
        final spansX =
            note.centerX >= beam.x1 - 8 && note.centerX <= beam.x2 + 8;
        final closeY = (note.centerY - beam.y).abs() <= 90;
        return spansX && closeY;
      });
    });
  }

  List<_StemGeometry> _normalizeStems(List<dynamic> rawStems) {
    return rawStems
        .whereType<Map>()
        .map((item) {
          final map = Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
          return _StemGeometry(
            staffId: map['staffId']?.toString() ?? '',
            x: _toDouble(map['x']) ?? 0,
            y1: _toDouble(map['y1']) ?? 0,
            y2: _toDouble(map['y2']) ?? 0,
          );
        })
        .where((item) => item.staffId.isNotEmpty)
        .toList();
  }

  List<_BeamGeometry> _normalizeBeams(List<dynamic> rawBeams) {
    return rawBeams
        .whereType<Map>()
        .map((item) {
          final map = Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
          return _BeamGeometry(
            staffId: map['staffId']?.toString() ?? '',
            x1: _toDouble(map['x1']) ?? 0,
            x2: _toDouble(map['x2']) ?? 0,
            y: _toDouble(map['y']) ?? 0,
          );
        })
        .where((item) => item.staffId.isNotEmpty)
        .toList();
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

class _StemGeometry {
  final String staffId;
  final double x;
  final double y1;
  final double y2;

  const _StemGeometry({
    required this.staffId,
    required this.x,
    required this.y1,
    required this.y2,
  });
}

class _BeamGeometry {
  final String staffId;
  final double x1;
  final double x2;
  final double y;

  const _BeamGeometry({
    required this.staffId,
    required this.x1,
    required this.x2,
    required this.y,
  });
}
