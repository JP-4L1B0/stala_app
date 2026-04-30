// Translation Group Model

class StaffSummary {
  final int lineCount;
  final int symbolCount;
  final String clefStatusLabel;

  const StaffSummary({
    required this.lineCount,
    required this.symbolCount,
    required this.clefStatusLabel,
  });
}

class SegmentMapItem {
  final String id; // line_0, space_0, etc.
  final String type; // line or space

  /// For lines, this is the center y.
  final double centerY;

  /// For spaces, these are useful. For lines, they may be null.
  final double? startY;
  final double? endY;

  /// Default mapping while clef is unresolved.
  /// Example: "F / A"
  final String defaultKeyLabel;

  const SegmentMapItem({
    required this.id,
    required this.type,
    required this.centerY,
    this.startY,
    this.endY,
    required this.defaultKeyLabel,
  });

  String get yDisplay {
    if (type == 'line') {
      return 'y: ${centerY.toStringAsFixed(1)} px';
    }

    if (startY != null && endY != null) {
      return 'y: ${startY!.toStringAsFixed(1)}-${endY!.toStringAsFixed(1)} px';
    }

    return 'y: ${centerY.toStringAsFixed(1)} px';
  }
}

class TranslatedSymbolViewItem {
  final String className;
  final double centerX;
  final double centerY;
  final double? score;
  final List<double>? bbox;
  final String staffId;
  final String staffRole; // treble, bass, unknown

  /// line_0, space_1, etc.
  final String locationId;

  /// "line" or "space"
  final String locationType;

  /// assign status to detected notes
  final String assignmentStatus;

  /// Default displayed translation for noteheads while accidental rules
  /// are not yet applied. For non-noteheads, keep null.
  final String? defaultKeyLabel;

  /// Reserved for future accidental application and note rewriting.
  /// Example future values:
  /// - sharp
  /// - flat
  /// - natural
  /// - sharp_applied
  /// - natural_cancelled
  final String? accidentalState;

  const TranslatedSymbolViewItem({
    required this.className,
    required this.centerX,
    required this.centerY,
    this.score,
    this.bbox,
    required this.staffId,
    required this.staffRole,
    required this.locationId,
    required this.locationType,
    required this.assignmentStatus,
    this.defaultKeyLabel,
    this.accidentalState,
  });

  String get centerDisplay =>
      '(${centerX.toStringAsFixed(1)}, ${centerY.toStringAsFixed(1)})';
}

class StaffTranslateGroup {
  final String staffId;
  final StaffSummary summary;
  final List<SegmentMapItem> segmentMap;
  final List<TranslatedSymbolViewItem> symbols;

  const StaffTranslateGroup({
    required this.staffId,
    required this.summary,
    required this.segmentMap,
    required this.symbols,
  });
}