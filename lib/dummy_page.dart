import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_text_styles.dart';
import 'models/translation_group_models.dart';
import 'models/session_data.dart';
import 'result_page.dart';
import 'services/generation_service.dart';
import 'services/processing_session_navigation.dart';

enum DummyViewOption {
  inputCrop,
  onnxDetection,
  staffValidation,
  structuralSegmentation,
  musicalInterpretation,
  tablatureGeneration,
  reports,
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
  final SymbolState symbolState;
  final String? validationReason;
  final String? inferredReason;

  const SymbolClassItem({
    required this.className,
    required this.x,
    required this.y,
    this.score,
    this.bbox,
    this.symbolState = SymbolState.detected,
    this.validationReason,
    this.inferredReason,
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

  const PolyMonoViewItem({
    required this.grandStaffId,
    required this.harmonicStacks,
    required this.chordAwareStacks,
    required this.strictMelody,
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
  final List<Map<String, dynamic>> staffOverlays;
  final List<Map<String, dynamic>> barLineOverlays;
  final List<Map<String, dynamic>> stemOverlays;
  final List<Map<String, dynamic>> beamOverlays;
  final List<Map<String, dynamic>> semanticRegions;
  final List<Map<String, dynamic>> clefSafetyRegions;
  final List<Map<String, dynamic>> rejectedNoteheads;
  final Map<String, dynamic> pipelineReport;
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
  final VoidCallback? onRetry;
  final bool replaceWithResultPage;

  const DummyPage({
    super.key,
    this.croppedImagePath,
    this.detectedImagePath,
    this.segmentedImagePath,
    this.detections = const [],
    this.ledgerLines = const [],
    this.classItems = const [],
    this.staffOverlays = const [],
    this.barLineOverlays = const [],
    this.stemOverlays = const [],
    this.beamOverlays = const [],
    this.semanticRegions = const [],
    this.clefSafetyRegions = const [],
    this.rejectedNoteheads = const [],
    this.pipelineReport = const {},
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
    this.onRetry,
    this.replaceWithResultPage = false,
  });

  @override
  State<DummyPage> createState() => _DummyPageState();
}

class _DummyPageState extends State<DummyPage> {
  DummyViewOption _selectedOption = DummyViewOption.inputCrop;

  @override
  void initState() {
    super.initState();
    final sessionId = widget.session?.id;
    if (sessionId != null && sessionId.isNotEmpty) {
      ProcessingSessionNavigation.enterDebug(sessionId);
    }
  }

  @override
  void dispose() {
    final sessionId = widget.session?.id;
    if (sessionId != null && sessionId.isNotEmpty) {
      ProcessingSessionNavigation.exitDebug(sessionId);
    }
    super.dispose();
  }

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
        actions: [
          if (widget.onRetry != null)
            TextButton.icon(
              onPressed: widget.onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
              ),
            ),
        ],
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
      case DummyViewOption.inputCrop:
        return _ImagePanel(
          title: 'A. Input & Crop',
          subtitle: 'Frozen cropped image used by the pipeline',
          imagePath: widget.croppedImagePath,
          emptyMessage: 'No cropped image available yet.',
        );

      case DummyViewOption.onnxDetection:
        return _DetectedPanel(
          title: 'B. Detection Results',
          subtitle: 'Raw multiclass symbol detection in locked image space',
          imagePath: widget.detectedImagePath,
          detections: widget.detections,
        );

      case DummyViewOption.staffValidation:
        return _SegmentOverlayPanel(
          title: 'C. Staff Validation',
          subtitle: 'Locked staff geometry validation',
          imagePath:
              widget.detectedImagePath ??
              widget.croppedImagePath ??
              widget.segmentedImagePath,
          staffs: widget.staffOverlays,
          symbols: const [],
          translateGroups: const [],
          ledgerLines: const [],
          barLines: const [],
          stems: const [],
          beams: const [],
          semanticRegions: const [],
          clefSafetyRegions: const [],
          rejectedNoteheads: const [],
          geometryOnly: true,
        );

      case DummyViewOption.structuralSegmentation:
        return _SegmentOverlayPanel(
          title: 'D. Structural Segmentation',
          subtitle: 'Staff geometry, symbols, and structural overlays',
          imagePath:
              widget.detectedImagePath ??
              widget.croppedImagePath ??
              widget.segmentedImagePath,
          staffs: widget.staffOverlays,
          symbols: widget.classItems,
          translateGroups: widget.translateGroups,
          ledgerLines: widget.ledgerLines,
          barLines: widget.barLineOverlays,
          stems: widget.stemOverlays,
          beams: widget.beamOverlays,
          semanticRegions: widget.semanticRegions,
          clefSafetyRegions: widget.clefSafetyRegions,
          rejectedNoteheads: widget.rejectedNoteheads,
        );

      case DummyViewOption.musicalInterpretation:
        return _TranslatePanel(
          title: 'E. Musical Interpretation',
          subtitle: 'Grouped translation result by staff line',
          groups: widget.translateGroups,
          noteGroups: widget.noteGroups,
          rhythmEvents: widget.rhythmEvents,
        );

      case DummyViewOption.tablatureGeneration:
        return _GeneratePanel(
          title: 'F. Tablature Generation',
          subtitle:
              'Downstream interpretation, mapping, generation, and export data',
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
          replaceWithResultPage: widget.replaceWithResultPage,
        );

      case DummyViewOption.reports:
        return _ReportPanel(
          title: 'G. Reports',
          subtitle: 'Structured validation and translation report',
          report: widget.pipelineReport,
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
              value: DummyViewOption.inputCrop,
              child: Text('Input & Crop'),
            ),
            DropdownMenuItem(
              value: DummyViewOption.onnxDetection,
              child: Text('Detection Results'),
            ),
            DropdownMenuItem(
              value: DummyViewOption.staffValidation,
              child: Text('Staff Validation'),
            ),
            DropdownMenuItem(
              value: DummyViewOption.structuralSegmentation,
              child: Text('Structural Segmentation'),
            ),
            DropdownMenuItem(
              value: DummyViewOption.musicalInterpretation,
              child: Text('Musical Interpretation'),
            ),
            DropdownMenuItem(
              value: DummyViewOption.tablatureGeneration,
              child: Text('Tablature Generation'),
            ),
            DropdownMenuItem(
              value: DummyViewOption.reports,
              child: Text('Reports'),
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

class _SegmentOverlaySettings {
  final bool showStaffLines;
  final bool showSymbols;
  final bool showLedgerLines;
  final bool showBarlines;
  final bool showBoundaries;
  final bool showStems;
  final bool showBeams;
  final bool showSemanticRegions;
  final bool showClefSafetyRegions;
  final bool showRejected;
  final double originalOpacity;

  const _SegmentOverlaySettings({
    this.showStaffLines = true,
    this.showSymbols = true,
    this.showLedgerLines = true,
    this.showBarlines = true,
    this.showBoundaries = true,
    this.showStems = false,
    this.showBeams = false,
    this.showSemanticRegions = true,
    this.showClefSafetyRegions = true,
    this.showRejected = true,
    this.originalOpacity = 1.0,
  });

  _SegmentOverlaySettings copyWith({
    bool? showStaffLines,
    bool? showSymbols,
    bool? showLedgerLines,
    bool? showBarlines,
    bool? showBoundaries,
    bool? showStems,
    bool? showBeams,
    bool? showSemanticRegions,
    bool? showClefSafetyRegions,
    bool? showRejected,
    double? originalOpacity,
  }) {
    return _SegmentOverlaySettings(
      showStaffLines: showStaffLines ?? this.showStaffLines,
      showSymbols: showSymbols ?? this.showSymbols,
      showLedgerLines: showLedgerLines ?? this.showLedgerLines,
      showBarlines: showBarlines ?? this.showBarlines,
      showBoundaries: showBoundaries ?? this.showBoundaries,
      showStems: showStems ?? this.showStems,
      showBeams: showBeams ?? this.showBeams,
      showSemanticRegions: showSemanticRegions ?? this.showSemanticRegions,
      showClefSafetyRegions:
          showClefSafetyRegions ?? this.showClefSafetyRegions,
      showRejected: showRejected ?? this.showRejected,
      originalOpacity: originalOpacity ?? this.originalOpacity,
    );
  }
}

class _SegmentOverlayPanel extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? imagePath;
  final List<Map<String, dynamic>> staffs;
  final List<SymbolClassItem> symbols;
  final List<StaffTranslateGroup> translateGroups;
  final List<LedgerLineViewItem> ledgerLines;
  final List<Map<String, dynamic>> barLines;
  final List<Map<String, dynamic>> stems;
  final List<Map<String, dynamic>> beams;
  final List<Map<String, dynamic>> semanticRegions;
  final List<Map<String, dynamic>> clefSafetyRegions;
  final List<Map<String, dynamic>> rejectedNoteheads;
  final bool geometryOnly;

  const _SegmentOverlayPanel({
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.staffs,
    required this.symbols,
    required this.translateGroups,
    required this.ledgerLines,
    required this.barLines,
    required this.stems,
    required this.beams,
    required this.semanticRegions,
    required this.clefSafetyRegions,
    required this.rejectedNoteheads,
    this.geometryOnly = false,
  });

  @override
  State<_SegmentOverlayPanel> createState() => _SegmentOverlayPanelState();
}

class _SegmentOverlayPanelState extends State<_SegmentOverlayPanel> {
  _SegmentOverlaySettings _settings = const _SegmentOverlaySettings();

  @override
  Widget build(BuildContext context) {
    final exists =
        widget.imagePath != null && File(widget.imagePath!).existsSync();

    return Column(
      children: [
        _PanelHeader(title: widget.title, subtitle: widget.subtitle),
        _buildControls(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: !exists
                ? const _EmptyPanelMessage(
                    message: 'No segment image available yet.',
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      color: Colors.black,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return InteractiveViewer(
                            child: Center(
                              child: _SegmentImageWithOverlay(
                                imagePath: widget.imagePath!,
                                settings: _settings,
                                staffs: widget.staffs,
                                symbols: widget.symbols,
                                translateGroups: widget.translateGroups,
                                ledgerLines: widget.ledgerLines,
                                barLines: widget.barLines,
                                stems: widget.stems,
                                beams: widget.beams,
                                semanticRegions: widget.semanticRegions,
                                clefSafetyRegions: widget.clefSafetyRegions,
                                rejectedNoteheads: widget.rejectedNoteheads,
                                maxWidth: constraints.maxWidth,
                                maxHeight: constraints.maxHeight,
                              ),
                            ),
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

  Widget _buildControls() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _toggle('Staff Lines', _settings.showStaffLines, (value) {
                _update(_settings.copyWith(showStaffLines: value));
              }),
              _toggle('Staff Boundaries', _settings.showBoundaries, (value) {
                _update(_settings.copyWith(showBoundaries: value));
              }),
              if (!widget.geometryOnly) ...[
                _toggle('Symbols', _settings.showSymbols, (value) {
                  _update(_settings.copyWith(showSymbols: value));
                }),
                _toggle('Ledger Lines', _settings.showLedgerLines, (value) {
                  _update(_settings.copyWith(showLedgerLines: value));
                }),
                _toggle('Barlines', _settings.showBarlines, (value) {
                  _update(_settings.copyWith(showBarlines: value));
                }),
                _toggle('Stems', _settings.showStems, (value) {
                  _update(_settings.copyWith(showStems: value));
                }),
                _toggle('Beams', _settings.showBeams, (value) {
                  _update(_settings.copyWith(showBeams: value));
                }),
                _toggle('Semantic Regions', _settings.showSemanticRegions, (
                  value,
                ) {
                  _update(_settings.copyWith(showSemanticRegions: value));
                }),
                _toggle('Clef Safety', _settings.showClefSafetyRegions, (
                  value,
                ) {
                  _update(_settings.copyWith(showClefSafetyRegions: value));
                }),
                _toggle('Rejected', _settings.showRejected, (value) {
                  _update(_settings.copyWith(showRejected: value));
                }),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 112,
                child: Text('Original opacity', style: AppTextStyles.caption),
              ),
              Expanded(
                child: Slider(
                  value: _settings.originalOpacity,
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  activeColor: AppColors.accent,
                  inactiveColor: AppColors.border,
                  onChanged: (value) {
                    _update(_settings.copyWith(originalOpacity: value));
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return SizedBox(
      width: 150,
      height: 30,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(4),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Checkbox(
                value: value,
                onChanged: (next) => onChanged(next ?? false),
                activeColor: AppColors.accent,
                checkColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _update(_SegmentOverlaySettings settings) {
    setState(() {
      _settings = settings;
    });
  }
}

class _SegmentImageWithOverlay extends StatelessWidget {
  final String imagePath;
  final _SegmentOverlaySettings settings;
  final List<Map<String, dynamic>> staffs;
  final List<SymbolClassItem> symbols;
  final List<StaffTranslateGroup> translateGroups;
  final List<LedgerLineViewItem> ledgerLines;
  final List<Map<String, dynamic>> barLines;
  final List<Map<String, dynamic>> stems;
  final List<Map<String, dynamic>> beams;
  final List<Map<String, dynamic>> semanticRegions;
  final List<Map<String, dynamic>> clefSafetyRegions;
  final List<Map<String, dynamic>> rejectedNoteheads;
  final double maxWidth;
  final double maxHeight;

  const _SegmentImageWithOverlay({
    required this.imagePath,
    required this.settings,
    required this.staffs,
    required this.symbols,
    required this.translateGroups,
    required this.ledgerLines,
    required this.barLines,
    required this.stems,
    required this.beams,
    required this.semanticRegions,
    required this.clefSafetyRegions,
    required this.rejectedNoteheads,
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

        return SizedBox(
          width: fitted.destination.width,
          height: fitted.destination.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: settings.originalOpacity > 0
                      ? AppColors.surface
                      : Colors.black,
                ),
              ),
              if (settings.originalOpacity > 0)
                Positioned.fill(
                  child: Opacity(
                    opacity: settings.originalOpacity,
                    child: Image.file(file, fit: BoxFit.contain),
                  ),
                ),
              Positioned.fill(
                child: CustomPaint(
                  painter: SegmentOverlayPainter(
                    settings: settings,
                    staffs: staffs,
                    symbols: symbols,
                    translateGroups: translateGroups,
                    ledgerLines: ledgerLines,
                    barLines: barLines,
                    stems: stems,
                    beams: beams,
                    semanticRegions: semanticRegions,
                    clefSafetyRegions: clefSafetyRegions,
                    rejectedNoteheads: rejectedNoteheads,
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

class SegmentOverlayPainter extends CustomPainter {
  final _SegmentOverlaySettings settings;
  final List<Map<String, dynamic>> staffs;
  final List<SymbolClassItem> symbols;
  final List<StaffTranslateGroup> translateGroups;
  final List<LedgerLineViewItem> ledgerLines;
  final List<Map<String, dynamic>> barLines;
  final List<Map<String, dynamic>> stems;
  final List<Map<String, dynamic>> beams;
  final List<Map<String, dynamic>> semanticRegions;
  final List<Map<String, dynamic>> clefSafetyRegions;
  final List<Map<String, dynamic>> rejectedNoteheads;
  final double imageWidth;
  final double imageHeight;

  SegmentOverlayPainter({
    required this.settings,
    required this.staffs,
    required this.symbols,
    required this.translateGroups,
    required this.ledgerLines,
    required this.barLines,
    required this.stems,
    required this.beams,
    required this.semanticRegions,
    required this.clefSafetyRegions,
    required this.rejectedNoteheads,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double sx(double x) => (x / imageWidth) * size.width;
    double sy(double y) => (y / imageHeight) * size.height;

    final assigned = translateGroups.expand((group) => group.symbols).toList();

    if (settings.showBoundaries) {
      final fillPaint = Paint()
        ..color = Colors.purpleAccent.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = Colors.purpleAccent.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7;

      for (final staff in staffs) {
        final top = _toDouble(staff['topBoundary']);
        final bottom = _toDouble(staff['bottomBoundary']);
        if (top == null || bottom == null) continue;
        final rect = Rect.fromLTRB(0, sy(top), size.width, sy(bottom));
        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, strokePaint);
      }
    }

    if (settings.showSemanticRegions) {
      final fillPaint = Paint()
        ..color = Colors.amberAccent.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = Colors.amberAccent.withValues(alpha: 0.42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7;

      for (final region in semanticRegions) {
        final x1 = _toDouble(region['x1']);
        final x2 = _toDouble(region['x2']);
        final y1 = _toDouble(region['y1']);
        final y2 = _toDouble(region['y2']);
        if (x1 == null || x2 == null || y1 == null || y2 == null) continue;
        final rect = Rect.fromLTRB(sx(x1), sy(y1), sx(x2), sy(y2));
        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, strokePaint);
      }
    }

    if (settings.showClefSafetyRegions) {
      final fillPaint = Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;

      for (final region in clefSafetyRegions) {
        final x1 = _toDouble(region['x1']);
        final x2 = _toDouble(region['x2']);
        final y1 = _toDouble(region['y1']);
        final y2 = _toDouble(region['y2']);
        if (x1 == null || x2 == null || y1 == null || y2 == null) continue;
        final rect = Rect.fromLTRB(sx(x1), sy(y1), sx(x2), sy(y2));
        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, strokePaint);
      }
    }

    if (settings.showStaffLines) {
      final linePaint = Paint()
        ..color = Colors.grey.withValues(alpha: 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9;

      for (final staff in staffs) {
        final rawLines = staff['lines'];
        if (rawLines is! List) continue;
        for (final line in rawLines) {
          final y = _toDouble(line);
          if (y == null) continue;
          canvas.drawLine(
            Offset(0, sy(y)),
            Offset(size.width, sy(y)),
            linePaint,
          );
        }
      }
    }

    if (settings.showLedgerLines) {
      final ledgerPaint = Paint()
        ..color = const Color(0xffff5131).withValues(alpha: 0.78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      for (final ledger in ledgerLines) {
        canvas.drawLine(
          Offset(sx(ledger.x1), sy(ledger.y)),
          Offset(sx(ledger.x2), sy(ledger.y)),
          ledgerPaint,
        );
      }
    }

    if (settings.showBarlines) {
      final barPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      for (final bar in barLines) {
        final x = _toDouble(bar['x']);
        final y1 = _toDouble(bar['y1']);
        final y2 = _toDouble(bar['y2']);
        if (x == null || y1 == null || y2 == null) continue;
        canvas.drawLine(Offset(sx(x), sy(y1)), Offset(sx(x), sy(y2)), barPaint);
      }
    }

    if (settings.showStems) {
      final stemPaint = Paint()
        ..color = Colors.tealAccent.withValues(alpha: 0.60)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      for (final stem in stems) {
        final x = _toDouble(stem['x']);
        final y1 = _toDouble(stem['y1']);
        final y2 = _toDouble(stem['y2']);
        if (x == null || y1 == null || y2 == null) continue;
        canvas.drawLine(
          Offset(sx(x), sy(y1)),
          Offset(sx(x), sy(y2)),
          stemPaint,
        );
      }
    }

    if (settings.showBeams) {
      final beamPaint = Paint()
        ..color = Colors.lightBlueAccent.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      for (final beam in beams) {
        final x1 = _toDouble(beam['x1']);
        final x2 = _toDouble(beam['x2']);
        final y = _toDouble(beam['y']);
        if (x1 == null || x2 == null || y == null) continue;
        canvas.drawLine(
          Offset(sx(x1), sy(y)),
          Offset(sx(x2), sy(y)),
          beamPaint,
        );
      }
    }

    if (settings.showSymbols) {
      for (final symbol in symbols) {
        final isAssigned = assigned.any((item) {
          return item.className == symbol.className &&
              (item.centerX - symbol.x).abs() <= 2.0 &&
              (item.centerY - symbol.y).abs() <= 2.0;
        });

        final paint = Paint()
          ..color = _symbolDebugColor(
            symbol.className,
            symbolState: symbol.symbolState,
          ).withValues(alpha: isAssigned ? 0.76 : 0.58)
          ..style = PaintingStyle.stroke
          ..strokeWidth = symbol.symbolState == SymbolState.inferred
              ? 1.4
              : 0.9;

        if (symbol.bbox != null && symbol.bbox!.length >= 4) {
          final bbox = symbol.bbox!;
          canvas.drawRect(
            Rect.fromLTRB(sx(bbox[0]), sy(bbox[1]), sx(bbox[2]), sy(bbox[3])),
            paint,
          );
        } else {
          canvas.drawCircle(Offset(sx(symbol.x), sy(symbol.y)), 4.0, paint);
        }
      }
    }

    if (settings.showRejected) {
      final rejectedPaint = Paint()
        ..color = const Color(0xff8b0000).withValues(alpha: 0.62)
        ..style = PaintingStyle.fill;
      final rejectedStroke = Paint()
        ..color = const Color(0xff8b0000).withValues(alpha: 0.88)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9;

      for (final rejected in rejectedNoteheads) {
        final bbox = rejected['bbox'];
        final x = _toDouble(rejected['centerX'] ?? rejected['x']);
        final y = _toDouble(rejected['centerY'] ?? rejected['y']);
        if (bbox is List && bbox.length >= 4) {
          final x1 = _toDouble(bbox[0]);
          final y1 = _toDouble(bbox[1]);
          final x2 = _toDouble(bbox[2]);
          final y2 = _toDouble(bbox[3]);
          if (x1 == null || y1 == null || x2 == null || y2 == null) continue;
          final rect = Rect.fromLTRB(sx(x1), sy(y1), sx(x2), sy(y2));
          canvas.drawRect(rect, rejectedPaint);
          canvas.drawRect(rect, rejectedStroke);
        } else if (x != null && y != null) {
          canvas.drawCircle(Offset(sx(x), sy(y)), 4.0, rejectedPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant SegmentOverlayPainter oldDelegate) {
    return oldDelegate.settings != settings ||
        oldDelegate.staffs != staffs ||
        oldDelegate.symbols != symbols ||
        oldDelegate.translateGroups != translateGroups ||
        oldDelegate.ledgerLines != ledgerLines ||
        oldDelegate.barLines != barLines ||
        oldDelegate.stems != stems ||
        oldDelegate.beams != beams ||
        oldDelegate.semanticRegions != semanticRegions ||
        oldDelegate.rejectedNoteheads != rejectedNoteheads ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}

Color _symbolDebugColor(
  String className, {
  SymbolState symbolState = SymbolState.detected,
}) {
  if (symbolState == SymbolState.inferred) {
    return Colors.limeAccent;
  }
  if (symbolState == SymbolState.rejected) {
    return const Color(0xff8b0000);
  }

  switch (className.trim().toLowerCase()) {
    case 'treble_clef':
      return Colors.lightGreenAccent;
    case 'bass_clef':
      return Colors.green.shade800;
    case 'notehead':
      return Colors.cyanAccent;
    case 'sharp':
      return Colors.orangeAccent;
    case 'flat':
      return Colors.yellowAccent;
    case 'natural':
      return Colors.purpleAccent;
    default:
      return Colors.redAccent;
  }
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
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
    final stateText = symbol.symbolState.name;
    final reasonText = symbol.inferredReason == null
        ? ''
        : ' -- ${symbol.inferredReason}';

    if (symbol.className.trim().toLowerCase() == 'notehead') {
      return '${symbol.className} -- $yText -- $confidenceText -- '
          '${symbol.locationId} -- ${symbol.defaultKeyLabel ?? 'Unresolved'} -- '
          '${symbol.assignmentStatus} -- $stateText$reasonText';
    }

    return '${symbol.className} -- $yText -- $confidenceText -- '
        '${symbol.locationId} -- ${symbol.assignmentStatus} -- $stateText$reasonText';
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

class _ReportPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Map<String, dynamic> report;

  const _ReportPanel({
    required this.title,
    required this.subtitle,
    required this.report,
  });

  @override
  Widget build(BuildContext context) {
    final sections = [
      _ReportSectionData('Staff Report', report['staff']),
      _ReportSectionData('Symbol Report', report['symbols']),
      _ReportSectionData('Segment Report', report['segments']),
      _ReportSectionData('Ledger Report', report['ledger']),
      _ReportSectionData('Validation Report', report['validation']),
      _ReportSectionData('Translation Report', report['translation']),
      _ReportSectionData('Coordinate Lock', report['coordinates']),
    ];

    return Column(
      children: [
        _PanelHeader(title: title, subtitle: subtitle),
        Expanded(
          child: report.isEmpty
              ? const _EmptyPanelMessage(
                  message: 'No report data available yet.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: sections.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final section = sections[index];
                    return _ReportSection(
                      title: section.title,
                      data: section.data,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ReportSectionData {
  final String title;
  final Object? data;

  const _ReportSectionData(this.title, this.data);
}

class _ReportSection extends StatelessWidget {
  final String title;
  final Object? data;

  const _ReportSection({required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
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
            title,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ..._reportLines(data).map((line) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                line,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

List<String> _reportLines(Object? data) {
  if (data == null) return const ['No data'];
  if (data is List) {
    if (data.isEmpty) return const ['No entries'];
    return data.take(80).map(_formatReportValue).toList(growable: false);
  }
  if (data is Map) {
    if (data.isEmpty) return const ['No entries'];
    return data.entries
        .map((entry) {
          return '${entry.key}: ${_formatReportValue(entry.value)}';
        })
        .toList(growable: false);
  }
  return [_formatReportValue(data)];
}

String _formatReportValue(Object? value) {
  if (value == null) return '-';
  if (value is num) return value.toStringAsFixed(value is int ? 0 : 2);
  if (value is List) {
    return value.map(_formatReportValue).join(', ');
  }
  if (value is Map) {
    return value.entries
        .map((entry) {
          return '${entry.key}=${_formatReportValue(entry.value)}';
        })
        .join(' | ');
  }
  return value.toString();
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
  final bool replaceWithResultPage;

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
    required this.replaceWithResultPage,
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
                  'Grand Staff',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _buildTextWrap(item.chordAwareStacks),
                const SizedBox(height: 12),
                Text(
                  'Treble Only',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _buildGroupWrap(item.strictMelody.map((p) => [p]).toList()),
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
                  if (!widget.replaceWithResultPage) {
                    Navigator.pop(context, 'openResult');
                    return;
                  }

                  ProcessingSessionNavigation.logTransition(
                    session.id,
                    debugReused: true,
                    resultReused: true,
                  );
                  final shouldRefreshHome =
                      await Navigator.pushReplacement<bool, bool>(
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
