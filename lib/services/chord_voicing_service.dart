import 'fretboard_mapping_service.dart';

class ChordVoicedEvent {
  final int eventIndex;
  final String label;
  final String? measureId;
  final int? measureIndex;
  final double? sourceX;
  final List<GuitarPosition> chosenPositions;
  final double cost;
  final String voicingReason;

  const ChordVoicedEvent({
    required this.eventIndex,
    required this.label,
    this.measureId,
    this.measureIndex,
    this.sourceX,
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

  const ChordVoicingResult({required this.lines});
}

class ChordVoicingService {
  ChordVoicingResult voice({required FretboardMappingResult fretboardMapping}) {
    final lines = fretboardMapping.lines
        .where((line) => line.id.contains('chord'))
        .map(_voiceLine)
        .whereType<ChordVoicingLine>()
        .toList();

    return ChordVoicingResult(lines: lines);
  }

  ChordVoicingLine? _voiceLine(FretboardMappedLine line) {
    final sourceEvents = line.events
        .where((event) => event.candidates.isNotEmpty)
        .toList();
    if (sourceEvents.isEmpty) return null;

    final path = _findLowestCostPath(sourceEvents);
    if (path.isEmpty) return null;

    final voicedEvents = <ChordVoicedEvent>[];

    for (int i = 0; i < path.length; i++) {
      final event = sourceEvents[i];
      final current = path[i];
      final previous = i > 0 ? path[i - 1] : null;
      final transition = previous == null
          ? 0.0
          : _transitionCost(previous, current);
      final cost = _scoreCandidate(current).cost + transition;

      voicedEvents.add(
        ChordVoicedEvent(
          eventIndex: event.eventIndex,
          label: event.label,
          measureId: event.measureId,
          measureIndex: event.measureIndex,
          sourceX: event.sourceX,
          chosenPositions: current.positions,
          cost: cost,
          voicingReason: _reasonFor(current, previous),
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

  List<FretboardCandidate> _findLowestCostPath(
    List<FretboardMappedEvent> events,
  ) {
    final dp = <Map<int, _PathState>>[];

    final firstStates = <int, _PathState>{};
    for (int i = 0; i < events.first.candidates.length; i++) {
      final candidate = events.first.candidates[i];
      firstStates[i] = _PathState(
        cost: _scoreCandidate(candidate).cost,
        previousIndex: null,
      );
    }
    dp.add(firstStates);

    for (int eventIndex = 1; eventIndex < events.length; eventIndex++) {
      final previousCandidates = events[eventIndex - 1].candidates;
      final currentCandidates = events[eventIndex].candidates;
      final currentStates = <int, _PathState>{};

      for (
        int currentIndex = 0;
        currentIndex < currentCandidates.length;
        currentIndex++
      ) {
        final current = currentCandidates[currentIndex];
        final localCost = _scoreCandidate(current).cost;
        double bestCost = double.infinity;
        int? bestPreviousIndex;

        for (
          int previousIndex = 0;
          previousIndex < previousCandidates.length;
          previousIndex++
        ) {
          final previousState = dp[eventIndex - 1][previousIndex];
          if (previousState == null) continue;

          final previous = previousCandidates[previousIndex];
          final cost =
              previousState.cost +
              localCost +
              _transitionCost(previous, current);

          if (cost < bestCost) {
            bestCost = cost;
            bestPreviousIndex = previousIndex;
          }
        }

        currentStates[currentIndex] = _PathState(
          cost: bestCost,
          previousIndex: bestPreviousIndex,
        );
      }

      dp.add(currentStates);
    }

    final lastStates = dp.last;
    int? bestFinalIndex;
    double bestFinalCost = double.infinity;

    for (final entry in lastStates.entries) {
      if (entry.value.cost < bestFinalCost) {
        bestFinalCost = entry.value.cost;
        bestFinalIndex = entry.key;
      }
    }

    if (bestFinalIndex == null) return const [];

    final path = List<FretboardCandidate?>.filled(events.length, null);
    int? currentIndex = bestFinalIndex;

    for (int eventIndex = events.length - 1; eventIndex >= 0; eventIndex--) {
      if (currentIndex == null) break;
      path[eventIndex] = events[eventIndex].candidates[currentIndex];
      currentIndex = dp[eventIndex][currentIndex]?.previousIndex;
    }

    return path.whereType<FretboardCandidate>().toList();
  }

  double _transitionCost(
    FretboardCandidate previous,
    FretboardCandidate current,
  ) {
    final previousCenter = _candidateCenter(previous);
    final currentCenter = _candidateCenter(current);

    final fretDistance = (currentCenter.fret - previousCenter.fret).abs();
    final stringDistance =
        (currentCenter.stringNumber - previousCenter.stringNumber).abs();
    final currentSpan = _fretSpan(current.positions);
    final openCount = current.positions.where((p) => p.fret == 0).length;

    double cost = 0;
    cost += fretDistance * 4.0;
    cost += stringDistance * 2.0;
    cost += currentSpan * 3.0;

    if (fretDistance > 5) cost += 20;
    if (fretDistance > 9) cost += 40;
    if (stringDistance == 0) cost -= 2;
    cost -= openCount * 1.0;

    return cost;
  }

  String _reasonFor(FretboardCandidate current, FretboardCandidate? previous) {
    final localReason = _scoreCandidate(current).reason;
    if (previous == null) return '$localReason+path_start';

    final transition = _transitionCost(previous, current);
    if (transition <= 8) return '$localReason+smooth_transition';
    if (transition <= 20) return '$localReason+reachable_transition';
    return '$localReason+larger_shift';
  }

  _CandidateCenter _candidateCenter(FretboardCandidate candidate) {
    final positions = candidate.positions;
    if (positions.isEmpty) {
      return const _CandidateCenter(stringNumber: 3, fret: 0);
    }

    final averageString =
        positions.map((p) => p.stringNumber).reduce((a, b) => a + b) /
        positions.length;
    final averageFret =
        positions.map((p) => p.fret).reduce((a, b) => a + b) / positions.length;

    return _CandidateCenter(
      stringNumber: averageString.round(),
      fret: averageFret.round(),
    );
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

    final minFret = fretted.map((p) => p.fret).reduce((a, b) => a < b ? a : b);

    final maxFret = fretted.map((p) => p.fret).reduce((a, b) => a > b ? a : b);

    return maxFret - minFret;
  }

  double _averageFret(List<GuitarPosition> positions) {
    if (positions.isEmpty) return 999;

    return positions.map((p) => p.fret).reduce((a, b) => a + b) /
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

class _PathState {
  final double cost;
  final int? previousIndex;

  const _PathState({required this.cost, required this.previousIndex});
}

class _CandidateCenter {
  final int stringNumber;
  final int fret;

  const _CandidateCenter({required this.stringNumber, required this.fret});
}
