import '../models/translation_group_models.dart';

class NoteGroupingService {
  Map<String, List<List<TranslatedSymbolViewItem>>> groupNotes({
    required List<StaffTranslateGroup> staffGroups,
  }) {
    final result = <String, List<List<TranslatedSymbolViewItem>>>{};

    for (final staff in staffGroups) {
      final staffId = staff.staffId;

      final notes = staff.symbols.where((symbol) {
        final isNotehead = symbol.className.toLowerCase() == 'notehead';
        final isValid =
            symbol.assignmentStatus == 'normal' ||
            symbol.assignmentStatus == 'ledgerConfirmed';

        return isNotehead && isValid;
      }).toList();

      if (notes.isEmpty) {
        result[staffId] = [];
        continue;
      }

      notes.sort((a, b) {
        final measureCompare = (a.measureIndex ?? 0).compareTo(
          b.measureIndex ?? 0,
        );
        if (measureCompare != 0) return measureCompare;
        return a.centerX.compareTo(b.centerX);
      });

      final groups = <List<TranslatedSymbolViewItem>>[];

      for (final measureNotes in _groupByMeasure(notes)) {
        final spacing = _estimateSpacing(measureNotes);
        final noteheadWidth = _estimateNoteheadWidth(measureNotes);
        // default
        //final threshold = (noteheadWidth * 0.9).clamp(6.0, spacing * 0.45);

        // safe
        //final maxThreshold = spacing * 0.45;
        //final safeMax = maxThreshold < 6.0 ? 6.0 : maxThreshold;
        //final threshold = (noteheadWidth * 0.9).clamp(6.0, safeMax);

        // might be better
        final adaptiveThreshold = noteheadWidth * 0.9;
        final spacingLimit = spacing * 0.45;

        final threshold =
        spacingLimit <= 6.0
            ? 6.0
            : adaptiveThreshold.clamp(6.0, spacingLimit);

        List<TranslatedSymbolViewItem> currentGroup = [];

        for (final note in measureNotes) {
          if (currentGroup.isEmpty) {
            currentGroup.add(note);
            continue;
          }

          final center =
              currentGroup.map((item) => item.centerX).reduce((a, b) => a + b) /
              currentGroup.length;

          final dx = (note.centerX - center).abs();

          if (dx <= threshold) {
            currentGroup.add(note);
          } else {
            groups.add(currentGroup);
            currentGroup = [note];
          }
        }

        if (currentGroup.isNotEmpty) {
          groups.add(currentGroup);
        }
      }

      result[staffId] = groups;
    }

    return result;
  }

  List<List<TranslatedSymbolViewItem>> _groupByMeasure(
    List<TranslatedSymbolViewItem> notes,
  ) {
    final keyed = <String, List<TranslatedSymbolViewItem>>{};

    for (final note in notes) {
      final key = note.measureId ?? 'implicit';
      keyed.putIfAbsent(key, () => []).add(note);
    }

    final groups = keyed.values.toList();
    groups.sort((a, b) {
      final aIndex = a.first.measureIndex ?? 0;
      final bIndex = b.first.measureIndex ?? 0;
      if (aIndex != bIndex) return aIndex.compareTo(bIndex);
      return a.first.centerX.compareTo(b.first.centerX);
    });

    return groups;
  }

  double _estimateSpacing(List<TranslatedSymbolViewItem> notes) {
    if (notes.length < 2) return 20.0;

    double total = 0;
    int count = 0;

    for (int i = 0; i < notes.length - 1; i++) {
      final dx = (notes[i + 1].centerX - notes[i].centerX).abs();

      if (dx > 0) {
        total += dx;
        count++;
      }
    }

    if (count == 0) return 20.0;

    return total / count;
  }

  double _estimateNoteheadWidth(List<TranslatedSymbolViewItem> notes) {
    final widths =
        notes
            .map((note) {
              final bbox = note.bbox;
              if (bbox == null || bbox.length < 4) return null;
              return (bbox[2] - bbox[0]).abs();
            })
            .whereType<double>()
            .where((width) => width > 0)
            .toList()
          ..sort();

    if (widths.isEmpty) return 12.0;

    return widths[widths.length ~/ 2];
  }
}
