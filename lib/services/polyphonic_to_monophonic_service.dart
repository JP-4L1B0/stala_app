import '../models/translation_group_models.dart';
import 'grand_staff_pairing_service.dart';

class HarmonicStack {
  final String id;
  final String grandStaffId;
  final int eventIndex;
  final List<TranslatedSymbolViewItem> notes;

  const HarmonicStack({
    required this.id,
    required this.grandStaffId,
    required this.eventIndex,
    required this.notes,
  });
}

class ChordAwareStack {
  final String id;
  final String grandStaffId;
  final int eventIndex;
  final List<TranslatedSymbolViewItem> notes;
  final String? chordName;
  final String? root;
  final String? quality;

  const ChordAwareStack({
    required this.id,
    required this.grandStaffId,
    required this.eventIndex,
    required this.notes,
    this.chordName,
    this.root,
    this.quality,
  });
}

class MonophonicNote {
  final String id;
  final String grandStaffId;
  final int eventIndex;
  final String pitch;
  final TranslatedSymbolViewItem sourceNote;
  final List<String> harmonyContext;
  final String selectionReason;

  const MonophonicNote({
    required this.id,
    required this.grandStaffId,
    required this.eventIndex,
    required this.pitch,
    required this.sourceNote,
    required this.harmonyContext,
    required this.selectionReason,
  });
}

class PolyphonicToMonophonicResult {
  final String grandStaffId;
  final List<HarmonicStack> harmonicStacks;
  final List<ChordAwareStack> chordAwareStacks;
  final List<MonophonicNote> strictMelody;
  final List<MonophonicNote> continuityMelody;

  const PolyphonicToMonophonicResult({
    required this.grandStaffId,
    required this.harmonicStacks,
    required this.chordAwareStacks,
    required this.strictMelody,
    required this.continuityMelody,
  });
}

class _HarmonicCandidate {
  final double centerX;
  final List<TranslatedSymbolViewItem> notes;

  const _HarmonicCandidate({
    required this.centerX,
    required this.notes,
  });
}

class PolyphonicToMonophonicService {
  List<PolyphonicToMonophonicResult> convert({
    required List<GrandStaffPair> grandStaffPairs,
    required Map<String, List<List<TranslatedSymbolViewItem>>> groupedNotes,
  }) {
    return grandStaffPairs.map((pair) {
      final stacks = _buildHarmonicStacks(
        pair: pair,
        groupedNotes: groupedNotes,
      );

      final chordAwareStacks = _buildChordAwareStacks(stacks);

      final strict = _prioritizeMelodyStrict(
        grandStaffId: pair.id,
        stacks: stacks,
      );

      final continuity = _prioritizeMelodyContinuity(
        grandStaffId: pair.id,
        stacks: stacks,
      );

      return PolyphonicToMonophonicResult(
        grandStaffId: pair.id,
        harmonicStacks: stacks,
        chordAwareStacks: chordAwareStacks,
        strictMelody: strict,
        continuityMelody: continuity,
      );
    }).toList();
  }

  List<HarmonicStack> _buildHarmonicStacks({
    required GrandStaffPair pair,
    required Map<String, List<List<TranslatedSymbolViewItem>>> groupedNotes,
  }) {
    final trebleGroups =
        groupedNotes[pair.trebleStaffId] ?? const <List<TranslatedSymbolViewItem>>[];

    final bassGroups = pair.bassStaffId == null
        ? const <List<TranslatedSymbolViewItem>>[]
        : groupedNotes[pair.bassStaffId] ?? const <List<TranslatedSymbolViewItem>>[];

    final allGroups = <List<TranslatedSymbolViewItem>>[
      ...trebleGroups,
      ...bassGroups,
    ];

    final eventCandidates = allGroups
        .where((group) => group.isNotEmpty)
        .map((group) {
      final avgX =
          group.map((note) => note.centerX).reduce((a, b) => a + b) /
              group.length;

      return _HarmonicCandidate(
        centerX: avgX,
        notes: group,
      );
    }).toList()
      ..sort((a, b) => a.centerX.compareTo(b.centerX));

    if (eventCandidates.isEmpty) return const [];

    final threshold = _estimateHarmonicThreshold(eventCandidates);

    final clusters = <List<_HarmonicCandidate>>[];
    List<_HarmonicCandidate> currentCluster = [];

    for (final candidate in eventCandidates) {
      if (currentCluster.isEmpty) {
        currentCluster.add(candidate);
        continue;
      }

      final clusterCenter = currentCluster
          .map((item) => item.centerX)
          .reduce((a, b) => a + b) /
          currentCluster.length;

      final dx = (candidate.centerX - clusterCenter).abs();

      if (dx <= threshold) {
        currentCluster.add(candidate);
      } else {
        clusters.add(currentCluster);
        currentCluster = [candidate];
      }
    }

    if (currentCluster.isNotEmpty) {
      clusters.add(currentCluster);
    }

    final stacks = <HarmonicStack>[];

    for (int i = 0; i < clusters.length; i++) {
      final notes = clusters[i]
          .expand((candidate) => candidate.notes)
          .where((note) =>
      note.defaultKeyLabel != null &&
          note.defaultKeyLabel!.trim().isNotEmpty)
          .toList();

      if (notes.isEmpty) continue;

      stacks.add(
        HarmonicStack(
          id: '${pair.id}_stack_$i',
          grandStaffId: pair.id,
          eventIndex: i,
          notes: notes,
        ),
      );
    }

    return stacks;
  }

  List<ChordAwareStack> _buildChordAwareStacks(List<HarmonicStack> stacks) {
    return stacks.map((stack) {
      final chord = _detectChord(stack.notes);

      return ChordAwareStack(
        id: '${stack.id}_chord',
        grandStaffId: stack.grandStaffId,
        eventIndex: stack.eventIndex,
        notes: stack.notes,
        chordName: chord?.chordName,
        root: chord?.root,
        quality: chord?.quality,
      );
    }).toList();
  }

  _ChordResult? _detectChord(List<TranslatedSymbolViewItem> notes) {
    final pitchClasses = notes
        .map((note) => note.defaultKeyLabel)
        .whereType<String>()
        .map(_pitchClass)
        .whereType<int>()
        .toSet();

    if (pitchClasses.length == 1) return null;

    if (pitchClasses.length == 2) {
      return _detectDyadOrInterval(pitchClasses);
    }

    const names = {
      0: 'C',
      1: 'C#',
      2: 'D',
      3: 'D#',
      4: 'E',
      5: 'F',
      6: 'F#',
      7: 'G',
      8: 'G#',
      9: 'A',
      10: 'A#',
      11: 'B',
    };

    for (int root = 0; root < 12; root++) {
      final major = {
        root,
        (root + 4) % 12,
        (root + 7) % 12,
      };

      final minor = {
        root,
        (root + 3) % 12,
        (root + 7) % 12,
      };

      final diminished = {
        root,
        (root + 3) % 12,
        (root + 6) % 12,
      };

      if (pitchClasses.containsAll(major)) {
        final rootName = names[root]!;
        return _ChordResult(
          chordName: rootName,
          root: rootName,
          quality: 'major',
        );
      }

      if (pitchClasses.containsAll(minor)) {
        final rootName = names[root]!;
        return _ChordResult(
          chordName: '${rootName}m',
          root: rootName,
          quality: 'minor',
        );
      }

      if (pitchClasses.containsAll(diminished)) {
        final rootName = names[root]!;
        return _ChordResult(
          chordName: '${rootName}dim',
          root: rootName,
          quality: 'diminished',
        );
      }
    }

    return null;
  }

  int? _pitchClass(String pitch) {
    final match = RegExp(r'^([A-G])([#b]?)-?\d+$').firstMatch(pitch);
    if (match == null) return null;

    final letter = match.group(1)!;
    final accidental = match.group(2) ?? '';

    const base = {
      'C': 0,
      'D': 2,
      'E': 4,
      'F': 5,
      'G': 7,
      'A': 9,
      'B': 11,
    };

    var value = base[letter];
    if (value == null) return null;

    if (accidental == '#') value += 1;
    if (accidental == 'b') value -= 1;

    return value % 12;
  }

  _ChordResult? _detectDyadOrInterval(Set<int> pitchClasses) {
    final notes = pitchClasses.toList()..sort();
    final a = notes[0];
    final b = notes[1];

    final interval = (b - a) % 12;

    const names = {
      0: 'C',
      1: 'C#',
      2: 'D',
      3: 'D#',
      4: 'E',
      5: 'F',
      6: 'F#',
      7: 'G',
      8: 'G#',
      9: 'A',
      10: 'A#',
      11: 'B',
    };

    final rootName = names[a] ?? 'Unknown';

    switch (interval) {
      case 3:
        return _ChordResult(
          chordName: '$rootName minor third',
          root: rootName,
          quality: 'minor third interval',
        );

      case 4:
        return _ChordResult(
          chordName: '$rootName major third',
          root: rootName,
          quality: 'major third interval',
        );

      case 5:
        return _ChordResult(
          chordName: '$rootName perfect fourth',
          root: rootName,
          quality: 'perfect fourth interval',
        );

      case 7:
        return _ChordResult(
          chordName: '${rootName}5',
          root: rootName,
          quality: 'power chord / perfect fifth',
        );

      case 8:
        return _ChordResult(
          chordName: '$rootName minor sixth',
          root: rootName,
          quality: 'minor sixth interval',
        );

      case 9:
        return _ChordResult(
          chordName: '$rootName major sixth',
          root: rootName,
          quality: 'major sixth interval',
        );

      default:
        return _ChordResult(
          chordName: '$rootName interval',
          root: rootName,
          quality: 'dyad interval',
        );
    }
  }

  List<MonophonicNote> _prioritizeMelody({
    required String grandStaffId,
    required List<HarmonicStack> stacks,
  }) {
    final melody = <MonophonicNote>[];
    int? previousMidi;

    for (final stack in stacks) {
      final candidates = stack.notes.where((note) {
        final pitch = note.defaultKeyLabel;
        return pitch != null && pitch.trim().isNotEmpty;
      }).toList();

      if (candidates.isEmpty) continue;

      TranslatedSymbolViewItem? bestNote;
      double bestScore = double.negativeInfinity;
      String bestReason = 'unknown';

      for (final note in candidates) {
        final pitch = note.defaultKeyLabel ?? '';
        final midi = _pitchToMidiValue(pitch);
        if (midi <= -9999) continue;

        final isTrebleLikely = _isTrebleMelodyCandidate(note);
        final scoreResult = _scoreMelodyCandidate(
          midi: midi,
          previousMidi: previousMidi,
          isTrebleLikely: isTrebleLikely,
        );

        if (scoreResult.score > bestScore) {
          bestScore = scoreResult.score;
          bestNote = note;
          bestReason = scoreResult.reason;
        }
      }

      if (bestNote == null) continue;

      final selectedPitch = bestNote.defaultKeyLabel ?? 'Unresolved';
      previousMidi = _pitchToMidiValue(selectedPitch);

      melody.add(
        MonophonicNote(
          id: '${grandStaffId}_mono_${stack.eventIndex}',
          grandStaffId: grandStaffId,
          eventIndex: stack.eventIndex,
          pitch: selectedPitch,
          sourceNote: bestNote,
          harmonyContext: candidates
              .map((note) => note.defaultKeyLabel ?? 'Unresolved')
              .toList(),
          selectionReason: bestReason,
        ),
      );
    }

    return melody;
  }

  List<MonophonicNote> _prioritizeMelodyStrict({
    required String grandStaffId,
    required List<HarmonicStack> stacks,
  }) {
    final melody = <MonophonicNote>[];

    for (final stack in stacks) {
      final trebleNotes = stack.notes.where((n) {
        return n.staffRole == 'treble' &&
            n.defaultKeyLabel != null &&
            n.defaultKeyLabel!.trim().isNotEmpty;
      }).toList();

      if (trebleNotes.isEmpty) continue;

      trebleNotes.sort((a, b) {
        return _pitchToMidiValue(b.defaultKeyLabel!)
            .compareTo(_pitchToMidiValue(a.defaultKeyLabel!));
      });

      final selected = trebleNotes.first;

      melody.add(
        MonophonicNote(
          id: '${grandStaffId}_strict_${stack.eventIndex}',
          grandStaffId: grandStaffId,
          eventIndex: stack.eventIndex,
          pitch: selected.defaultKeyLabel!,
          sourceNote: selected,
          harmonyContext: stack.notes
              .map((n) => n.defaultKeyLabel ?? 'Unresolved')
              .toList(),
          selectionReason: 'strict_treble_only',
        ),
      );
    }

    return melody;
  }

  List<MonophonicNote> _prioritizeMelodyContinuity({
    required String grandStaffId,
    required List<HarmonicStack> stacks,
  }) {
    final melody = <MonophonicNote>[];
    int? previousMidi;

    for (final stack in stacks) {
      final candidates = stack.notes.where((n) {
        return n.defaultKeyLabel != null &&
            n.defaultKeyLabel!.trim().isNotEmpty;
      }).toList();

      if (candidates.isEmpty) continue;

      TranslatedSymbolViewItem? best;
      double bestScore = double.negativeInfinity;

      for (final note in candidates) {
        final midi = _pitchToMidiValue(note.defaultKeyLabel!);
        final isTreble = note.staffRole == 'treble';

        double score = 0;

        // Treble priority
        score += isTreble ? 50 : -20;

        // Continuity
        if (previousMidi != null) {
          final jump = (midi - previousMidi).abs();

          if (jump <= 2) score += 30;
          else if (jump <= 5) score += 20;
          else if (jump <= 12) score += 5;
          else score -= 40;
        }

        // Bass restriction
        if (!isTreble && previousMidi != null) {
          final jump = (midi - previousMidi).abs();
          if (jump > 7) score -= 60; // reject bad bass jumps
        }

        if (score > bestScore) {
          bestScore = score;
          best = note;
        }
      }

      if (best == null) continue;

      final pitch = best.defaultKeyLabel!;
      previousMidi = _pitchToMidiValue(pitch);

      melody.add(
        MonophonicNote(
          id: '${grandStaffId}_cont_${stack.eventIndex}',
          grandStaffId: grandStaffId,
          eventIndex: stack.eventIndex,
          pitch: pitch,
          sourceNote: best,
          harmonyContext: candidates
              .map((n) => n.defaultKeyLabel ?? 'Unresolved')
              .toList(),
          selectionReason:
          best.staffRole == 'treble' ? 'treble_primary' : 'bass_fallback',
        ),
      );
    }

    return melody;
  }

  int _pitchToMidiValue(String pitch) {
    final match = RegExp(r'^([A-G])([#b]?)(-?\d+)$').firstMatch(pitch);
    if (match == null) return -9999;

    final letter = match.group(1)!;
    final accidental = match.group(2) ?? '';
    final octave = int.tryParse(match.group(3) ?? '') ?? 0;

    const baseSemitones = {
      'C': 0,
      'D': 2,
      'E': 4,
      'F': 5,
      'G': 7,
      'A': 9,
      'B': 11,
    };

    var semitone = baseSemitones[letter] ?? 0;

    if (accidental == '#') semitone += 1;
    if (accidental == 'b') semitone -= 1;

    return ((octave + 1) * 12) + semitone;
  }

  double _estimateHarmonicThreshold(List<_HarmonicCandidate> candidates) {
    if (candidates.length < 2) return 8.0;

    final gaps = <double>[];

    for (int i = 0; i < candidates.length - 1; i++) {
      final dx = (candidates[i + 1].centerX - candidates[i].centerX).abs();

      if (dx > 0) {
        gaps.add(dx);
      }
    }

    if (gaps.isEmpty) return 8.0;

    gaps.sort();

    final medianGap = gaps[gaps.length ~/ 2];

    return (medianGap * 0.35).clamp(6.0, 18.0);
  }

  _MelodyScoreResult _scoreMelodyCandidate({
    required int midi,
    required int? previousMidi,
    required bool isTrebleLikely,
  }) {
    double score = 0;
    final reasons = <String>[];

    // 1. Primary voice bias
    if (isTrebleLikely) {
      score += 45;
      reasons.add('treble_primary');
    } else {
      score -= 15;
      reasons.add('bass_fallback');
    }

    // 2. Register preference: guitar-friendly / melody-friendly range
    // E3 = 52, E6 = 88
    if (midi >= 52 && midi <= 88) {
      score += 20;
      reasons.add('register_ok');
    } else {
      score -= 20;
      reasons.add('register_outlier');
    }

    // 3. Continuity from previous melody
    if (previousMidi != null) {
      final jump = (midi - previousMidi).abs();

      if (jump == 0) {
        score += 25;
        reasons.add('repeat_stability');
      } else if (jump <= 2) {
        score += 22;
        reasons.add('stepwise_motion');
      } else if (jump <= 5) {
        score += 15;
        reasons.add('small_jump');
      } else if (jump <= 12) {
        score += 3;
        reasons.add('moderate_jump');
      } else {
        score -= 30;
        reasons.add('large_jump_penalty');
      }
    } else {
      // First note: prefer higher register slightly, but not too much.
      score += midi * 0.05;
      reasons.add('initial_pitch');
    }

    // 4. Small upper-register preference, weaker than continuity.
    score += midi * 0.03;

    return _MelodyScoreResult(
      score: score,
      reason: reasons.join('+'),
    );
  }

  bool _isTrebleMelodyCandidate(TranslatedSymbolViewItem note) {
    return note.staffRole == 'treble';
  }
}

class _ChordResult {
  final String chordName;
  final String root;
  final String quality;

  const _ChordResult({
    required this.chordName,
    required this.root,
    required this.quality,
  });
}

class _MelodyScoreResult {
  final double score;
  final String reason;

  const _MelodyScoreResult({
    required this.score,
    required this.reason,
  });
}