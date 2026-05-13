import 'polyphonic_to_monophonic_service.dart';

enum InterpretedMusicType { chordAware, strictMelody, continuityMelody }

class InterpretedMusicEvent {
  final int eventIndex;
  final String sourceGrandStaffId;
  final InterpretedMusicType type;
  final String? measureId;
  final int? measureIndex;
  final double? sourceX;

  final String label; // display: C5, perfect fifth, E4
  final List<String> pitches; // raw pitches for F-map
  final String? quality; // major, minor, perfect fifth, etc.
  final String? root; // C, D, etc.

  const InterpretedMusicEvent({
    required this.eventIndex,
    required this.sourceGrandStaffId,
    required this.type,
    this.measureId,
    this.measureIndex,
    this.sourceX,
    required this.label,
    required this.pitches,
    this.quality,
    this.root,
  });
}

class InterpretedMusicLine {
  final String id;
  final String title;
  final InterpretedMusicType type;
  final List<InterpretedMusicEvent> events;

  const InterpretedMusicLine({
    required this.id,
    required this.title,
    required this.type,
    required this.events,
  });
}

class MusicalInterpretationResult {
  final InterpretedMusicLine chordAwareLine;
  final InterpretedMusicLine strictMelodyLine;
  final InterpretedMusicLine continuityMelodyLine;

  const MusicalInterpretationResult({
    required this.chordAwareLine,
    required this.strictMelodyLine,
    required this.continuityMelodyLine,
  });
}

class MusicalInterpretationService {
  MusicalInterpretationResult interpret({
    required List<PolyphonicToMonophonicResult> polyMonoResults,
  }) {
    final chordAwareEvents = <InterpretedMusicEvent>[];
    final strictEvents = <InterpretedMusicEvent>[];
    final continuityEvents = <InterpretedMusicEvent>[];

    int globalChordIndex = 0;
    int globalStrictIndex = 0;
    int globalContinuityIndex = 0;

    for (final result in polyMonoResults) {
      for (final stack in result.chordAwareStacks) {
        final label = stack.chordName ?? _fallbackStackLabel(stack);

        chordAwareEvents.add(
          InterpretedMusicEvent(
            eventIndex: globalChordIndex++,
            sourceGrandStaffId: result.grandStaffId,
            type: InterpretedMusicType.chordAware,
            measureId: stack.measureId,
            measureIndex: stack.measureIndex,
            sourceX: stack.sourceX,
            label: label,
            pitches: stack.notes
                .map((note) => note.defaultKeyLabel ?? 'Unresolved')
                .toList(),
            quality: stack.quality,
            root: stack.root,
          ),
        );
      }

      for (final note in result.strictMelody) {
        strictEvents.add(
          InterpretedMusicEvent(
            eventIndex: globalStrictIndex++,
            sourceGrandStaffId: result.grandStaffId,
            type: InterpretedMusicType.strictMelody,
            measureId: note.measureId,
            measureIndex: note.measureIndex,
            sourceX: note.sourceX,
            label: note.pitch,
            pitches: [note.pitch],
          ),
        );
      }

      for (final note in result.continuityMelody) {
        continuityEvents.add(
          InterpretedMusicEvent(
            eventIndex: globalContinuityIndex++,
            sourceGrandStaffId: result.grandStaffId,
            type: InterpretedMusicType.continuityMelody,
            measureId: note.measureId,
            measureIndex: note.measureIndex,
            sourceX: note.sourceX,
            label: note.pitch,
            pitches: [note.pitch],
          ),
        );
      }
    }

    return MusicalInterpretationResult(
      chordAwareLine: InterpretedMusicLine(
        id: 'normalized_chord_aware',
        title: 'Chord Version',
        type: InterpretedMusicType.chordAware,
        events: chordAwareEvents,
      ),
      strictMelodyLine: InterpretedMusicLine(
        id: 'normalized_mprio_strict',
        title: 'Simple Melody',
        type: InterpretedMusicType.strictMelody,
        events: strictEvents,
      ),
      continuityMelodyLine: InterpretedMusicLine(
        id: 'normalized_mprio_continuity',
        title: 'Smooth Melody',
        type: InterpretedMusicType.continuityMelody,
        events: continuityEvents,
      ),
    );
  }

  String _fallbackStackLabel(ChordAwareStack stack) {
    final pitches = stack.notes
        .map((note) => note.defaultKeyLabel)
        .whereType<String>()
        .where((pitch) => pitch.trim().isNotEmpty)
        .toList();

    if (pitches.isEmpty) return 'Unresolved';
    if (pitches.length == 1) return pitches.first;
    return pitches.join(' + ');
  }
}
