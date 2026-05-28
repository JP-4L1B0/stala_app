import 'event_manager_service.dart';
import 'rhythm_interpretation_service.dart';
import '../models/tablature_result.dart';

class TablatureResultAdapter {
  const TablatureResultAdapter();

  List<TablatureResult> fromEventManagerResult({
    required EventManagerResult result,
    RhythmInterpretationResult? rhythmResult,
    String titleFallback = 'Untitled',
  }) {
    return result.lines.map((line) {
      return TablatureResult(
        title: line.title.isNotEmpty ? line.title : titleFallback,
        mode: _modeFromLineId(line.sourceLineId),
        sourceLineId: line.sourceLineId,
        events: line.events
            .map((event) => _fromPlayableEvent(event, rhythmResult))
            .toList(),
      );
    }).toList();
  }

  List<TablatureResult> combine({
    EventManagerResult? eventManagerResult,
    RhythmInterpretationResult? rhythmResult,
    String titleFallback = 'Untitled',
  }) {
    return [
      if (eventManagerResult != null)
        ...fromEventManagerResult(
          result: eventManagerResult,
          rhythmResult: rhythmResult,
          titleFallback: titleFallback,
        ),
    ];
  }

  TablatureEvent _fromPlayableEvent(
    PlayableEvent event,
    RhythmInterpretationResult? rhythmResult,
  ) {
    final duration = _durationFor(
      rhythmResult: rhythmResult,
      measureIndex: event.measureIndex,
      sourceX: event.sourceX,
      fallback: _defaultDurationForMelody(event),
    );

    return TablatureEvent(
      eventIndex: event.eventIndex,
      label: event.label,
      durationSeconds: duration,
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
        'measureId': event.measureId,
        'measureIndex': event.measureIndex,
        'sourceX': event.sourceX,
        'durationBeats': duration,
      },
    );
  }

  TranslationMode _modeFromLineId(String id) {
    final normalized = id.toLowerCase();

    if (normalized.contains('strict')) {
      return TranslationMode.trebleOnly;
    }

    if (normalized.contains('treble')) {
      return TranslationMode.trebleOnly;
    }

    if (normalized.contains('grand') || normalized.contains('chord')) {
      return TranslationMode.grandStaff;
    }

    return TranslationMode.unknown;
  }

  double _defaultDurationForMelody(PlayableEvent event) {
    return 1.0;
  }

  double _durationFor({
    required RhythmInterpretationResult? rhythmResult,
    required int? measureIndex,
    required double? sourceX,
    required double fallback,
  }) {
    if (rhythmResult == null) return fallback;
    return rhythmResult.durationFor(
      measureIndex: measureIndex,
      sourceX: sourceX,
      fallback: fallback,
    );
  }
}
