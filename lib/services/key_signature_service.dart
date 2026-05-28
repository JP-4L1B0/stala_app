import '../dummy_page.dart';

enum KeySignatureAccidental {
  sharp,
  flat,
  none,
}

class KeySignatureResult {
  final String staffId;
  final int count;
  final KeySignatureAccidental accidentalType;
  final List<String> alteredSteps;
  final String label;

  const KeySignatureResult({
    required this.staffId,
    required this.count,
    required this.accidentalType,
    required this.alteredSteps,
    required this.label,
  });

  factory KeySignatureResult.none(String staffId) {
    return KeySignatureResult(
      staffId: staffId,
      count: 0,
      accidentalType: KeySignatureAccidental.none,
      alteredSteps: const [],
      label: 'No key signature',
    );
  }
}

class KeySignatureService {
  static const List<String> _sharpOrder = ['F', 'C', 'G', 'D', 'A', 'E', 'B'];
  static const List<String> _flatOrder = ['B', 'E', 'A', 'D', 'G', 'C', 'F'];

  KeySignatureResult resolveKeySignature({
    required String staffId,
    required List<SymbolClassItem> symbolsInStaff,
    required double spacing,
  }) {
    final noteheads = symbolsInStaff
        .where((s) => s.className.trim().toLowerCase() == 'notehead')
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));

    if (noteheads.isEmpty) {
      return KeySignatureResult.none(staffId);
    }

    final firstNoteX = noteheads.first.x;

    final keyCandidates = symbolsInStaff.where((symbol) {
      final name = symbol.className.trim().toLowerCase();

      final isKeyCandidate = name == 'sharp' || name == 'flat';
      final beforeFirstNote = symbol.x < firstNoteX;

      // Keep it away from notes; accidentals near notes will be handled later.
      final notTooCloseToFirstNote = (firstNoteX - symbol.x) > spacing * 1.2;

      return isKeyCandidate && beforeFirstNote && notTooCloseToFirstNote;
    }).toList()
      ..sort((a, b) => a.x.compareTo(b.x));

    if (keyCandidates.isEmpty) {
      return KeySignatureResult.none(staffId);
    }

    final sharpCount = keyCandidates
        .where((s) => s.className.trim().toLowerCase() == 'sharp')
        .length;

    final flatCount = keyCandidates
        .where((s) => s.className.trim().toLowerCase() == 'flat')
        .length;

    if (sharpCount == 0 && flatCount == 0) {
      return KeySignatureResult.none(staffId);
    }

    // If mixed symbols appear, pick the majority for now.
    if (sharpCount >= flatCount) {
      final count = sharpCount.clamp(0, 7);
      return KeySignatureResult(
        staffId: staffId,
        count: count,
        accidentalType: KeySignatureAccidental.sharp,
        alteredSteps: _sharpOrder.take(count).toList(),
        label: count == 0 ? 'No key signature' : '$count sharp key signature',
      );
    }

    final count = flatCount.clamp(0, 7);
    return KeySignatureResult(
      staffId: staffId,
      count: count,
      accidentalType: KeySignatureAccidental.flat,
      alteredSteps: _flatOrder.take(count).toList(),
      label: count == 0 ? 'No key signature' : '$count flat key signature',
    );
  }

  String applyToPitch({
    required String pitch,
    required KeySignatureResult keySignature,
  }) {
    if (keySignature.accidentalType == KeySignatureAccidental.none) {
      return pitch;
    }

    final parsed = _parsePitch(pitch);
    if (parsed == null) return pitch;

    final letter = parsed.$1;
    final accidental = parsed.$2;
    final octave = parsed.$3;

    // If pitch already has explicit accidental, leave it alone.
    // Direct accidental service will override later.
    if (accidental.isNotEmpty) {
      return pitch;
    }

    if (!keySignature.alteredSteps.contains(letter)) {
      return pitch;
    }

    switch (keySignature.accidentalType) {
      case KeySignatureAccidental.sharp:
        return '$letter#$octave';
      case KeySignatureAccidental.flat:
        return '${letter}b$octave';
      case KeySignatureAccidental.none:
        return pitch;
    }
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