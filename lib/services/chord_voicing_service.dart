import 'fretboard_mapping_service.dart';

class ChordVoicedEvent {
  final int eventIndex;
  final String label;
  final List<GuitarPosition> chosenPositions;
  final double cost;
  final String voicingReason;

  const ChordVoicedEvent({
    required this.eventIndex,
    required this.label,
    required this.chosenPositions,
    required this.cost,
    required this.voicingReason,
  });
}

class ChordVoicingLine {
  final String sourceLineId;
  final String title;
  final List<ChordVoicedEvent> events;

  const ChordVoicingLine({
    required this.sourceLineId,
    required this.title,
    required this.events,
  });
}

class ChordVoicingResult {
  final List<ChordVoicingLine> lines;

  const ChordVoicingResult({
    required this.lines,
  });
}

class ChordVoicingService {
  ChordVoicingResult voice({
    required FretboardMappingResult fretboardMapping,
  }) {
    final lines = fretboardMapping.lines
        .where((line) => line.id.contains('chord'))
        .map(_voiceLine)
        .whereType<ChordVoicingLine>()
        .toList();

    return ChordVoicingResult(lines: lines);
  }

  ChordVoicingLine? _voiceLine(FretboardMappedLine line) {
    final voicedEvents = <ChordVoicedEvent>[];

    for (final event in line.events) {
      if (event.candidates.isEmpty) continue;

      final best = _selectBestCandidate(event.candidates);
      if (best == null) continue;

      voicedEvents.add(
        ChordVoicedEvent(
          eventIndex: event.eventIndex,
          label: event.label,
          chosenPositions: best.candidate.positions,
          cost: best.cost,
          voicingReason: best.reason,
        ),
      );
    }

    if (voicedEvents.isEmpty) return null;

    return ChordVoicingLine(
      sourceLineId: line.id,
      title: line.title,
      events: voicedEvents,
    );
  }

  _VoicingScore? _selectBestCandidate(List<FretboardCandidate> candidates) {
    _VoicingScore? best;

    for (final candidate in candidates) {
      if (candidate.positions.isEmpty) continue;

      final score = _scoreCandidate(candidate);

      if (best == null || score.cost < best.cost) {
        best = score;
      }
    }

    return best;
  }

  _VoicingScore _scoreCandidate(FretboardCandidate candidate) {
    final positions = candidate.positions;

    final span = _fretSpan(positions);
    final avgFret = _averageFret(positions);
    final stringSpread = _stringSpread(positions);
    final openCount = positions.where((p) => p.fret == 0).length;
    final mutedGapCount = _mutedGapCount(positions);
    final hasRootInBass = _hasLowestStringRoot(candidate);

    double cost = 0;
    final reasons = <String>[];

    // 1. Compact fret span
    cost += span * 5.0;
    if (span <= 3) reasons.add('compact_shape');

    // 2. Prefer lower/mid fret region for beginner-friendliness
    cost += avgFret * 0.9;
    if (avgFret <= 5) reasons.add('low_position');

    // 3. Penalize wide string spread slightly
    cost += stringSpread * 1.5;

    // 4. Reward open strings slightly
    cost -= openCount * 1.5;
    if (openCount > 0) reasons.add('open_string_support');

    // 5. Penalize skipped/muted gaps in simple voicings
    cost += mutedGapCount * 3.0;
    if (mutedGapCount == 0) reasons.add('continuous_strings');

    // 6. Prefer root or low chord tone on lower string when possible
    if (hasRootInBass) {
      cost -= 4.0;
      reasons.add('root_in_bass');
    }

    // 7. Strong penalty for difficult shapes
    if (span > 5) {
      cost += 50;
      reasons.add('wide_span_penalty');
    }

    if (avgFret > 12) {
      cost += 25;
      reasons.add('high_position_penalty');
    }

    return _VoicingScore(
      candidate: candidate,
      cost: cost,
      reason: reasons.isEmpty ? 'best_available_shape' : reasons.join('+'),
    );
  }

  int _fretSpan(List<GuitarPosition> positions) {
    final fretted = positions.where((p) => p.fret > 0).toList();
    if (fretted.length < 2) return 0;

    final minFret = fretted
        .map((p) => p.fret)
        .reduce((a, b) => a < b ? a : b);

    final maxFret = fretted
        .map((p) => p.fret)
        .reduce((a, b) => a > b ? a : b);

    return maxFret - minFret;
  }

  double _averageFret(List<GuitarPosition> positions) {
    if (positions.isEmpty) return 999;

    return positions
        .map((p) => p.fret)
        .reduce((a, b) => a + b) /
        positions.length;
  }

  int _stringSpread(List<GuitarPosition> positions) {
    if (positions.length < 2) return 0;

    final minString = positions
        .map((p) => p.stringNumber)
        .reduce((a, b) => a < b ? a : b);

    final maxString = positions
        .map((p) => p.stringNumber)
        .reduce((a, b) => a > b ? a : b);

    return maxString - minString;
  }

  int _mutedGapCount(List<GuitarPosition> positions) {
    if (positions.length < 2) return 0;

    final strings = positions.map((p) => p.stringNumber).toList()..sort();

    int gaps = 0;
    for (int i = 0; i < strings.length - 1; i++) {
      final diff = strings[i + 1] - strings[i];

      if (diff > 1) {
        gaps += diff - 1;
      }
    }

    return gaps;
  }

  bool _hasLowestStringRoot(FretboardCandidate candidate) {
    if (candidate.positions.isEmpty) return false;

    final root = _extractRootFromLabel(candidate.label);
    if (root == null) return false;

    final sortedByLowString = [...candidate.positions]
      ..sort((a, b) => b.stringNumber.compareTo(a.stringNumber));

    final lowest = sortedByLowString.first;

    return _pitchLetter(lowest.pitch) == root;
  }

  String? _extractRootFromLabel(String label) {
    final match = RegExp(r'^([A-G])([#b]?)').firstMatch(label);
    if (match == null) return null;

    return '${match.group(1)}${match.group(2) ?? ''}';
  }

  String? _pitchLetter(String pitch) {
    final match = RegExp(r'^([A-G])([#b]?)').firstMatch(pitch);
    if (match == null) return null;

    return '${match.group(1)}${match.group(2) ?? ''}';
  }
}

class _VoicingScore {
  final FretboardCandidate candidate;
  final double cost;
  final String reason;

  const _VoicingScore({
    required this.candidate,
    required this.cost,
    required this.reason,
  });
}