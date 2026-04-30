import '../dummy_page.dart';

enum ResolvedClef {
  treble,
  bass,
  unknown,
}

class StaffClefResult {
  final String staffId;
  final ResolvedClef clef;
  final double? confidence;
  final String source;

  const StaffClefResult({
    required this.staffId,
    required this.clef,
    this.confidence,
    required this.source,
  });

  String get label {
    switch (clef) {
      case ResolvedClef.treble:
        return 'Treble clef';
      case ResolvedClef.bass:
        return 'Bass clef';
      case ResolvedClef.unknown:
        return 'Unknown clef';
    }
  }
}

class ClefResolutionService {
  List<StaffClefResult> resolveClefs({
    required List<SymbolClassItem> classItems,
    required Map<String, List<double>> staffLineGroups,
  }) {
    final results = <StaffClefResult>[];

    staffLineGroups.forEach((staffId, lines) {
      final top = lines.first;
      final bottom = lines.last;
      final spacing = _averageSpacing(lines);

      final extendedTop = top - spacing * 1.5;
      final extendedBottom = bottom + spacing * 1.5;

      final clefCandidates = classItems.where((item) {
        final name = item.className.trim().toLowerCase();
        final isClef = name == 'treble_clef' || name == 'bass_clef';
        final insideStaffY = item.y >= extendedTop && item.y <= extendedBottom;
        return isClef && insideStaffY;
      }).toList()
        ..sort((a, b) => a.x.compareTo(b.x));

      if (clefCandidates.isEmpty) {
        results.add(
          StaffClefResult(
            staffId: staffId,
            clef: ResolvedClef.unknown,
            confidence: null,
            source: 'missing',
          ),
        );
        return;
      }

      final clefSymbol = clefCandidates.first;
      final name = clefSymbol.className.trim().toLowerCase();

      results.add(
        StaffClefResult(
          staffId: staffId,
          clef: name == 'bass_clef' ? ResolvedClef.bass : ResolvedClef.treble,
          confidence: clefSymbol.score,
          source: 'detected',
        ),
      );
    });

    return results;
  }

  double _averageSpacing(List<double> lines) {
    if (lines.length < 2) return 0;

    double total = 0;
    for (int i = 0; i < lines.length - 1; i++) {
      total += lines[i + 1] - lines[i];
    }

    return total / (lines.length - 1);
  }
}