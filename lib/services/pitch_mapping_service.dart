import '../models/translation_group_models.dart';
import 'clef_resolution_service.dart';

class PitchMappingService {
  String? resolvePitch({
    required SegmentMapItem segment,
    required ResolvedClef clef,
  }) {
    final stepIndex = _stepIndexFromLocationId(segment.id);
    if (stepIndex == null) return null;

    switch (clef) {
      case ResolvedClef.treble:
        return _pitchFromBase(
          baseLetter: 'F',
          baseOctave: 5,
          stepIndex: stepIndex,
        );

      case ResolvedClef.bass:
        return _pitchFromBase(
          baseLetter: 'A',
          baseOctave: 3,
          stepIndex: stepIndex,
        );

      case ResolvedClef.unknown:
        return _pitchFromBase(
          baseLetter: 'F',
          baseOctave: 5,
          stepIndex: stepIndex,
        );
    }
  }

  int? _stepIndexFromLocationId(String id) {
    if (id.startsWith('line_')) {
      final n = int.tryParse(id.replaceFirst('line_', ''));
      if (n == null) return null;
      return n * 2;
    }

    if (id.startsWith('space_')) {
      final n = int.tryParse(id.replaceFirst('space_', ''));
      if (n == null) return null;
      return (n * 2) + 1;
    }

    if (id.startsWith('v_line_above_')) {
      final n = int.tryParse(id.replaceFirst('v_line_above_', ''));
      if (n == null) return null;
      return -2 * n;
    }

    if (id.startsWith('v_line_below_')) {
      final n = int.tryParse(id.replaceFirst('v_line_below_', ''));
      if (n == null) return null;
      return 8 + (2 * n);
    }

    return null;
  }

  String _pitchFromBase({
    required String baseLetter,
    required int baseOctave,
    required int stepIndex,
  }) {
    const letters = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

    final baseLetterIndex = letters.indexOf(baseLetter);
    final baseDiatonicNumber = (baseOctave * 7) + baseLetterIndex;

    final targetDiatonicNumber = baseDiatonicNumber - stepIndex;

    final octave = targetDiatonicNumber ~/ 7;
    final letterIndex = targetDiatonicNumber % 7;
    final letter = letters[letterIndex];

    return '$letter$octave';
  }
}