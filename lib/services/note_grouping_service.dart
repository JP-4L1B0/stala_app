import '../models/translation_group_models.dart';

class NoteGroupingService {
  Map<String, List<List<TranslatedSymbolViewItem>>> groupNotes({
    required List<StaffTranslateGroup> staffGroups,
  }) {
    final result = <String, List<List<TranslatedSymbolViewItem>>>{};

    for (final staff in staffGroups) {
      final staffId = staff.staffId;

      // Step 1: filter valid noteheads
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

      // Step 2: sort left → right
      notes.sort((a, b) => a.centerX.compareTo(b.centerX));

      // Step 3: estimate spacing (used for grouping threshold)
      final spacing = _estimateSpacing(notes);

      final threshold = spacing * 0.35;

      // Step 4: group notes
      final groups = <List<TranslatedSymbolViewItem>>[];
      List<TranslatedSymbolViewItem> currentGroup = [];

      for (final note in notes) {
        if (currentGroup.isEmpty) {
          currentGroup.add(note);
          continue;
        }

        final last = currentGroup.last;

        final dx = (note.centerX - last.centerX).abs();

        if (dx <= threshold) {
          // same chord
          currentGroup.add(note);
        } else {
          // new group
          groups.add(currentGroup);
          currentGroup = [note];
        }
      }

      // add last group
      if (currentGroup.isNotEmpty) {
        groups.add(currentGroup);
      }

      result[staffId] = groups;
    }

    return result;
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
}