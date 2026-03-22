import '../models/saved_item_data.dart';
import '../models/session_data.dart';

class RecentItemsRepository {
  RecentItemsRepository._();

  static List<SavedItemData> getTemporaryRecentItems() {
    return List.generate(
      10,
          (index) => SavedItemData(
        id: 'recent_$index',
        title: 'Unnamed_${(index + 1).toString().padLeft(2, '0')}',
        subtitle: _generateModifiedText(index),
        fileType: index.isEven ? '.stala' : '.zip',
        createdAt: _generatePlaceholderDate(index),
      ),
    );
  }

  static List<SavedItemData> fromSessions(
      List<SessionData> sessions, {
        String fileType = '.stala',
      }) {
    return sessions
        .map(
          (session) => SavedItemData.fromSession(
        session,
        fileType: fileType,
      ),
    )
        .toList();
  }

  static String _generatePlaceholderDate(int index) {
    final now = DateTime.now().subtract(Duration(days: index));
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year.toString();
    return '$day/$month/$year';
  }

  static String _generateModifiedText(int index) {
    if (index < 5) {
      return '${(index + 1) * 7} min ago';
    }
    return '${index - 3} h ago';
  }
}