import 'musical_interpretation_service.dart';

class GuitarPosition {
  final int stringNumber; // 1 = high E, 6 = low E
  final int fret;
  final String pitch;

  const GuitarPosition({
    required this.stringNumber,
    required this.fret,
    required this.pitch,
  });
}

class FretboardCandidate {
  final String label;
  final List<GuitarPosition> positions;

  const FretboardCandidate({
    required this.label,
    required this.positions,
  });
}

class FretboardMappedEvent {
  final int eventIndex;
  final String label;
  final List<String> pitches;
  final List<FretboardCandidate> candidates;

  const FretboardMappedEvent({
    required this.eventIndex,
    required this.label,
    required this.pitches,
    required this.candidates,
  });
}

class FretboardMappedLine {
  final String id;
  final String title;
  final List<FretboardMappedEvent> events;

  const FretboardMappedLine({
    required this.id,
    required this.title,
    required this.events,
  });
}

class FretboardMappingResult {
  final List<FretboardMappedLine> lines;

  const FretboardMappingResult({
    required this.lines,
  });
}

class FretboardMappingService {
  static const int maxFret = 24;

  // Standard tuning:
  // string 1 = high E4, string 6 = low E2
  static const Map<int, int> _openStringMidi = {
    1: 64, // E4
    2: 59, // B3
    3: 55, // G3
    4: 50, // D3
    5: 45, // A2
    6: 40, // E2
  };

  FretboardMappingResult mapInterpretation({
    required MusicalInterpretationResult interpretation,
  }) {
    final lines = [
      _mapLine(interpretation.chordAwareLine),
      _mapLine(interpretation.strictMelodyLine),
      _mapLine(interpretation.continuityMelodyLine),
    ];

    return FretboardMappingResult(lines: lines);
  }

  FretboardMappedLine _mapLine(InterpretedMusicLine line) {
    return FretboardMappedLine(
      id: line.id,
      title: line.title,
      events: line.events.map(_mapEvent).toList(),
    );
  }

  FretboardMappedEvent _mapEvent(InterpretedMusicEvent event) {
    final candidates = <FretboardCandidate>[];

    if (event.pitches.length == 1) {
      final pitch = event.pitches.first;
      final positions = _positionsForPitch(pitch);

      for (final pos in positions) {
        candidates.add(
          FretboardCandidate(
            label: '${pos.pitch}: S${pos.stringNumber} F${pos.fret}',
            positions: [pos],
          ),
        );
      }
    } else {
      candidates.addAll(_multiPitchCandidates(event));
    }

    return FretboardMappedEvent(
      eventIndex: event.eventIndex,
      label: event.label,
      pitches: event.pitches,
      candidates: candidates,
    );
  }

  List<GuitarPosition> _positionsForPitch(String pitch) {
    final midi = _pitchToMidiValue(pitch);
    if (midi == null) return const [];

    final positions = <GuitarPosition>[];

    for (final entry in _openStringMidi.entries) {
      final stringNumber = entry.key;
      final openMidi = entry.value;
      final fret = midi - openMidi;

      if (fret >= 0 && fret <= maxFret) {
        positions.add(
          GuitarPosition(
            stringNumber: stringNumber,
            fret: fret,
            pitch: pitch,
          ),
        );
      }
    }

    positions.sort((a, b) {
      final fretCompare = a.fret.compareTo(b.fret);
      if (fretCompare != 0) return fretCompare;
      return a.stringNumber.compareTo(b.stringNumber);
    });

    return positions;
  }

  List<FretboardCandidate> _multiPitchCandidates(
      InterpretedMusicEvent event,
      ) {
    final pitchPositions = event.pitches.map((pitch) {
      return _positionsForPitch(pitch);
    }).toList();

    if (pitchPositions.any((list) => list.isEmpty)) {
      return const [];
    }

    final combinations = <List<GuitarPosition>>[];

    void build(int index, List<GuitarPosition> current) {
      if (index == pitchPositions.length) {
        final usedStrings = current.map((p) => p.stringNumber).toSet();

        // Cannot play two pitches on the same string at the same time.
        if (usedStrings.length != current.length) return;

        if (!_isPlayableShape(current)) return;

        combinations.add(List<GuitarPosition>.from(current));
        return;
      }

      for (final pos in pitchPositions[index]) {
        build(index + 1, [...current, pos]);
      }
    }

    build(0, []);

    return combinations.map((combo) {
      final label = combo
          .map((p) => '${p.pitch}: S${p.stringNumber} F${p.fret}')
          .join(' | ');

      return FretboardCandidate(
        label: label,
        positions: combo,
      );
    }).toList();
  }

  bool _isPlayableShape(List<GuitarPosition> positions) {
    if (positions.isEmpty) return false;

    final fretted = positions.where((p) => p.fret > 0).toList();
    if (fretted.isEmpty) return true;

    final minFret = fretted.map((p) => p.fret).reduce((a, b) => a < b ? a : b);
    final maxFret = fretted.map((p) => p.fret).reduce((a, b) => a > b ? a : b);

    final fretSpan = maxFret - minFret;

    // Base playable range. EventManager/A* can optimize later.
    return fretSpan <= 5;
  }

  int? _pitchToMidiValue(String pitch) {
    final match = RegExp(r'^([A-G])([#b]?)(-?\d+)$').firstMatch(pitch);
    if (match == null) return null;

    final letter = match.group(1)!;
    final accidental = match.group(2) ?? '';
    final octave = int.tryParse(match.group(3) ?? '');
    if (octave == null) return null;

    const baseSemitones = {
      'C': 0,
      'D': 2,
      'E': 4,
      'F': 5,
      'G': 7,
      'A': 9,
      'B': 11,
    };

    var semitone = baseSemitones[letter];
    if (semitone == null) return null;

    if (accidental == '#') semitone += 1;
    if (accidental == 'b') semitone -= 1;

    return ((octave + 1) * 12) + semitone;
  }
}