import 'dart:math' as math;

import 'fretboard_mapping_service.dart';

class PlayabilityScore {
  final double cost;
  final String reason;

  const PlayabilityScore({required this.cost, required this.reason});
}

class CandidateCenter {
  final int stringNumber;
  final int fret;

  const CandidateCenter({required this.stringNumber, required this.fret});
}

class PlayabilityScoringService {
  static const double severeCost = 9999;

  const PlayabilityScoringService();

  PlayabilityScore initialCandidateCost(FretboardCandidate candidate) {
    final positions = candidate.positions;
    if (positions.isEmpty) {
      return const PlayabilityScore(cost: severeCost, reason: 'empty_shape');
    }

    final avgFret = averageFret(positions);
    final span = fretSpan(positions);
    final stringSpread = stringSpreadOf(positions);
    final openCount = positions.where((p) => p.fret == 0).length;

    double cost = 0;
    final reasons = <String>[];

    cost += avgFret * 0.6;
    cost += fretRegionPenalty(positions);
    cost += handStretchPenalty(span);
    cost += stringSpread * 1.4;
    cost -= openCount * 3.0;

    if (avgFret <= 5) reasons.add('low_position');
    if (openCount > 0) reasons.add('open_string');
    if (span <= 3) reasons.add('compact_shape');
    if (positions.any((p) => p.fret > 15)) reasons.add('high_fret_discouraged');

    return PlayabilityScore(
      cost: cost,
      reason: reasons.isEmpty ? 'best_available' : reasons.join('+'),
    );
  }

  double transitionCost(
    FretboardCandidate previous,
    FretboardCandidate current,
  ) {
    final previousCenter = candidateCenter(previous);
    final currentCenter = candidateCenter(current);

    final fretDistance = (currentCenter.fret - previousCenter.fret).abs();
    final stringDistance =
        (currentCenter.stringNumber - previousCenter.stringNumber).abs();
    final currentSpan = fretSpan(current.positions);
    final openCount = current.positions.where((p) => p.fret == 0).length;

    double cost = 0;
    cost += initialCandidateCost(current).cost;
    cost += fretDistance * 4.0;
    cost += positionShiftPenalty(fretDistance);
    cost += stringDistance * 2.0;
    cost += currentSpan * 3.0;
    cost -= openCount * 1.5;

    if (stringDistance == 0) cost -= 2.0;

    return cost;
  }

  double fretRegionPenalty(List<GuitarPosition> positions) {
    double penalty = 0;
    for (final position in positions) {
      final fret = position.fret;
      if (fret == 0) {
        penalty -= 4.0;
      } else if (fret <= 5) {
        penalty += fret * 0.3;
      } else if (fret <= 10) {
        penalty += 8.0 + ((fret - 5) * 1.8);
      } else if (fret <= 15) {
        penalty += 26.0 + ((fret - 10) * 4.0);
      } else {
        penalty += 65.0 + ((fret - 15) * 10.0);
      }
    }
    return penalty;
  }

  double handStretchPenalty(int fretSpan) {
    if (fretSpan <= 3) return fretSpan * 1.5;
    if (fretSpan <= 5) return 6.0 + ((fretSpan - 3) * 8.0);
    return 50.0 + ((fretSpan - 5) * 18.0);
  }

  double positionShiftPenalty(int fretDistance) {
    if (fretDistance <= 2) return fretDistance * 1.5;
    if (fretDistance <= 5) return 4.0 + ((fretDistance - 2) * 5.0);
    if (fretDistance <= 9) return 24.0 + ((fretDistance - 5) * 10.0);
    return 70.0 + ((fretDistance - 9) * 18.0);
  }

  CandidateCenter candidateCenter(FretboardCandidate candidate) {
    final positions = candidate.positions;
    if (positions.isEmpty) {
      return const CandidateCenter(stringNumber: 3, fret: 0);
    }

    final avgString =
        positions.map((p) => p.stringNumber).reduce((a, b) => a + b) /
        positions.length;
    final avgFret =
        positions.map((p) => p.fret).reduce((a, b) => a + b) /
        positions.length;

    return CandidateCenter(
      stringNumber: avgString.round(),
      fret: avgFret.round(),
    );
  }

  int fretSpan(List<GuitarPosition> positions) {
    final fretted = positions.where((p) => p.fret > 0).toList();
    if (fretted.length < 2) return 0;

    final minFret = fretted.map((p) => p.fret).reduce(math.min);
    final maxFret = fretted.map((p) => p.fret).reduce(math.max);
    return maxFret - minFret;
  }

  double averageFret(List<GuitarPosition> positions) {
    if (positions.isEmpty) return severeCost;
    return positions.map((p) => p.fret).reduce((a, b) => a + b) /
        positions.length;
  }

  int stringSpreadOf(List<GuitarPosition> positions) {
    if (positions.length < 2) return 0;
    final minString = positions.map((p) => p.stringNumber).reduce(math.min);
    final maxString = positions.map((p) => p.stringNumber).reduce(math.max);
    return maxString - minString;
  }
}
