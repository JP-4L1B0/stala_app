import 'fretboard_mapping_service.dart';
import 'playability_scoring_service.dart';

class PlayableEvent {
  final int eventIndex;
  final String label;
  final String? measureId;
  final int? measureIndex;
  final double? sourceX;
  final List<GuitarPosition> chosenPositions;
  final double transitionCost;

  const PlayableEvent({
    required this.eventIndex,
    required this.label,
    this.measureId,
    this.measureIndex,
    this.sourceX,
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

  const EventManagerResult({required this.lines});
}

class EventManagerService {
  final PlayabilityScoringService _playabilityScoring =
      const PlayabilityScoringService();

  EventManagerResult manage({
    required FretboardMappingResult fretboardMapping,
  }) {
    final lines = fretboardMapping.lines
        .where(
          (line) =>
              line.id.contains('treble') || line.id.contains('grand_staff'),
        )
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
          measureId: events[i].measureId,
          measureIndex: events[i].measureIndex,
          sourceX: events[i].sourceX,
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

        for (
          int prevIndex = 0;
          prevIndex < prevCandidates.length;
          prevIndex++
        ) {
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

    for (int eventIndex = events.length - 1; eventIndex >= 0; eventIndex--) {
      if (currentIndex == null) break;

      path[eventIndex] = events[eventIndex].candidates[currentIndex];
      currentIndex = dp[eventIndex][currentIndex]?.previousIndex;
    }

    return path.whereType<FretboardCandidate>().toList();
  }

  double _initialCandidateCost(FretboardCandidate candidate) {
    return _playabilityScoring.initialCandidateCost(candidate).cost;
  }

  double _transitionCost(
    FretboardCandidate previous,
    FretboardCandidate current,
  ) {
    return _playabilityScoring.transitionCost(previous, current);
  }
}

class _PathState {
  final double cost;
  final int? previousIndex;

  const _PathState({required this.cost, required this.previousIndex});
}
