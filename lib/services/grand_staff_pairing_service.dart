import '../dummy_page.dart';
import '../models/translation_group_models.dart';

class GrandStaffPair {
  final String id;
  final String trebleStaffId;
  final String? bassStaffId;

  const GrandStaffPair({
    required this.id,
    required this.trebleStaffId,
    this.bassStaffId,
  });
}

class GrandStaffPairingService {
  List<GrandStaffPair> pairStaffs({
    required List<NoteGroupViewItem> noteGroups,
    required List<StaffTranslateGroup> translateGroups,
  }) {
    final noteStaffIds = noteGroups.map((group) => group.staffId).toSet();
    final orderedStaffIds = translateGroups
        .map((group) => group.staffId)
        .where(noteStaffIds.contains)
        .toList();

    final clefByStaffId = {
      for (final group in translateGroups)
        group.staffId: group.summary.clefStatusLabel.toLowerCase(),
    };

    final used = <String>{};
    final pairs = <GrandStaffPair>[];

    for (int i = 0; i < orderedStaffIds.length; i++) {
      final staffId = orderedStaffIds[i];
      if (used.contains(staffId)) continue;

      final role = _roleForStaff(
        staffId: staffId,
        orderedStaffIds: orderedStaffIds,
        clefByStaffId: clefByStaffId,
      );

      if (role == _StaffPairRole.bass) {
        continue;
      }

      final bassStaffId = _findBassPartner(
        trebleIndex: i,
        orderedStaffIds: orderedStaffIds,
        clefByStaffId: clefByStaffId,
        used: used,
      );

      pairs.add(
        GrandStaffPair(
          id: 'grand_staff_${pairs.length}',
          trebleStaffId: staffId,
          bassStaffId: bassStaffId,
        ),
      );

      used.add(staffId);
      if (bassStaffId != null) used.add(bassStaffId);
    }

    return pairs;
  }

  String? _findBassPartner({
    required int trebleIndex,
    required List<String> orderedStaffIds,
    required Map<String, String> clefByStaffId,
    required Set<String> used,
  }) {
    final nextIndex = trebleIndex + 1;
    if (nextIndex >= orderedStaffIds.length) return null;

    final candidate = orderedStaffIds[nextIndex];
    if (used.contains(candidate)) return null;

    final role = _roleForStaff(
      staffId: candidate,
      orderedStaffIds: orderedStaffIds,
      clefByStaffId: clefByStaffId,
    );

    if (role == _StaffPairRole.bass) return candidate;

    return null;
  }

  _StaffPairRole _roleForStaff({
    required String staffId,
    required List<String> orderedStaffIds,
    required Map<String, String> clefByStaffId,
  }) {
    final clefLabel = clefByStaffId[staffId] ?? '';

    if (clefLabel.contains('bass')) return _StaffPairRole.bass;
    if (clefLabel.contains('treble')) return _StaffPairRole.treble;

    final index = orderedStaffIds.indexOf(staffId);
    if (index < 0) return _StaffPairRole.treble;

    return index.isEven ? _StaffPairRole.treble : _StaffPairRole.bass;
  }
}

enum _StaffPairRole { treble, bass }
