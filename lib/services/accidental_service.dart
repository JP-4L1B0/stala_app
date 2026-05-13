import '../dummy_page.dart';

enum AccidentalType { sharp, flat, natural, none }

class AccidentalResult {
  final String pitch;
  final AccidentalType accidental;
  final String source;

  const AccidentalResult({
    required this.pitch,
    required this.accidental,
    required this.source,
  });
}

class AccidentalService {
  AccidentalResult applyDirectAccidental({
    required String basePitch,
    required SymbolClassItem notehead,
    required List<SymbolClassItem> symbolsInStaff,
    required double spacing,
  }) {
    final accidentals = symbolsInStaff.where((symbol) {
      final name = symbol.className.trim().toLowerCase();

      final isAccidental =
          name == 'sharp' || name == 'flat' || name == 'natural';

      if (!isAccidental) return false;

      final isLeftOfNote = symbol.x < notehead.x;
      final horizontalDistance = notehead.x - symbol.x;
      final verticallyClose = (notehead.y - symbol.y).abs() <= spacing * 0.8;

      final closeEnough = horizontalDistance <= spacing * 3.0;

      return isLeftOfNote && closeEnough && verticallyClose;
    }).toList()..sort((a, b) => b.x.compareTo(a.x)); // nearest left first

    if (accidentals.isEmpty) {
      return AccidentalResult(
        pitch: basePitch,
        accidental: AccidentalType.none,
        source: 'none',
      );
    }

    final accidental = accidentals.first;
    final accidentalName = accidental.className.trim().toLowerCase();

    if (accidentalName == 'sharp') {
      return AccidentalResult(
        pitch: _applySharp(basePitch),
        accidental: AccidentalType.sharp,
        source: 'direct',
      );
    }

    if (accidentalName == 'flat') {
      return AccidentalResult(
        pitch: _applyFlat(basePitch),
        accidental: AccidentalType.flat,
        source: 'direct',
      );
    }

    return AccidentalResult(
      pitch: _applyNatural(basePitch),
      accidental: AccidentalType.natural,
      source: 'direct',
    );
  }

  AccidentalResult applyMeasureAwareAccidental({
    required String basePitch,
    required SymbolClassItem notehead,
    required List<SymbolClassItem> symbolsInStaff,
    required double spacing,
    double? measureStartX,
    double? measureEndX,
  }) {
    final accidentals = symbolsInStaff.where((symbol) {
      final name = symbol.className.trim().toLowerCase();
      final isAccidental =
          name == 'sharp' || name == 'flat' || name == 'natural';
      if (!isAccidental) return false;

      final isLeftOfNote = symbol.x < notehead.x;
      if (!isLeftOfNote) return false;

      final insideMeasureStart =
          measureStartX == null || symbol.x >= measureStartX;
      final insideMeasureEnd = measureEndX == null || symbol.x <= measureEndX;
      if (!insideMeasureStart || !insideMeasureEnd) return false;

      final verticallySamePitch =
          (notehead.y - symbol.y).abs() <= spacing * 0.8;

      return verticallySamePitch;
    }).toList()..sort((a, b) => b.x.compareTo(a.x));

    if (accidentals.isEmpty) {
      return AccidentalResult(
        pitch: basePitch,
        accidental: AccidentalType.none,
        source: 'none',
      );
    }

    final accidental = accidentals.first;
    final horizontalDistance = notehead.x - accidental.x;
    final source = horizontalDistance <= spacing * 3.0
        ? 'direct'
        : 'measure_carry';

    final accidentalName = accidental.className.trim().toLowerCase();

    if (accidentalName == 'sharp') {
      return AccidentalResult(
        pitch: _applySharp(basePitch),
        accidental: AccidentalType.sharp,
        source: source,
      );
    }

    if (accidentalName == 'flat') {
      return AccidentalResult(
        pitch: _applyFlat(basePitch),
        accidental: AccidentalType.flat,
        source: source,
      );
    }

    return AccidentalResult(
      pitch: _applyNatural(basePitch),
      accidental: AccidentalType.natural,
      source: source,
    );
  }

  String _applySharp(String pitch) {
    final parsed = _parsePitch(pitch);
    if (parsed == null) return pitch;

    final letter = parsed.$1;
    final octave = parsed.$3;

    return '$letter#$octave';
  }

  String _applyFlat(String pitch) {
    final parsed = _parsePitch(pitch);
    if (parsed == null) return pitch;

    final letter = parsed.$1;
    final octave = parsed.$3;

    return '${letter}b$octave';
  }

  String _applyNatural(String pitch) {
    final parsed = _parsePitch(pitch);
    if (parsed == null) return pitch;

    final letter = parsed.$1;
    final octave = parsed.$3;

    return '$letter$octave';
  }

  (String, String, String)? _parsePitch(String pitch) {
    final match = RegExp(r'^([A-G])([#b]?)(-?\d+)$').firstMatch(pitch);
    if (match == null) return null;

    final letter = match.group(1);
    final accidental = match.group(2);
    final octave = match.group(3);

    if (letter == null || accidental == null || octave == null) return null;

    return (letter, accidental, octave);
  }
}
