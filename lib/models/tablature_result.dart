enum TranslationMode {
  strict,
  continuity,
  chordAware,
  unknown,
}

TranslationMode translationModeFromString(dynamic value) {
  return TranslationMode.values.firstWhere(
        (mode) => mode.name == value?.toString(),
    orElse: () => TranslationMode.unknown,
  );
}

class TablatureResult {
  final String title;
  final TranslationMode mode;
  final String sourceLineId;
  final List<TablatureEvent> events;

  const TablatureResult({
    required this.title,
    required this.mode,
    required this.sourceLineId,
    required this.events,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'mode': mode.name,
    'sourceLineId': sourceLineId,
    'events': events.map((e) => e.toJson()).toList(),
  };

  factory TablatureResult.fromJson(Map<String, dynamic> json) {
    return TablatureResult(
      title: json['title']?.toString() ?? 'Untitled',
      mode: translationModeFromString(json['mode']),
      sourceLineId: json['sourceLineId']?.toString() ?? '',
      events: (json['events'] as List? ?? const [])
          .map((item) {
        return TablatureEvent.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
      })
          .toList(),
    );
  }
}

class TablatureEvent {
  final int eventIndex;
  final String label;
  final double durationSeconds;
  final List<TabPosition> positions;
  final Map<String, dynamic> metadata;

  const TablatureEvent({
    required this.eventIndex,
    required this.label,
    required this.durationSeconds,
    required this.positions,
    this.metadata = const {},
  });

  bool get isRest => positions.isEmpty;
  bool get isChord => positions.length > 1;

  Map<String, dynamic> toJson() => {
    'eventIndex': eventIndex,
    'label': label,
    'durationSeconds': durationSeconds,
    'positions': positions.map((p) => p.toJson()).toList(),
    'metadata': metadata,
  };

  factory TablatureEvent.fromJson(Map<String, dynamic> json) {
    return TablatureEvent(
      eventIndex: (json['eventIndex'] as num?)?.toInt() ?? 0,
      label: json['label']?.toString() ?? '',
      durationSeconds: (json['durationSeconds'] as num?)?.toDouble() ?? 1.0,
      positions: (json['positions'] as List? ?? const [])
          .map((item) {
        return TabPosition.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
      })
          .toList(),
      metadata: Map<String, dynamic>.from(json['metadata'] ?? const {}),
    );
  }
}

class TabPosition {
  final int stringNumber; // 6 = Low E, 1 = High E
  final int fret;
  final String pitch;

  const TabPosition({
    required this.stringNumber,
    required this.fret,
    required this.pitch,
  });

  Map<String, dynamic> toJson() => {
    'stringNumber': stringNumber,
    'fret': fret,
    'pitch': pitch,
  };

  factory TabPosition.fromJson(Map<String, dynamic> json) {
    return TabPosition(
      stringNumber: (json['stringNumber'] as num?)?.toInt() ?? 1,
      fret: (json['fret'] as num?)?.toInt() ?? 0,
      pitch: json['pitch']?.toString() ?? '',
    );
  }
}