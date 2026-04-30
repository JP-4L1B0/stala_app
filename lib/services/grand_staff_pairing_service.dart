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
    final clefByStaffId = {
      for (final group in translateGroups)
        group.staffId: group.summary.clefStatusLabel.toLowerCase(),
    };

    final trebleStaffIds = <String>[];
    final bassStaffIds = <String>[];

    for (final group in noteGroups) {
      final clefLabel = clefByStaffId[group.staffId] ?? '';

      if (clefLabel.contains('bass')) {
        bassStaffIds.add(group.staffId);
      } else {
        trebleStaffIds.add(group.staffId);
      }
    }

    final pairs = <GrandStaffPair>[];
    final maxCount = trebleStaffIds.length > bassStaffIds.length
        ? trebleStaffIds.length
        : bassStaffIds.length;

    for (int i = 0; i < maxCount; i++) {
      if (i >= trebleStaffIds.length) continue;

      pairs.add(
        GrandStaffPair(
          id: 'grand_staff_${pairs.length}',
          trebleStaffId: trebleStaffIds[i],
          bassStaffId: i < bassStaffIds.length ? bassStaffIds[i] : null,
        ),
      );
    }

    return pairs;
  }
}