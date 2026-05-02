import 'fretboard_mapping_service.dart';

class PlayableEvent {
  final int eventIndex;
  final String label;
  final List<GuitarPosition> chosenPositions;
  final double transitionCost;

  const PlayableEvent({
    required this.eventIndex,
    required this.label,
    required this.chosenPositions,
    required this.transitionCost,
  });
}

class ManagedEventLine {
  final String sourceLineId;
  final String title;
  final List<PlayableEvent> events;
  final double totalCost;

  const ManagedEventLine({
    required this.sourceLineId,
    required this.title,
    required this.events,
    required this.totalCost,
  });
}

class EventManagerResult {
  final List<ManagedEventLine> lines;

  const EventManagerResult({
    required this.lines,
  });
}

class EventManagerService {
  EventManagerResult manage({
    required FretboardMappingResult fretboardMapping,
  }) {
    final lines = fretboardMapping.lines
    // For now, optimize melody lines first.
        .where((line) =>
    line.id.contains('strict') ||
        line.id.contains('continuity'))
        .map(_optimizeLine)
        .whereType<ManagedEventLine>()
        .toList();

    return EventManagerResult(lines: lines);
  }

  ManagedEventLine? _optimizeLine(FretboardMappedLine line) {
    final events = line.events
        .where((event) => event.candidates.isNotEmpty)
        .toList();

    if (events.isEmpty) return null;

    final path = _findLowestCostPath(events);
    if (path.isEmpty) return null;

    double totalCost = 0;

    final playableEvents = <PlayableEvent>[];

    for (int i = 0; i < path.length; i++) {
      final current = path[i];
      final previous = i > 0 ? path[i - 1] : null;

      final cost = previous == null
          ? _initialCandidateCost(current)
          : _transitionCost(previous, current);

      totalCost += cost;

      playableEvents.add(
        PlayableEvent(
          eventIndex: events[i].eventIndex,
          label: events[i].label,
          chosenPositions: current.positions,
          transitionCost: cost,
        ),
      );
    }

    return ManagedEventLine(
      sourceLineId: line.id,
      title: line.title,
      events: playableEvents,
      totalCost: totalCost,
    );
  }

  List<FretboardCandidate> _findLowestCostPath(
      List<FretboardMappedEvent> events,
      ) {
    final dp = <Map<int, _PathState>>[];

    // First event
    final firstStates = <int, _PathState>{};
    for (int i = 0; i < events.first.candidates.length; i++) {
      final candidate = events.first.candidates[i];

      firstStates[i] = _PathState(
        cost: _initialCandidateCost(candidate),
        previousIndex: null,
      );
    }

    dp.add(firstStates);

    // Remaining events
    for (int eventIndex = 1; eventIndex < events.length; eventIndex++) {
      final prevCandidates = events[eventIndex - 1].candidates;
      final currCandidates = events[eventIndex].candidates;

      final currStates = <int, _PathState>{};

      for (int currIndex = 0; currIndex < currCandidates.length; currIndex++) {
        final curr = currCandidates[currIndex];

        double bestCost = double.infinity;
        int? bestPrevIndex;

        for (int prevIndex = 0;
        prevIndex < prevCandidates.length;
        prevIndex++) {
          final prevState = dp[eventIndex - 1][prevIndex];
          if (prevState == null) continue;

          final prev = prevCandidates[prevIndex];

          final cost = prevState.cost + _transitionCost(prev, curr);

          if (cost < bestCost) {
            bestCost = cost;
            bestPrevIndex = prevIndex;
          }
        }

        currStates[currIndex] = _PathState(
          cost: bestCost,
          previousIndex: bestPrevIndex,
        );
      }

      dp.add(currStates);
    }

    // Find best final candidate
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

    // Backtrack
    final path = List<FretboardCandidate?>.filled(events.length, null);
    int? currentIndex = bestFinalIndex;

    for (int eventIndex = events.length - 1;
    eventIndex >= 0;
    eventIndex--) {
      if (currentIndex == null) break;

      path[eventIndex] = events[eventIndex].candidates[currentIndex];
      currentIndex = dp[eventIndex][currentIndex]?.previousIndex;
    }

    return path.whereType<FretboardCandidate>().toList();
  }

  double _initialCandidateCost(FretboardCandidate candidate) {
    final positions = candidate.positions;
    if (positions.isEmpty) return 9999;

    final avgFret =
        positions.map((p) => p.fret).reduce((a, b) => a + b) /
            positions.length;

    final span = _fretSpan(positions);
    final openCount = positions.where((p) => p.fret == 0).length;

    double cost = 0;

    // Prefer lower/mid fret starting area.
    cost += avgFret * 0.8;

    // Avoid wide chord shapes.
    cost += span * 3.0;

    // Slight reward for open strings.
    cost -= openCount * 1.5;

    return cost;
  }

  double _transitionCost(
      FretboardCandidate previous,
      FretboardCandidate current,
      ) {
    final prevCenter = _candidateCenter(previous);
    final currCenter = _candidateCenter(current);

    final fretDistance = (currCenter.fret - prevCenter.fret).abs();
    final stringDistance =
    (currCenter.stringNumber - prevCenter.stringNumber).abs();

    final currentSpan = _fretSpan(current.positions);
    final openCount = current.positions.where((p) => p.fret == 0).length;

    double cost = 0;

    cost += fretDistance * 4.0;
    cost += stringDistance * 2.0;
    cost += currentSpan * 3.0;

    // Big penalty for large jumps.
    if (fretDistance > 5) {
      cost += 20;
    }

    if (fretDistance > 9) {
      cost += 40;
    }

    // Reward staying on nearby/same string.
    if (stringDistance == 0) {
      cost -= 2;
    }

    // Slight reward for open strings.
    cost -= openCount * 1.0;

    return cost;
  }

  _CandidateCenter _candidateCenter(FretboardCandidate candidate) {
    final positions = candidate.positions;

    if (positions.isEmpty) {
      return const _CandidateCenter(stringNumber: 3, fret: 0);
    }

    final avgString =
        positions.map((p) => p.stringNumber).reduce((a, b) => a + b) /
            positions.length;

    final avgFret =
        positions.map((p) => p.fret).reduce((a, b) => a + b) /
            positions.length;

    return _CandidateCenter(
      stringNumber: avgString.round(),
      fret: avgFret.round(),
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
}

class _PathState {
  final double cost;
  final int? previousIndex;

  const _PathState({
    required this.cost,
    required this.previousIndex,
  });
}

class _CandidateCenter {
  final int stringNumber;
  final int fret;

  const _CandidateCenter({
    required this.stringNumber,
    required this.fret,
  });
}