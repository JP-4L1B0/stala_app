import 'event_manager_service.dart';
import 'chord_voicing_service.dart';
import '../models/tablature_result.dart';

class TablatureResultAdapter {
  const TablatureResultAdapter();

  List<TablatureResult> fromEventManagerResult({
    required EventManagerResult result,
    String titleFallback = 'Untitled',
  }) {
    return result.lines.map((line) {
      return TablatureResult(
        title: line.title.isNotEmpty ? line.title : titleFallback,
        mode: _modeFromLineId(line.sourceLineId),
        sourceLineId: line.sourceLineId,
        events: line.events.map(_fromPlayableEvent).toList(),
      );
    }).toList();
  }

  List<TablatureResult> fromChordVoicingResult({
    required ChordVoicingResult result,
    String titleFallback = 'Untitled',
  }) {
    return result.lines.map((line) {
      return TablatureResult(
        title: line.title.isNotEmpty ? line.title : titleFallback,
        mode: TranslationMode.chordAware,
        sourceLineId: line.sourceLineId,
        events: line.events.map(_fromChordVoicedEvent).toList(),
      );
    }).toList();
  }

  List<TablatureResult> combine({
    EventManagerResult? eventManagerResult,
    ChordVoicingResult? chordVoicingResult,
    String titleFallback = 'Untitled',
  }) {
    return [
      if (eventManagerResult != null)
        ...fromEventManagerResult(
          result: eventManagerResult,
          titleFallback: titleFallback,
        ),
      if (chordVoicingResult != null)
        ...fromChordVoicingResult(
          result: chordVoicingResult,
          titleFallback: titleFallback,
        ),
    ];
  }

  TablatureEvent _fromPlayableEvent(PlayableEvent event) {
    return TablatureEvent(
      eventIndex: event.eventIndex,
      label: event.label,
      durationSeconds: _defaultDurationForMelody(event),
      positions: event.chosenPositions.map((p) {
        return TabPosition(
          stringNumber: p.stringNumber,
          fret: p.fret,
          pitch: p.pitch,
        );
      }).toList(),
      metadata: {
        'source': 'event_manager',
        'transitionCost': event.transitionCost,
      },
    );
  }

  TablatureEvent _fromChordVoicedEvent(ChordVoicedEvent event) {
    return TablatureEvent(
      eventIndex: event.eventIndex,
      label: event.label,
      durationSeconds: 1.0,
      positions: event.chosenPositions.map((p) {
        return TabPosition(
          stringNumber: p.stringNumber,
          fret: p.fret,
          pitch: p.pitch,
        );
      }).toList(),
      metadata: {
        'source': 'chord_voicing',
        'cost': event.cost,
        'voicingReason': event.voicingReason,
      },
    );
  }

  TranslationMode _modeFromLineId(String id) {
    final normalized = id.toLowerCase();

    if (normalized.contains('strict')) {
      return TranslationMode.strict;
    }

    if (normalized.contains('continuity')) {
      return TranslationMode.continuity;
    }

    if (normalized.contains('chord')) {
      return TranslationMode.chordAware;
    }

    return TranslationMode.unknown;
  }

  double _defaultDurationForMelody(PlayableEvent event) {
    // Temporary thesis-safe default.
    // Later, replace this with centerX/xGap-based timing if upstream data includes x positions.
    return 1.0;
  }
}