import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_text_styles.dart';
import 'models/translation_group_models.dart';
import 'models/session_data.dart';
import 'result_page.dart';
import 'services/generation_service.dart';

enum DummyViewOption {
  cropped,
  detected,
  segments,
  classList,
  translate,
  generate,
}

class DetectionPoint {
  final String className;
  final double centerX;
  final double centerY;
  final double? score;

  const DetectionPoint({
    required this.className,
    required this.centerX,
    required this.centerY,
    this.score,
  });
}

class LedgerLineViewItem {
  final String staffId;
  final double x1;
  final double x2;
  final double y;

  const LedgerLineViewItem({
    required this.staffId,
    required this.x1,
    required this.x2,
    required this.y,
  });
}

class SymbolClassItem {
  final String className;
  final double x;
  final double y;
  final double? score;
  final List<double>? bbox;

  const SymbolClassItem({
    required this.className,
    required this.x,
    required this.y,
    this.score,
    this.bbox,
  });
}

class GenerateOutputItem {
  final String title;
  final String value;

  const GenerateOutputItem({required this.title, required this.value});
}

class NoteGroupViewItem {
  final String staffId;
  final List<List<String>> groups;

  const NoteGroupViewItem({required this.staffId, required this.groups});
}

class RhythmEventViewItem {
  final String staffId;
  final int? measureIndex;
  final String label;
  final double durationBeats;
  final String timingSource;
  final double confidence;
  final bool hasStem;
  final bool hasBeam;

  const RhythmEventViewItem({
    required this.staffId,
    required this.measureIndex,
    required this.label,
    required this.durationBeats,
    required this.timingSource,
    required this.confidence,
    required this.hasStem,
    required this.hasBeam,
  });
}

class GrandStaffPairViewItem {
  final String id;
  final String trebleStaffId;
  final String? bassStaffId;
  final List<List<String>> trebleGroups;
  final List<List<String>> bassGroups;

  const GrandStaffPairViewItem({
    required this.id,
    required this.trebleStaffId,
    required this.bassStaffId,
    required this.trebleGroups,
    required this.bassGroups,
  });
}

class PolyMonoViewItem {
  final String grandStaffId;
  final List<List<String>> harmonicStacks;
  final List<String> chordAwareStacks;
  final List<String> strictMelody;
  final List<String> continuityMelody;

  const PolyMonoViewItem({
    required this.grandStaffId,
    required this.harmonicStacks,
    required this.chordAwareStacks,
    required this.strictMelody,
    required this.continuityMelody,
  });
}

class MusicInterpretationViewItem {
  final String title;
  final List<String> labels;

  const MusicInterpretationViewItem({
    required this.title,
    required this.labels,
  });
}

class FretboardMappingViewItem {
  final String title;
  final List<String> eventSummaries;

  const FretboardMappingViewItem({
    required this.title,
    required this.eventSummaries,
  });
}

class EventManagerViewItem {
  final String title;
  final String totalCost;
  final List<String> events;

  const EventManagerViewItem({
    required this.title,
    required this.totalCost,
    required this.events,
  });
}

class ChordVoicingViewItem {
  final String title;
  final List<String> events;

  const ChordVoicingViewItem({required this.title, required this.events});
}

class GeneratedTabViewItem {
  final String mode;
  final int columns;
  final int fretboardFrames;
  final int exportPages;
  final String firstEventSummary;

  const GeneratedTabViewItem({
    required this.mode,
    required this.columns,
    required this.fretboardFrames,
    required this.exportPages,
    required this.firstEventSummary,
  });
}

class DummyPage extends StatefulWidget {
  final String? croppedImagePath;
  final String? detectedImagePath;
  final String? segmentedImagePath;

  final List<DetectionPoint> detections;
  final List<LedgerLineViewItem> ledgerLines;
  final List<SymbolClassItem> classItems;
  final List<StaffTranslateGroup> translateGroups;
  final List<GenerateOutputItem> generateOutputs;
  final List<NoteGroupViewItem> noteGroups;
  final List<RhythmEventViewItem> rhythmEvents;
  final List<GrandStaffPairViewItem> grandStaffPairs;
  final List<PolyMonoViewItem> polyMonoResults;
  final List<MusicInterpretationViewItem> musicInterpretations;
  final List<FretboardMappingViewItem> fretboardMappings;
  final List<EventManagerViewItem> eventManagerResults;
  final List<ChordVoicingViewItem> chordVoicingResults;
  final SessionData? session;
  final List<GeneratedTabResult> generatedTabResults;
  final List<GeneratedTabViewItem> generatedTabs;

  const DummyPage({
    super.key,
    this.croppedImagePath,
    this.detectedImagePath,
    this.segmentedImagePath,
    this.detections = const [],
    this.ledgerLines = const [],
    this.classItems = const [],
    this.translateGroups = const [],
    this.generateOutputs = const [],
    this.noteGroups = const [],
    this.rhythmEvents = const [],
    this.grandStaffPairs = const [],
    this.polyMonoResults = const [],
    this.musicInterpretations = const [],
    this.fretboardMappings = const [],
    this.eventManagerResults = const [],
    this.chordVoicingResults = const [],
    this.generatedTabs = const [],
    this.generatedTabResults = const [],
    this.session,
  });

  @override
  State<DummyPage> createState() => _DummyPageState();
}

class _DummyPageState extends State<DummyPage> {
  DummyViewOption _selectedOption = DummyViewOption.cropped;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'Debug Results',
          style: AppTextStyles.sectionTitle.copyWith(fontSize: 20),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: _OptionDropdown(
                  value: _selectedOption,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedOption = value;
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.shadow,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _buildSelectedPanel(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedPanel() {
    switch (_selectedOption) {
      case DummyViewOption.cropped:
        return _ImagePanel(
          title: 'A. Preprocess - Cropped',
          subtitle: 'Preprocessed or cropped image output',
          imagePath: widget.croppedImagePath,
          emptyMessage: 'No cropped image available yet.',
        );

      case DummyViewOption.detected:
        return _DetectedPanel(
          title: 'B. Detecting Symbol - Detected',
          subtitle: 'Detected image output',
          imagePath: widget.detectedImagePath,
          detections: widget.detections,
        );

      case DummyViewOption.segments:
        return _DetectedPanel(
          title: 'C. Segmenting - Segments',
          subtitle: 'Staff lines with confirmed ledger overlays',
          imagePath: widget.segmentedImagePath,
          detections: const [],
          ledgerLines: widget.ledgerLines,
        );

      case DummyViewOption.classList:
        return _ClassListPanel(
          title: 'D. Translating - Class',
          subtitle: 'Detected symbols sorted top-left to bottom-right',
          items: widget.classItems,
        );

      case DummyViewOption.translate:
        return _TranslatePanel(
          title: 'E. Translating - Map',
          subtitle: 'Grouped translation result by staff line',
          groups: widget.translateGroups,
          noteGroups: widget.noteGroups,
          rhythmEvents: widget.rhythmEvents,
        );

      case DummyViewOption.generate:
        return _GeneratePanel(
          title: 'F. Generating - Generate',
          subtitle: 'Prepared output for graph / API generation',
          outputs: widget.generateOutputs,
          grandStaffPairs: widget.grandStaffPairs,
          polyMonoResults: widget.polyMonoResults,
          musicInterpretations: widget.musicInterpretations,
          fretboardMappings: widget.fretboardMappings,
          eventManagerResults: widget.eventManagerResults,
          chordVoicingResults: widget.chordVoicingResults,
          generatedTabResults: widget.generatedTabResults,
          generatedTabs: widget.generatedTabs,
          session: widget.session,
        );
    }
  }
}

class _OptionDropdown extends StatelessWidget {
  final DummyViewOption value;
  final ValueChanged<DummyViewOption?> onChanged;

  const _OptionDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DummyViewOption>(
          value: value,
          dropdownColor: AppColors.card,
          iconEnabledColor: AppColors.textPrimary,
          style: AppTextStyles.button,
          items: const [
            DropdownMenuItem(
              value: DummyViewOption.cropped,
              child: Text('Cropped'),
            ),
            DropdownMenuItem(
              value: DummyViewOption.detected,
              child: Text('Detected'),
            ),
            DropdownMenuItem(
              value: DummyViewOption.segments,
              child: Text('Segments'),
            ),
            DropdownMenuItem(
              value: DummyViewOption.classList,
              child: Text('Class'),
            ),
            DropdownMenuItem(
              value: DummyViewOption.translate,
              child: Text('Translate'),
            ),
            DropdownMenuItem(
              value: DummyViewOption.generate,
              child: Text('Generate'),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _PanelHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.sectionTitle),
          const SizedBox(height: 4),
          Text(subtitle, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

class _ImagePanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? imagePath;
  final String emptyMessage;

  const _ImagePanel({
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PanelHeader(title: title, subtitle: subtitle),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildImageOrEmpty(
              imagePath: imagePath,
              emptyMessage: emptyMessage,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetectedPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? imagePath;
  final List<DetectionPoint> detections;
  final List<LedgerLineViewItem> ledgerLines;

  const _DetectedPanel({
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.detections,
    this.ledgerLines = const [],
  });

  @override
  Widget build(BuildContext context) {
    final exists = imagePath != null && File(imagePath!).existsSync();

    return Column(
      children: [
        _PanelHeader(title: title, subtitle: subtitle),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: !exists
                ? const _EmptyPanelMessage(
                    message: 'No detected image available yet.',
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      color: AppColors.surface,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            children: [
                              Positioned.fill(
                                child: InteractiveViewer(
                                  child: Center(
                                    child: _DetectionImageWithOverlay(
                                      imagePath: imagePath!,
                                      detections: detections,
                                      ledgerLines: ledgerLines,
                                      maxWidth: constraints.maxWidth,
                                      maxHeight: constraints.maxHeight,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface.withValues(
                                      alpha: 0.92,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Text(
                                    'Detections: ${detections.length}',
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _DetectionImageWithOverlay extends StatelessWidget {
  final String imagePath;
  final List<DetectionPoint> detections;
  final List<LedgerLineViewItem> ledgerLines;
  final double maxWidth;
  final double maxHeight;

  const _DetectionImageWithOverlay({
    required this.imagePath,
    required this.detections,
    this.ledgerLines = const [],
    required this.maxWidth,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(imagePath);

    return FutureBuilder<ImageInfo>(
      future: _loadImageInfo(file),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final imageInfo = snapshot.data!;
        final imageWidth = imageInfo.image.width.toDouble();
        final imageHeight = imageInfo.image.height.toDouble();

        final fitted = applyBoxFit(
          BoxFit.contain,
          Size(imageWidth, imageHeight),
          Size(maxWidth, maxHeight),
        );

        final renderWidth = fitted.destination.width;
        final renderHeight = fitted.destination.height;

        return SizedBox(
          width: renderWidth,
          height: renderHeight,
          child: Stack(
            children: [
              Positioned.fill(child: Image.file(file, fit: BoxFit.contain)),
              Positioned.fill(
                child: CustomPaint(
                  painter: DetectionOverlayPainter(
                    detections: detections,
                    ledgerLines: ledgerLines,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<ImageInfo> _loadImageInfo(File file) async {
    final imageProvider = FileImage(file);
    final completer = Completer<ImageInfo>();
    final stream = imageProvider.resolve(const ImageConfiguration());

    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        completer.complete(info);
        stream.removeListener(listener);
      },
      onError: (error, stackTrace) {
        completer.completeError(error, stackTrace);
        stream.removeListener(listener);
      },
    );

    stream.addListener(listener);
    return completer.future;
  }
}

class DetectionOverlayPainter extends CustomPainter {
  final List<DetectionPoint> detections;
  final List<LedgerLineViewItem> ledgerLines;
  final double imageWidth;
  final double imageHeight;

  DetectionOverlayPainter({
    required this.detections,
    this.ledgerLines = const [],
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pointPaint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.60)
      ..style = PaintingStyle.fill;

    final baseRadius = size.shortestSide * 0.006;

    // Clamp to avoid too small or too big
    final innerRadius = baseRadius.clamp(1.8, 3.0);
    final outerRadius = (baseRadius * 1.7).clamp(3.0, 5.0);

    final ringPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = (innerRadius * 0.4).clamp(0.6, 1.2);

    for (final detection in detections) {
      if (detection.centerX < 0 ||
          detection.centerY < 0 ||
          detection.centerX > imageWidth ||
          detection.centerY > imageHeight) {
        continue;
      }

      final dx = (detection.centerX / imageWidth) * size.width;
      final dy = (detection.centerY / imageHeight) * size.height;

      canvas.drawCircle(Offset(dx, dy), innerRadius, pointPaint);
      canvas.drawCircle(Offset(dx, dy), outerRadius, ringPaint);
    }

    final ledgerPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (final ledger in ledgerLines) {
      final x1 = (ledger.x1 / imageWidth) * size.width;
      final x2 = (ledger.x2 / imageWidth) * size.width;
      final y = (ledger.y / imageHeight) * size.height;

      canvas.drawLine(Offset(x1, y), Offset(x2, y), ledgerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.ledgerLines != ledgerLines ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}

Widget _buildImageOrEmpty({
  required String? imagePath,
  required String emptyMessage,
}) {
  final exists = imagePath != null && File(imagePath).existsSync();

  if (!exists) {
    return _EmptyPanelMessage(message: emptyMessage);
  }

  return ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Container(
      color: AppColors.surface,
      child: InteractiveViewer(
        child: Center(child: Image.file(File(imagePath), fit: BoxFit.contain)),
      ),
    ),
  );
}

class _ClassListPanel extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<SymbolClassItem> items;

  const _ClassListPanel({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  @override
  State<_ClassListPanel> createState() => _ClassListPanelState();
}

class _ClassListPanelState extends State<_ClassListPanel> {
  String? _expandedClassKey;

  static const List<String> _classOrder = [
    'notehead',
    'treble_clef',
    'bass_clef',
    'sharp',
    'flat',
    'natural',
  ];

  @override
  Widget build(BuildContext context) {
    final grouped = _groupItemsByClass(widget.items);

    return Column(
      children: [
        _PanelHeader(title: widget.title, subtitle: widget.subtitle),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _classOrder.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final classKey = _classOrder[index];
              final classItems = grouped[classKey] ?? const <SymbolClassItem>[];
              final isExpanded = _expandedClassKey == classKey;

              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        setState(() {
                          _expandedClassKey = isExpanded ? null : classKey;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_formatClassName(classKey)} - ${classItems.length} detected',
                                style: AppTextStyles.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isExpanded) ...[
                      Container(height: 1, color: AppColors.divider),
                      if (classItems.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            'No detections under this class.',
                            style: AppTextStyles.bodySecondary,
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(14),
                          itemCount: classItems.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, itemIndex) {
                            final item = classItems[itemIndex];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${itemIndex + 1}. ${_formatClassName(classKey)}',
                                    style: AppTextStyles.body.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'center: (${item.x.toStringAsFixed(1)}, ${item.y.toStringAsFixed(1)})',
                                    style: AppTextStyles.bodySecondary,
                                  ),
                                  if (item.score != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'confidence: ${item.score!.toStringAsFixed(3)}',
                                      style: AppTextStyles.caption,
                                    ),
                                  ],
                                  if (item.bbox != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'bbox: [${item.bbox![0].toStringAsFixed(1)}, '
                                      '${item.bbox![1].toStringAsFixed(1)}, '
                                      '${item.bbox![2].toStringAsFixed(1)}, '
                                      '${item.bbox![3].toStringAsFixed(1)}]',
                                      style: AppTextStyles.caption,
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

Map<String, List<SymbolClassItem>> _groupItemsByClass(
  List<SymbolClassItem> items,
) {
  final Map<String, List<SymbolClassItem>> grouped = {
    'notehead': <SymbolClassItem>[],
    'treble_clef': <SymbolClassItem>[],
    'bass_clef': <SymbolClassItem>[],
    'sharp': <SymbolClassItem>[],
    'flat': <SymbolClassItem>[],
    'natural': <SymbolClassItem>[],
  };

  for (final item in items) {
    final key = item.className.trim().toLowerCase();
    if (grouped.containsKey(key)) {
      grouped[key]!.add(item);
    } else {
      grouped.putIfAbsent(key, () => <SymbolClassItem>[]).add(item);
    }
  }

  return grouped;
}

String _formatClassName(String raw) {
  switch (raw) {
    case 'notehead':
      return 'Notehead';
    case 'treble_clef':
      return 'Treble Clef';
    case 'bass_clef':
      return 'Bass Clef';
    case 'sharp':
      return 'Sharp';
    case 'flat':
      return 'Flat';
    case 'natural':
      return 'Natural';
    default:
      return raw
          .split('_')
          .map((part) {
            if (part.isEmpty) return part;
            return part[0].toUpperCase() + part.substring(1);
          })
          .join(' ');
  }
}

class _TranslatePanel extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<StaffTranslateGroup> groups;
  final List<NoteGroupViewItem> noteGroups;
  final List<RhythmEventViewItem> rhythmEvents;

  const _TranslatePanel({
    required this.title,
    required this.subtitle,
    required this.groups,
    required this.noteGroups,
    required this.rhythmEvents,
  });

  @override
  State<_TranslatePanel> createState() => _TranslatePanelState();
}

class _TranslatePanelState extends State<_TranslatePanel> {
  String? _expandedStaffId;
  int _selectedTranslateTab = 0; // 0 = Map, 1 = Note Group, 2 = Rhythm

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PanelHeader(title: widget.title, subtitle: widget.subtitle),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _TranslateTabButton(
                label: 'Map',
                selected: _selectedTranslateTab == 0,
                onTap: () {
                  setState(() {
                    _selectedTranslateTab = 0;
                  });
                },
              ),
              const SizedBox(width: 8),
              _TranslateTabButton(
                label: 'Note Group',
                selected: _selectedTranslateTab == 1,
                onTap: () {
                  setState(() {
                    _selectedTranslateTab = 1;
                  });
                },
              ),
              const SizedBox(width: 8),
              _TranslateTabButton(
                label: 'Rhythm',
                selected: _selectedTranslateTab == 2,
                onTap: () {
                  setState(() {
                    _selectedTranslateTab = 2;
                  });
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _selectedTranslateTab == 0
              ? _buildMapTab()
              : _selectedTranslateTab == 1
              ? _buildNoteGroupTab()
              : _buildRhythmTab(),
        ),
      ],
    );
  }

  Widget _buildMapTab() {
    return widget.groups.isEmpty
        ? const _EmptyPanelMessage(
            message: 'No translation data available yet.',
          )
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: widget.groups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final group = widget.groups[index];
              final isExpanded = _expandedStaffId == group.staffId;

              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        setState(() {
                          _expandedStaffId = isExpanded ? null : group.staffId;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    group.staffId,
                                    style: AppTextStyles.body.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${group.summary.lineCount} lines detected • '
                                    '${group.summary.symbolCount} symbols assigned • '
                                    '${group.summary.clefStatusLabel}',
                                    style: AppTextStyles.caption.copyWith(
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isExpanded) ...[
                      Container(height: 1, color: AppColors.divider),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            _TranslateBox(
                              title: 'Segment Map',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: group.segmentMap
                                    .map(
                                      (item) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 5,
                                        ),
                                        child: Text(
                                          '${item.id} -- ${item.yDisplay} -- ${item.defaultKeyLabel}',
                                          style: AppTextStyles.bodySecondary
                                              .copyWith(
                                                fontSize: 12,
                                                color: item.id.startsWith('v_')
                                                    ? Colors.lightBlueAccent
                                                    : null,
                                                fontStyle:
                                                    item.id.startsWith('v_')
                                                    ? FontStyle.italic
                                                    : null,
                                              ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _TranslateBox(
                              title: 'Symbol/s',
                              child: group.symbols.isEmpty
                                  ? Text(
                                      'No symbols assigned within this staff.',
                                      style: AppTextStyles.bodySecondary
                                          .copyWith(fontSize: 12),
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: group.symbols
                                          .where(
                                            (symbol) =>
                                                symbol.assignmentStatus !=
                                                'ledgerCandidate',
                                          )
                                          .map(
                                            (symbol) => Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 6,
                                              ),
                                              child: Text(
                                                _buildSymbolLine(symbol),
                                                style: AppTextStyles
                                                    .bodySecondary
                                                    .copyWith(fontSize: 12),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
  }

  Widget _buildNoteGroupTab() {
    return widget.noteGroups.isEmpty
        ? const _EmptyPanelMessage(message: 'No note groups available yet.')
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: widget.noteGroups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = widget.noteGroups[index];

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.staffId,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (item.groups.isEmpty)
                      Text(
                        'No grouped notes for this staff.',
                        style: AppTextStyles.bodySecondary.copyWith(
                          fontSize: 12,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: item.groups.map((group) {
                          final label = group.length == 1
                              ? group.first
                              : group.join(' + ');

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              '[$label]',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              );
            },
          );
  }

  Widget _buildRhythmTab() {
    return widget.rhythmEvents.isEmpty
        ? const _EmptyPanelMessage(
            message: 'No rhythm estimates available yet.',
          )
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: widget.rhythmEvents.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = widget.rhythmEvents[index];
              final measureLabel = item.measureIndex == null
                  ? 'Measure unknown'
                  : 'Measure ${item.measureIndex! + 1}';
              final timingLabel = _formatTimingSource(item.timingSource);
              final confidence = (item.confidence * 100).round();
              final geometry = [
                if (item.hasStem) 'stem',
                if (item.hasBeam) 'beam',
              ].join(' + ');

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.label,
                            style: AppTextStyles.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${item.durationBeats.toStringAsFixed(2)} beat',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${item.staffId} -- $measureLabel -- $timingLabel',
                      style: AppTextStyles.bodySecondary.copyWith(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      geometry.isEmpty
                          ? 'Estimated from spacing -- confidence $confidence%'
                          : 'Detected $geometry -- confidence $confidence%',
                      style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              );
            },
          );
  }

  String _buildSymbolLine(TranslatedSymbolViewItem symbol) {
    final confidenceText = symbol.score != null
        ? symbol.score!.toStringAsFixed(3)
        : 'n/a';

    final yText = 'y: ${symbol.centerY.toStringAsFixed(1)} px';

    if (symbol.className.trim().toLowerCase() == 'notehead') {
      return '${symbol.className} -- $yText -- $confidenceText -- '
          '${symbol.locationId} -- ${symbol.defaultKeyLabel ?? 'Unresolved'} -- '
          '${symbol.assignmentStatus}';
    }

    return '${symbol.className} -- $yText -- $confidenceText -- '
        '${symbol.locationId} -- ${symbol.assignmentStatus}';
  }

  String _formatTimingSource(String source) {
    switch (source) {
      case 'beam_geometry':
        return 'short note from beam shape';
      case 'stem_spacing_estimate':
        return 'stem with spacing estimate';
      case 'spacing_estimate':
        return 'spacing estimate';
      default:
        return source.replaceAll('_', ' ');
    }
  }
}

class _TranslateTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TranslateTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: selected ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _TranslateBox extends StatelessWidget {
  final String title;
  final Widget child;

  const _TranslateBox({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _GeneratePanel extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<GenerateOutputItem> outputs;
  final List<GrandStaffPairViewItem> grandStaffPairs;
  final List<PolyMonoViewItem> polyMonoResults;
  final List<MusicInterpretationViewItem> musicInterpretations;
  final List<FretboardMappingViewItem> fretboardMappings;
  final List<EventManagerViewItem> eventManagerResults;
  final List<ChordVoicingViewItem> chordVoicingResults;
  final List<GeneratedTabResult> generatedTabResults;
  final List<GeneratedTabViewItem> generatedTabs;
  final SessionData? session;

  const _GeneratePanel({
    required this.title,
    required this.subtitle,
    required this.outputs,
    required this.grandStaffPairs,
    required this.polyMonoResults,
    required this.musicInterpretations,
    required this.fretboardMappings,
    required this.eventManagerResults,
    required this.chordVoicingResults,
    required this.generatedTabResults,
    required this.generatedTabs,
    required this.session,
  });

  @override
  State<_GeneratePanel> createState() => _GeneratePanelState();
}

class _GeneratePanelState extends State<_GeneratePanel> {
  String? _expandedSectionId = 'grand_staff';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PanelHeader(title: widget.title, subtitle: widget.subtitle),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildGenerateSection(
                sectionId: 'grand_staff',
                title: 'Grand Staff Pairing',
                subtitle: '${widget.grandStaffPairs.length} pairs prepared',
                child: _buildGrandStaffPairsContent(),
              ),
              const SizedBox(height: 10),
              _buildGenerateSection(
                sectionId: 'poly_mono',
                title: 'Poly-Mono',
                subtitle: '${widget.polyMonoResults.length} results prepared',
                child: _buildPolyMonoContent(),
              ),
              const SizedBox(height: 10),
              _buildGenerateSection(
                sectionId: 'music_interpretation',
                title: 'Musical Interpretation',
                subtitle:
                    '${widget.musicInterpretations.length} structures prepared',
                child: _buildMusicInterpretationContent(),
              ),
              const SizedBox(height: 10),
              _buildGenerateSection(
                sectionId: 'fretboard_mapping',
                title: 'Fretboard Mapping',
                subtitle:
                    '${widget.fretboardMappings.length} mapped structures prepared',
                child: _buildFretboardMappingContent(),
              ),
              const SizedBox(height: 10),
              _buildGenerateSection(
                sectionId: 'event_manager',
                title: 'Event Manager',
                subtitle:
                    '${widget.eventManagerResults.length} optimized lines prepared',
                child: _buildEventManagerContent(),
              ),
              const SizedBox(height: 10),
              _buildGenerateSection(
                sectionId: 'chord_voicing',
                title: 'Chord Voicing',
                subtitle:
                    '${widget.chordVoicingResults.length} voiced lines prepared',
                child: _buildChordVoicingContent(),
              ),
              const SizedBox(height: 10),
              _buildGenerateSection(
                sectionId: 'generated_tabs',
                title: 'Generated Tabs',
                subtitle:
                    '${widget.generatedTabs.length} generated tab outputs prepared',
                child: _buildGeneratedTabsContent(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGenerateSection({
    required String sectionId,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final isExpanded = _expandedSectionId == sectionId;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              setState(() {
                _expandedSectionId = isExpanded ? null : sectionId;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Container(height: 1, color: AppColors.divider),
            Padding(padding: const EdgeInsets.all(14), child: child),
          ],
        ],
      ),
    );
  }

  Widget _buildGrandStaffPairsContent() {
    if (widget.grandStaffPairs.isEmpty) {
      return Text(
        'No grand staff pairs available yet.',
        style: AppTextStyles.bodySecondary.copyWith(fontSize: 12),
      );
    }

    return Column(
      children: widget.grandStaffPairs.map((pair) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _TranslateBox(
            title: pair.id,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Treble (${pair.trebleStaffId})',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _buildGroupWrap(pair.trebleGroups),
                const SizedBox(height: 10),
                if (pair.bassStaffId != null) ...[
                  Text(
                    'Bass (${pair.bassStaffId})',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildGroupWrap(pair.bassGroups),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPolyMonoContent() {
    if (widget.polyMonoResults.isEmpty) {
      return Text(
        'No poly-mono result available yet.',
        style: AppTextStyles.bodySecondary.copyWith(fontSize: 12),
      );
    }

    return Column(
      children: widget.polyMonoResults.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _TranslateBox(
            title: item.grandStaffId,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'H-detr Harmonic Stacks',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _buildGroupWrap(item.harmonicStacks),
                const SizedBox(height: 12),

                Text(
                  'H-detr Chord-Aware',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _buildTextWrap(item.chordAwareStacks),
                const SizedBox(height: 12),
                Text(
                  'M-prio (Strict)',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _buildGroupWrap(item.strictMelody.map((p) => [p]).toList()),

                const SizedBox(height: 12),

                Text(
                  'M-prio (Continuity)',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _buildGroupWrap(item.continuityMelody.map((p) => [p]).toList()),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMusicInterpretationContent() {
    if (widget.musicInterpretations.isEmpty) {
      return Text(
        'No interpreted music structures available yet.',
        style: AppTextStyles.bodySecondary.copyWith(fontSize: 12),
      );
    }

    return Column(
      children: widget.musicInterpretations.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _TranslateBox(
            title: item.title,
            child: _buildTextWrap(
              item.labels.isEmpty ? ['Empty'] : item.labels,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFretboardMappingContent() {
    if (widget.fretboardMappings.isEmpty) {
      return Text(
        'No fretboard mapping results available yet.',
        style: AppTextStyles.bodySecondary.copyWith(fontSize: 12),
      );
    }

    return Column(
      children: widget.fretboardMappings.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _TranslateBox(
            title: item.title,
            child: _buildTextWrap(
              item.eventSummaries.isEmpty
                  ? ['No mapped events']
                  : item.eventSummaries,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEventManagerContent() {
    if (widget.eventManagerResults.isEmpty) {
      return Text(
        'No optimized playable events available yet.',
        style: AppTextStyles.bodySecondary.copyWith(fontSize: 12),
      );
    }

    return Column(
      children: widget.eventManagerResults.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _TranslateBox(
            title: '${item.title} • cost ${item.totalCost}',
            child: _buildTextWrap(
              item.events.isEmpty ? ['No playable events'] : item.events,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildChordVoicingContent() {
    if (widget.chordVoicingResults.isEmpty) {
      return Text(
        'No chord voicing results available yet.',
        style: AppTextStyles.bodySecondary.copyWith(fontSize: 12),
      );
    }

    return Column(
      children: widget.chordVoicingResults.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _TranslateBox(
            title: item.title,
            child: _buildTextWrap(
              item.events.isEmpty ? ['No voiced chord events'] : item.events,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGeneratedTabsContent() {
    if (widget.generatedTabs.isEmpty) {
      return Text(
        'No generated tab result available yet.',
        style: AppTextStyles.bodySecondary.copyWith(fontSize: 12),
      );
    }

    final session = widget.session;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton(
          onPressed: widget.generatedTabResults.isEmpty || session == null
              ? null
              : () async {
                  final shouldRefreshHome = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ResultPage(
                        session: session,
                        generatedTabs: widget.generatedTabResults,
                      ),
                    ),
                  );

                  if (!mounted) return;

                  if (shouldRefreshHome == true) {
                    Navigator.pop(context, true);
                  }
                },
          child: const Text('Open Result Page'),
        ),
        const SizedBox(height: 12),

        ...widget.generatedTabs.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TranslateBox(
              title: item.mode,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Columns: ${item.columns}',
                    style: AppTextStyles.caption,
                  ),
                  Text(
                    'Fretboard Frames: ${item.fretboardFrames}',
                    style: AppTextStyles.caption,
                  ),
                  Text(
                    'Export Pages: ${item.exportPages}',
                    style: AppTextStyles.caption,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.firstEventSummary,
                    style: AppTextStyles.bodySecondary.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildGroupWrap(List<List<String>> groups) {
    if (groups.isEmpty) {
      return Text(
        'No notes',
        style: AppTextStyles.bodySecondary.copyWith(fontSize: 12),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: groups.map((group) {
        final label = group.length == 1 ? group.first : group.join(' + ');

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            '[$label]',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextWrap(List<String> items) {
    if (items.isEmpty) {
      return Text(
        'No chord-aware stacks available.',
        style: AppTextStyles.bodySecondary.copyWith(fontSize: 12),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((text) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            text,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _EmptyPanelMessage extends StatelessWidget {
  final String message;

  const _EmptyPanelMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySecondary,
        ),
      ),
    );
  }
}
