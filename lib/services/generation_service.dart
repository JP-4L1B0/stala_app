import '../models/tablature_result.dart';

class GeneratedTabResult {
  final String title;
  final TranslationMode mode;
  final List<GeneratedTabColumn> columns;
  final List<GeneratedTabRow> rows;
  final List<FretboardHighlightFrame> fretboardFrames;
  final List<TabExportPage> exportPages;
  final double totalWidth;
  final double rowHeight;
  final double columnWidth;

  const GeneratedTabResult({
    required this.title,
    required this.mode,
    required this.columns,
    required this.rows,
    required this.fretboardFrames,
    required this.exportPages,
    required this.totalWidth,
    required this.rowHeight,
    required this.columnWidth,
  });

  GeneratedTabColumn? columnForEvent(int eventIndex) {
    for (final column in columns) {
      if (column.eventIndex == eventIndex) return column;
    }
    return null;
  }

  FretboardHighlightFrame? fretboardFrameForEvent(int eventIndex) {
    for (final frame in fretboardFrames) {
      if (frame.eventIndex == eventIndex) return frame;
    }
    return null;
  }
}

class GeneratedTabRow {
  final int stringNumber;
  final String label;
  final int visualIndex;

  const GeneratedTabRow({
    required this.stringNumber,
    required this.label,
    required this.visualIndex,
  });
}

class GeneratedTabColumn {
  final int eventIndex;
  final String label;
  final double durationSeconds;
  final double x;
  final double width;
  final List<GeneratedTabNumber> numbers;
  final EventDetail eventDetail;

  const GeneratedTabColumn({
    required this.eventIndex,
    required this.label,
    required this.durationSeconds,
    required this.x,
    required this.width,
    required this.numbers,
    required this.eventDetail,
  });

  bool get isRest => numbers.isEmpty;
  bool get isChord => numbers.length > 1;
}

class GeneratedTabNumber {
  final int eventIndex;
  final int stringNumber;
  final int fret;
  final String pitch;
  final double x;
  final int visualRowIndex;

  const GeneratedTabNumber({
    required this.eventIndex,
    required this.stringNumber,
    required this.fret,
    required this.pitch,
    required this.x,
    required this.visualRowIndex,
  });
}

class EventDetail {
  final int eventIndex;
  final String label;
  final double durationSeconds;
  final List<TabPosition> positions;

  const EventDetail({
    required this.eventIndex,
    required this.label,
    required this.durationSeconds,
    required this.positions,
  });

  String get displayTitle {
    if (positions.isEmpty) return 'Rest';
    if (positions.length > 1) return label.isNotEmpty ? label : 'Chord';
    return label.isNotEmpty ? label : positions.first.pitch;
  }

  String get displaySubtitle {
    if (positions.isEmpty) {
      return 'No fretboard position';
    }

    if (positions.length == 1) {
      final p = positions.first;
      return 'String: ${p.stringNumber}, Fret: ${p.fret}';
    }

    return positions
        .map((p) => 'S${p.stringNumber}:F${p.fret}')
        .join('  •  ');
  }
}

class FretboardHighlightFrame {
  final int eventIndex;
  final String label;
  final List<TabPosition> highlights;

  const FretboardHighlightFrame({
    required this.eventIndex,
    required this.label,
    required this.highlights,
  });
}

class TabExportPage {
  final int pageIndex;
  final int startEventIndex;
  final int endEventIndex;
  final List<GeneratedTabColumn> columns;

  const TabExportPage({
    required this.pageIndex,
    required this.startEventIndex,
    required this.endEventIndex,
    required this.columns,
  });
}

class GenerationService {
  static const List<GeneratedTabRow> standardGuitarRows = [
    GeneratedTabRow(stringNumber: 6, label: 'E', visualIndex: 0), // Low E
    GeneratedTabRow(stringNumber: 5, label: 'A', visualIndex: 1),
    GeneratedTabRow(stringNumber: 4, label: 'D', visualIndex: 2),
    GeneratedTabRow(stringNumber: 3, label: 'G', visualIndex: 3),
    GeneratedTabRow(stringNumber: 2, label: 'B', visualIndex: 4),
    GeneratedTabRow(stringNumber: 1, label: 'e', visualIndex: 5), // High E
  ];

  const GenerationService();

  GeneratedTabResult generate({
    required TablatureResult result,
    double columnWidth = 48,
    double rowHeight = 32,
    int exportEventsPerPage = 24,
  }) {
    final columns = <GeneratedTabColumn>[];

    for (int i = 0; i < result.events.length; i++) {
      final event = result.events[i];
      final x = i * columnWidth;

      columns.add(
        GeneratedTabColumn(
          eventIndex: event.eventIndex,
          label: event.label,
          durationSeconds: event.durationSeconds,
          x: x,
          width: columnWidth,
          numbers: _buildNumbers(
            event: event,
            x: x + (columnWidth / 2),
          ),
          eventDetail: EventDetail(
            eventIndex: event.eventIndex,
            label: event.label,
            durationSeconds: event.durationSeconds,
            positions: event.positions,
          ),
        ),
      );
    }

    final fretboardFrames = result.events.map((event) {
      return FretboardHighlightFrame(
        eventIndex: event.eventIndex,
        label: event.label,
        highlights: event.positions,
      );
    }).toList();

    return GeneratedTabResult(
      title: result.title,
      mode: result.mode,
      columns: columns,
      rows: standardGuitarRows,
      fretboardFrames: fretboardFrames,
      exportPages: _buildExportPages(
        columns: columns,
        eventsPerPage: exportEventsPerPage,
      ),
      totalWidth: columns.length * columnWidth,
      rowHeight: rowHeight,
      columnWidth: columnWidth,
    );
  }

  List<GeneratedTabResult> generateAll({
    required List<TablatureResult> results,
    double columnWidth = 48,
    double rowHeight = 32,
    int exportEventsPerPage = 24,
  }) {
    return results.map((result) {
      return generate(
        result: result,
        columnWidth: columnWidth,
        rowHeight: rowHeight,
        exportEventsPerPage: exportEventsPerPage,
      );
    }).toList();
  }

  List<GeneratedTabNumber> _buildNumbers({
    required TablatureEvent event,
    required double x,
  }) {
    return event.positions.map((position) {
      return GeneratedTabNumber(
        eventIndex: event.eventIndex,
        stringNumber: position.stringNumber,
        fret: position.fret,
        pitch: position.pitch,
        x: x,
        visualRowIndex: _visualRowIndexForString(position.stringNumber),
      );
    }).toList();
  }

  int _visualRowIndexForString(int stringNumber) {
    switch (stringNumber) {
      case 6:
        return 0;
      case 5:
        return 1;
      case 4:
        return 2;
      case 3:
        return 3;
      case 2:
        return 4;
      case 1:
        return 5;
      default:
        return 5;
    }
  }

  List<TabExportPage> _buildExportPages({
    required List<GeneratedTabColumn> columns,
    required int eventsPerPage,
  }) {
    if (columns.isEmpty) return const [];

    final pages = <TabExportPage>[];

    for (int start = 0; start < columns.length; start += eventsPerPage) {
      final endExclusive = (start + eventsPerPage > columns.length)
          ? columns.length
          : start + eventsPerPage;

      final pageColumns = columns.sublist(start, endExclusive);

      pages.add(
        TabExportPage(
          pageIndex: pages.length,
          startEventIndex: pageColumns.first.eventIndex,
          endEventIndex: pageColumns.last.eventIndex,
          columns: pageColumns,
        ),
      );
    }

    return pages;
  }
}