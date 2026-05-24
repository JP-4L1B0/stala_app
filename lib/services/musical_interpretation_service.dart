import 'polyphonic_to_monophonic_service.dart';

enum InterpretedMusicType { grandStaff, trebleOnly }

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
  final InterpretedMusicLine grandStaffLine;
  final InterpretedMusicLine trebleOnlyLine;

  const MusicalInterpretationResult({
    required this.grandStaffLine,
    required this.trebleOnlyLine,
  });
}

class MusicalInterpretationService {
  MusicalInterpretationResult interpret({
    required List<PolyphonicToMonophonicResult> polyMonoResults,
  }) {
    final grandStaffEvents = <InterpretedMusicEvent>[];
    final trebleOnlyEvents = <InterpretedMusicEvent>[];

    int globalGrandStaffIndex = 0;
    int globalTrebleOnlyIndex = 0;

    for (final result in polyMonoResults) {
      for (final stack in result.chordAwareStacks) {
        final label = stack.chordName ?? _fallbackStackLabel(stack);

        grandStaffEvents.add(
          InterpretedMusicEvent(
            eventIndex: globalGrandStaffIndex++,
            sourceGrandStaffId: result.grandStaffId,
            type: InterpretedMusicType.grandStaff,
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
        trebleOnlyEvents.add(
          InterpretedMusicEvent(
            eventIndex: globalTrebleOnlyIndex++,
            sourceGrandStaffId: result.grandStaffId,
            type: InterpretedMusicType.trebleOnly,
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
      grandStaffLine: InterpretedMusicLine(
        id: 'normalized_grand_staff',
        title: 'Grand Staff',
        type: InterpretedMusicType.grandStaff,
        events: grandStaffEvents,
      ),
      trebleOnlyLine: InterpretedMusicLine(
        id: 'normalized_treble_only',
        title: 'Treble Only',
        type: InterpretedMusicType.trebleOnly,
        events: trebleOnlyEvents,
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
