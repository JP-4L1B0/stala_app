import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/session_data.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_text_styles.dart';
import 'data/debug_settings_repository.dart';
import 'result_page.dart';
import 'dummy_page.dart';
import 'services/staff_segmentation_service.dart';
import 'services/barline_refinement_service.dart';
import 'models/translation_group_models.dart';
import 'services/translation_grouping_service.dart';
import 'services/note_grouping_service.dart';
import 'services/grand_staff_pairing_service.dart';
import 'services/polyphonic_to_monophonic_service.dart';
import 'services/musical_interpretation_service.dart';
import 'services/fretboard_mapping_service.dart';
import 'services/event_manager_service.dart';
import 'services/rhythm_interpretation_service.dart';
import 'services/tablature_result_adapter.dart';
import 'services/generation_service.dart';
import 'services/save_export_service.dart';
import 'data/app_settings_repository.dart';
import 'services/tutorial_service.dart';

/// Processing screen shown after the image crop is confirmed.
///
/// Responsibilities:
/// - display overall processing progress
/// - show each pipeline stage and its status
/// - simulate the current workflow for UI development
/// - bridge to the native OpenCV/ONNX vision pipeline
class ProcessingPage extends StatefulWidget {
  final String sourceImagePath;
  final String croppedImagePath;

  const ProcessingPage({
    super.key,
    required this.sourceImagePath,
    required this.croppedImagePath,
  });

  @override
  State<ProcessingPage> createState() => _ProcessingPageState();
}

/// High-level state of one processing stage in the pipeline.
enum ProcessingStageStatus { pending, active, completed, failed }

/// UI model for a single pipeline stage row.
class ProcessingStageItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final ProcessingStageStatus status;

  const ProcessingStageItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.status,
  });

  ProcessingStageItem copyWith({
    String? title,
    String? subtitle,
    IconData? icon,
    ProcessingStageStatus? status,
  }) {
    return ProcessingStageItem(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      icon: icon ?? this.icon,
      status: status ?? this.status,
    );
  }
}

class SheetInterpretationException implements Exception {
  final String message;

  const SheetInterpretationException(this.message);

  @override
  String toString() => message;
}

class _SymbolGeometry {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double centerX;
  final double centerY;

  const _SymbolGeometry({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.centerX,
    required this.centerY,
  });

  double get width => (x2 - x1).abs();
  double get height => (y2 - y1).abs();
}

enum StemAttachmentType { leftEdge, rightEdge, center, unknown }

class _StemAttachmentAnalysis {
  final StemAttachmentType type;
  final Map<String, dynamic>? stem;
  final double? stemCenterX;

  const _StemAttachmentAnalysis({
    required this.type,
    required this.stem,
    required this.stemCenterX,
  });
}

class _DetectionFilterResult {
  final List<Map<String, dynamic>> symbolGraph;
  final List<Map<String, dynamic>> translationDetections;
  final List<Map<String, dynamic>> rejectedNoteheads;
  final List<Map<String, dynamic>> semanticRegions;
  final List<Map<String, dynamic>> clefSafetyRegions;
  final List<Map<String, dynamic>> inferredSymbols;
  final Map<String, int> rejectionReasonCounts;

  const _DetectionFilterResult({
    required this.symbolGraph,
    required this.translationDetections,
    required this.rejectedNoteheads,
    required this.semanticRegions,
    required this.clefSafetyRegions,
    required this.inferredSymbols,
    required this.rejectionReasonCounts,
  });
}

class SymbolNode {
  final Map<String, dynamic> rawDetection;
  final SymbolState state;
  final double structuralScore;
  final bool isInferred;
  final List<String> rejectionReasons;
  final List<String> supportSources;
  final Map<String, dynamic> validation;

  const SymbolNode({
    required this.rawDetection,
    required this.state,
    required this.structuralScore,
    required this.isInferred,
    required this.rejectionReasons,
    required this.supportSources,
    required this.validation,
  });

  bool get isRejected => state == SymbolState.rejected;

  Map<String, dynamic> toMap() {
    return {
      ...rawDetection,
      'symbolState': state.name,
      'structuralScore': structuralScore,
      'isInferred': isInferred,
      'isRejected': isRejected,
      'rejectionReasons': rejectionReasons,
      'supportSources': supportSources,
      'validation': validation,
    };
  }
}

class _NoteheadValidation {
  final bool valid;
  final bool baseValid;
  final double finalScore;
  final double supportScore;
  final double nonStemSupportScore;
  final StemAttachmentType attachmentType;
  final double? attachmentStemCenterX;
  final double attachmentPenalty;
  final String reason;

  const _NoteheadValidation({
    required this.valid,
    required this.baseValid,
    required this.finalScore,
    required this.supportScore,
    required this.nonStemSupportScore,
    required this.attachmentType,
    required this.attachmentStemCenterX,
    required this.attachmentPenalty,
    required this.reason,
  });

  const _NoteheadValidation.invalid(String failureReason)
    : valid = false,
      baseValid = false,
      finalScore = 0.0,
      supportScore = 0.0,
      nonStemSupportScore = 0.0,
      attachmentType = StemAttachmentType.unknown,
      attachmentStemCenterX = null,
      attachmentPenalty = 0.0,
      reason = failureReason;
}

class _SupportScore {
  final double total;
  final double nonStem;

  const _SupportScore({required this.total, required this.nonStem});
}

class _SymbolAttachmentValidation {
  final bool valid;
  final String reason;

  const _SymbolAttachmentValidation({
    required this.valid,
    required this.reason,
  });
}

class _StructuralSupportContext {
  final bool ledger;
  final bool edgeStem;
  final bool beam;
  final bool chord;
  final bool rhythmicGrouping;
  final bool centerStem;

  const _StructuralSupportContext({
    required this.ledger,
    required this.edgeStem,
    required this.beam,
    required this.chord,
    required this.rhythmicGrouping,
    required this.centerStem,
  });
}

class _ClefOverlapPenalty {
  final double penalty;
  final List<String> reasons;
  final bool coreRejected;
  final bool transitionPenalty;
  final bool validNearClef;

  const _ClefOverlapPenalty({
    required this.penalty,
    required this.reasons,
    required this.coreRejected,
    required this.transitionPenalty,
    required this.validNearClef,
  });
}

class _ProcessingPageState extends State<ProcessingPage> {
  static const MethodChannel _visionPipelineChannel = MethodChannel(
    'stala/python_bridge',
  );

  late List<ProcessingStageItem> _stages;
  int _activeStageIndex = -1;
  bool _isProcessingFinished = false;
  bool _hasProcessingFailed = false;
  bool _isProcessingActive = false;
  String _statusMessage = 'Getting your music sheet ready...';

  final StaffSegmentationService _segmentationService =
      StaffSegmentationService();

  final BarlineRefinementService _barlineRefinementService =
      const BarlineRefinementService();

  final TranslationGroupingService _translationGroupingService =
      TranslationGroupingService();

  final NoteGroupingService _noteGroupingService = NoteGroupingService();

  final GrandStaffPairingService _grandStaffPairingService =
      GrandStaffPairingService();

  final PolyphonicToMonophonicService _polyMonoService =
      PolyphonicToMonophonicService();

  final MusicalInterpretationService _musicalInterpretationService =
      MusicalInterpretationService();

  final FretboardMappingService _fretboardMappingService =
      FretboardMappingService();

  final EventManagerService _eventManagerService = EventManagerService();

  final RhythmInterpretationService _rhythmInterpretationService =
      const RhythmInterpretationService();

  final SaveExportService _saveExportService = const SaveExportService();
  final AppSettingsRepository _appSettingsRepository =
      const AppSettingsRepository();

  Map<String, dynamic>? _processingResult;
  final GlobalKey _processingHelpTourKey = GlobalKey();
  final GlobalKey _processingProgressTourKey = GlobalKey();
  final GlobalKey _processingStepsTourKey = GlobalKey();
  final GlobalKey _processingFooterTourKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _stages = _buildInitialStages();
    _startProcessingPipeline();
    TutorialService.autoStartTour(
      context,
      pageKey: TutorialService.processingPageKey,
      keys: _processingTourKeys,
      page: TutorialPage.processingPage,
    );
  }

  List<GlobalKey> get _processingTourKeys => [
    _processingProgressTourKey,
    _processingStepsTourKey,
    _processingFooterTourKey,
    _processingHelpTourKey,
  ];

  List<ProcessingStageItem> _buildInitialStages() {
    return [
      const ProcessingStageItem(
        title: 'Preparing Image',
        subtitle:
            'Cleaning up the crop so the notes and staff lines are easier to read.',
        icon: Icons.tune_rounded,
        status: ProcessingStageStatus.pending,
      ),
      const ProcessingStageItem(
        title: 'Finding Music Symbols',
        subtitle: 'Looking for notes, accidentals, and clefs on the sheet.',
        icon: Icons.center_focus_strong_rounded,
        status: ProcessingStageStatus.pending,
      ),
      const ProcessingStageItem(
        title: 'Reading Staff Lines',
        subtitle: 'Locating each staff so STALA can understand note positions.',
        icon: Icons.horizontal_rule_rounded,
        status: ProcessingStageStatus.pending,
      ),
      const ProcessingStageItem(
        title: 'Interpreting Notes',
        subtitle:
            'Matching the detected marks to pitches and guitar-friendly choices.',
        icon: Icons.music_note_rounded,
        status: ProcessingStageStatus.pending,
      ),
      const ProcessingStageItem(
        title: 'Building Tablature',
        subtitle: 'Creating the guitar tab and playback-ready result.',
        icon: Icons.library_music_rounded,
        status: ProcessingStageStatus.pending,
      ),
    ];
  }

  Future<void> _startProcessingPipeline() async {
    if (_isProcessingActive) return;
    _isProcessingActive = true;
    try {
      if (!mounted) return;

      setState(() {
        _activeStageIndex = 0;
        _statusMessage = 'Getting your music sheet ready...';
        _stages[0] = _stages[0].copyWith(status: ProcessingStageStatus.active);
      });

      await Future.delayed(const Duration(milliseconds: 400));

      if (!mounted) return;

      setState(() {
        _stages[0] = _stages[0].copyWith(
          status: ProcessingStageStatus.completed,
        );
        _activeStageIndex = 1;
        _statusMessage = 'Finding the notes and symbols on the page...';
        _stages[1] = _stages[1].copyWith(status: ProcessingStageStatus.active);
      });

      setState(() {
        _statusMessage = 'Scanning the music symbols...';
      });

      final dynamic result = await _visionPipelineChannel.invokeMethod(
        'processImage',
        {'imagePath': widget.croppedImagePath},
      );

      setState(() {
        _statusMessage = 'Music symbols found. Reading the staff lines next...';
      });

      if (!mounted) return;

      final response = Map<String, dynamic>.from(result as Map);
      response['croppedImagePath'] ??= widget.croppedImagePath;
      _processingResult = response;

      final status = response['status']?.toString() ?? 'error';
      final message = response['message']?.toString();
      final errors = (response['errors'] as List?)?.cast<dynamic>() ?? const [];

      if (status == 'success') {
        final rawDetections = response['detections'] is List
            ? response['detections'] as List
            : const [];
        final immutableRawDetections = rawDetections
            .whereType<Map>()
            .map((item) {
              return Map<String, dynamic>.unmodifiable(
                Map<String, dynamic>.from(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              );
            })
            .toList(growable: false);
        response['rawDetections'] = immutableRawDetections;
        print('STALA_COUNTS: RAW ONNX COUNT=${immutableRawDetections.length}');
        var classItems = _parseClassItems(rawDetections);

        setState(() {
          _stages[1] = _stages[1].copyWith(
            status: ProcessingStageStatus.completed,
          );
          _activeStageIndex = 2;
          _statusMessage = 'Reading staff lines and note positions...';
          _stages[2] = _stages[2].copyWith(
            status: ProcessingStageStatus.active,
          );
        });

        final segmentationInputPath =
            response['preprocessedImagePath'] ??
            response['detectionImagePath'] ??
            response['croppedImagePath'] ??
            widget.croppedImagePath;

        final segmentationResult = await _segmentationService.segmentStaffLines(
          imagePath: segmentationInputPath,
          symbolDetections: rawDetections,
        );

        if (segmentationResult['status'] == 'success') {
          response['segmentedImagePath'] =
              segmentationResult['segmentedImagePath'];
          response['staffLineCount'] = segmentationResult['staffLineCount'];
          response['staffLines'] = segmentationResult['staffLines'];
          final lockedValidatedStaffs = _freezeValidatedStaffs(
            segmentationResult['validatedStaffs'],
          );
          response['validatedStaffs'] = lockedValidatedStaffs;
          response['ledgerLines'] = segmentationResult['ledgerLines'];
          response['ledgerDiagnostics'] =
              segmentationResult['ledgerDiagnostics'] ?? const {};
          response['barLines'] = segmentationResult['barLines'];
          response['stems'] = segmentationResult['stems'];
          response['beams'] = segmentationResult['beams'];
          response['measures'] = segmentationResult['measures'];

          _logInputCoordinateLock(response);
          _logStaffIntegrityCheck('after_segmentation', lockedValidatedStaffs);
          _warnCoordinateSpaceDrift(
            'after_segmentation',
            lockedValidatedStaffs,
          );
          final staffIntegrity = _staffIntegrityReport(lockedValidatedStaffs);
          print(
            'STAFF_VALIDATION: '
            'staffs=${staffIntegrity['staffs']} '
            'avgSpacing=${(_toDouble(staffIntegrity['avgSpacing']) ?? 0).toStringAsFixed(2)} '
            'fragmented=${staffIntegrity['fragmented']}',
          );
          print(
            'SEGMENT_COUNTS: '
            'stems=${((response['stems'] as List?) ?? const []).length} '
            'beams=${((response['beams'] as List?) ?? const []).length} '
            'ledgers=${((response['ledgerLines'] as List?) ?? const []).length} '
            'barlines=${((response['barLines'] as List?) ?? const []).length} '
            'measures=${((response['measures'] as List?) ?? const []).length}',
          );

          final detectionValidation = _filterStructureAwareDetections(
            rawDetections: rawDetections,
            validatedStaffs: (response['validatedStaffs'] as List?) ?? const [],
            ledgerLines: (response['ledgerLines'] as List?) ?? const [],
            stems: (response['stems'] as List?) ?? const [],
            beams: (response['beams'] as List?) ?? const [],
          );

          final translationDetections =
              detectionValidation.translationDetections;
          response['symbolGraph'] = detectionValidation.symbolGraph;
          response['translationDetections'] = translationDetections;
          response['rejectedNoteheads'] = detectionValidation.rejectedNoteheads;
          response['semanticRegions'] = detectionValidation.semanticRegions;
          response['clefSafetyRegions'] = detectionValidation.clefSafetyRegions;
          response['inferredSymbols'] = detectionValidation.inferredSymbols;
          response['rejectionStats'] =
              detectionValidation.rejectionReasonCounts;
          classItems = _parseClassItems(translationDetections);

          print(
            'STALA_COUNTS: AFTER STRUCTURAL ANNOTATION '
            'graph=${detectionValidation.symbolGraph.length}',
          );
          final semanticPenaltyCount = detectionValidation.symbolGraph.where((
            item,
          ) {
            final reason = item['validationReason']?.toString() ?? '';
            return reason.contains('semantic penalty');
          }).length;
          print(
            'STALA_COUNTS: AFTER SEMANTIC SCORING '
            'semanticRegions=${detectionValidation.semanticRegions.length} '
            'semanticPenalties=$semanticPenaltyCount '
            'rejected=${detectionValidation.rejectedNoteheads.length}',
          );
          print(
            'STALA_COUNTS: REJECTION STATS '
            '${detectionValidation.rejectionReasonCounts}',
          );
          print(
            'STALA_COUNTS: AFTER INFERRED GENERATION '
            'inferred=${detectionValidation.inferredSymbols.length} '
            'graph=${detectionValidation.symbolGraph.length}',
          );
          _logStaffIntegrityCheck(
            'after_semantic_scoring',
            response['validatedStaffs'] as List? ?? const [],
          );
          _logStaffIntegrityCheck(
            'after_inferred_generation',
            response['validatedStaffs'] as List? ?? const [],
          );
          print(
            'SYMBOL_VALIDATION: '
            'detected=${detectionValidation.translationDetections.length} '
            'inferred=${detectionValidation.inferredSymbols.length} '
            'rejected=${detectionValidation.rejectedNoteheads.length}',
          );

          final refinedBarlines = _barlineRefinementService.refine(
            rawBarLines: (response['barLines'] as List?) ?? const [],
            rawMeasures: (response['measures'] as List?) ?? const [],
            rawValidatedStaffs:
                (response['validatedStaffs'] as List?) ?? const [],
            classItems: classItems,
            rawStems: (response['stems'] as List?) ?? const [],
          );

          response['barLines'] = refinedBarlines.barLines;
          response['measures'] = refinedBarlines.measures;
          _logDuplicateMeasureIds(refinedBarlines.measures);
          print(
            'SEGMENT_COUNTS: '
            'stems=${((response['stems'] as List?) ?? const []).length} '
            'beams=${((response['beams'] as List?) ?? const []).length} '
            'ledgers=${((response['ledgerLines'] as List?) ?? const []).length} '
            'barlines=${refinedBarlines.barLines.length} '
            'measures=${refinedBarlines.measures.length}',
          );

          setState(() {
            _stages[2] = _stages[2].copyWith(
              status: ProcessingStageStatus.completed,
            );
            _activeStageIndex = 3;
            _statusMessage = 'Connecting notes to their staff positions...';
            _stages[3] = _stages[3].copyWith(
              status: ProcessingStageStatus.active,
            );
          });

          print(
            'STALA_PIPELINE: interpreting start '
            'TRANSLATION-CONSUMED COUNT=${classItems.length} '
            'staffs=${(response['validatedStaffs'] as List?)?.length ?? 0} '
            'measures=${(response['measures'] as List?)?.length ?? 0}',
          );
          _logStaffIntegrityCheck(
            'before_translation',
            response['validatedStaffs'] as List? ?? const [],
          );

          final translateGroups = _translationGroupingService.buildGroups(
            classItems: classItems,
            staffLines: (response['staffLines'] as List?) ?? const [],
            validatedStaffs: (response['validatedStaffs'] as List?) ?? const [],
            ledgerLines: (response['ledgerLines'] as List?) ?? const [],
            measures: (response['measures'] as List?) ?? const [],
          );

          print(
            'STALA_PIPELINE: translateGroups=${translateGroups.length} '
            'symbols=${translateGroups.fold<int>(0, (sum, group) => sum + group.symbols.length)}',
          );

          final groupedNotes = _noteGroupingService.groupNotes(
            staffGroups: translateGroups,
          );

          final interpretedNoteCount = groupedNotes.values.fold<int>(
            0,
            (sum, groups) =>
                sum +
                groups.fold<int>(0, (inner, group) => inner + group.length),
          );

          if (interpretedNoteCount == 0) {
            throw const SheetInterpretationException(
              'No readable noteheads were matched to the staff lines. Please try a clearer crop with the full staff area visible.',
            );
          }

          print(
            'STALA_PIPELINE: groupedNotes=${groupedNotes.length} '
            'noteEvents=$interpretedNoteCount',
          );

          final noteGroupViewItems = groupedNotes.entries.map((entry) {
            return NoteGroupViewItem(
              staffId: entry.key,
              groups: entry.value
                  .map(
                    (group) => group
                        .map((note) => note.defaultKeyLabel ?? 'Unresolved')
                        .toList(),
                  )
                  .toList(),
            );
          }).toList();

          response['noteGroups'] = noteGroupViewItems;

          final rhythmResult = _rhythmInterpretationService.interpret(
            groupedNotes: groupedNotes,
            rawStems: (response['stems'] as List?) ?? const [],
            rawBeams: (response['beams'] as List?) ?? const [],
          );

          final rhythmViewItems = rhythmResult.events.map((event) {
            return RhythmEventViewItem(
              staffId: event.staffId,
              measureIndex: event.measureIndex,
              label: event.label,
              durationBeats: event.durationBeats,
              timingSource: event.timingSource,
              confidence: event.confidence,
              hasStem: event.hasStem,
              hasBeam: event.hasBeam,
            );
          }).toList();

          response['rhythmEvents'] = rhythmViewItems;

          print('STALA_PIPELINE: rhythmEvents=${rhythmResult.events.length}');
          print(
            'TRANSLATION_COUNTS: '
            'symbols=${translateGroups.fold<int>(0, (sum, group) => sum + group.symbols.length)} '
            'noteEvents=$interpretedNoteCount '
            'rhythmEvents=${rhythmResult.events.length}',
          );

          final grandStaffPairs = _grandStaffPairingService.pairStaffs(
            noteGroups: noteGroupViewItems,
            translateGroups: translateGroups,
          );

          print('STALA_PIPELINE: grandStaffPairs=${grandStaffPairs.length}');

          final grandStaffPairViewItems = grandStaffPairs
              .map((pair) {
                final trebleView = _findNoteGroupViewItem(
                  noteGroupViewItems,
                  pair.trebleStaffId,
                );

                if (trebleView == null) return null;

                final bassView = pair.bassStaffId == null
                    ? null
                    : _findNoteGroupViewItem(
                        noteGroupViewItems,
                        pair.bassStaffId!,
                      );

                return GrandStaffPairViewItem(
                  id: pair.id,
                  trebleStaffId: pair.trebleStaffId,
                  bassStaffId: pair.bassStaffId,
                  trebleGroups: trebleView.groups,
                  bassGroups: bassView?.groups ?? const [],
                );
              })
              .whereType<GrandStaffPairViewItem>()
              .toList();

          response['grandStaffPairs'] = grandStaffPairViewItems;

          final polyMonoResults = _polyMonoService.convert(
            grandStaffPairs: grandStaffPairs,
            groupedNotes: groupedNotes,
          );

          print(
            'STALA_PIPELINE: polyMonoResults=${polyMonoResults.length} '
            'stacks=${polyMonoResults.fold<int>(0, (sum, result) => sum + result.harmonicStacks.length)}',
          );

          final polyMonoViewItems = polyMonoResults.map((result) {
            final chordAwareStrings = result.chordAwareStacks.map((stack) {
              final notes = stack.notes
                  .map((n) => n.defaultKeyLabel ?? 'Unresolved')
                  .join(' + ');

              final chord = stack.chordName;

              if (chord == null) {
                return 'NO_CHORD';
              }

              return '[$notes] → $chord';
            }).toList();

            final allNoChord = chordAwareStrings.every(
              (item) => item == 'NO_CHORD',
            );

            final finalChordAware = allNoChord
                ? ['No chords detected']
                : chordAwareStrings
                      .where((item) => item != 'NO_CHORD')
                      .toList();

            return PolyMonoViewItem(
              grandStaffId: result.grandStaffId,
              harmonicStacks: result.harmonicStacks.map((stack) {
                return stack.notes
                    .map((n) => n.defaultKeyLabel ?? 'Unresolved')
                    .toList();
              }).toList(),
              chordAwareStacks: finalChordAware,
              strictMelody: result.strictMelody.map((n) => n.pitch).toList(),
            );
          }).toList();

          response['polyMonoResults'] = polyMonoViewItems;

          // Music interpretation service
          final musicInterpretation = _musicalInterpretationService.interpret(
            polyMonoResults: polyMonoResults,
          );

          print(
            'STALA_PIPELINE: musicInterpretation '
            'grandStaff=${musicInterpretation.grandStaffLine.events.length} '
            'trebleOnly=${musicInterpretation.trebleOnlyLine.events.length}',
          );

          final musicInterpretationViewItems = [
            MusicInterpretationViewItem(
              title: musicInterpretation.grandStaffLine.title,
              labels: musicInterpretation.grandStaffLine.events
                  .map((event) => event.label)
                  .toList(),
            ),
            MusicInterpretationViewItem(
              title: musicInterpretation.trebleOnlyLine.title,
              labels: musicInterpretation.trebleOnlyLine.events
                  .map((event) => event.label)
                  .toList(),
            ),
          ];

          response['musicInterpretations'] = musicInterpretationViewItems;

          // F-map
          final fretboardMapping = _fretboardMappingService.mapInterpretation(
            interpretation: musicInterpretation,
          );

          print(
            'STALA_PIPELINE: fretboardMapping '
            'events=${fretboardMapping.lines.fold<int>(0, (sum, line) => sum + line.events.length)} '
            'candidates=${fretboardMapping.lines.fold<int>(0, (sum, line) => sum + line.events.fold<int>(0, (inner, event) => inner + event.candidates.length))}',
          );

          final fretboardMappingViewItems = fretboardMapping.lines.map((line) {
            return FretboardMappingViewItem(
              title: line.title,
              eventSummaries: line.events.map((event) {
                final preview = event.candidates
                    .take(3)
                    .map((candidate) {
                      return candidate.positions
                          .map((pos) {
                            return 'S${pos.stringNumber} F${pos.fret}';
                          })
                          .join(' + ');
                    })
                    .join(', ');

                final suffix = event.candidates.length > 3 ? '...' : '';

                return '${event.label} → ${event.candidates.length} candidates: $preview$suffix';
              }).toList(),
            );
          }).toList();

          response['fretboardMappings'] = fretboardMappingViewItems;

          // Event manager
          final eventManagerResult = _eventManagerService.manage(
            fretboardMapping: fretboardMapping,
          );

          print(
            'STALA_PIPELINE: eventManager '
            'lines=${eventManagerResult.lines.length}',
          );

          final eventManagerViewItems = eventManagerResult.lines.map((line) {
            return EventManagerViewItem(
              title: line.title,
              totalCost: line.totalCost.toStringAsFixed(2),
              events: line.events.map((event) {
                final positions = event.chosenPositions
                    .map((pos) {
                      return '${pos.pitch}: S${pos.stringNumber} F${pos.fret}';
                    })
                    .join(' + ');

                return '${event.label} → $positions';
              }).toList(),
            );
          }).toList();

          response['eventManagerResults'] = eventManagerViewItems;

          final chordVoicingViewItems = const <ChordVoicingViewItem>[];
          response['chordVoicingResults'] = chordVoicingViewItems;

          if (!mounted) return;

          setState(() {
            _stages[3] = _stages[3].copyWith(
              status: ProcessingStageStatus.completed,
            );
            _activeStageIndex = 4;
            _statusMessage = 'Building your tablature result...';
            _stages[4] = _stages[4].copyWith(
              status: ProcessingStageStatus.active,
            );
          });

          final tablatureResults = const TablatureResultAdapter().combine(
            eventManagerResult: eventManagerResult,
            rhythmResult: rhythmResult,
            titleFallback: 'Sample 1',
          );

          debugPrint('TABLATURE RESULTS: ${tablatureResults.length} mode(s)');

          response['tablatureResults'] = tablatureResults
              .map((result) => result.toJson())
              .toList();

          for (final result in tablatureResults) {
            debugPrint('${result.mode.name}: ${result.events.length} events');

            if (result.events.isNotEmpty) {
              final first = result.events.first;
              debugPrint(
                'First event: index=${first.eventIndex}, '
                'duration=${first.durationSeconds}, '
                'label=${first.label}, '
                'positions=${first.positions.length}',
              );
            }
          }

          // Session save
          final session = SessionData(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            projectName: 'Sample 1',

            originalImagePath: widget.sourceImagePath,
            croppedImagePath:
                response['croppedImagePath']?.toString() ??
                widget.croppedImagePath,
            preprocessedImagePath: response['preprocessedImagePath']
                ?.toString(),
            detectionImagePath: response['detectionImagePath']?.toString(),
            segmentationImagePath: response['segmentedImagePath']?.toString(),

            detectedSymbols:
                (response['symbolGraph'] as List? ??
                        response['rawDetections'] as List? ??
                        const [])
                    .whereType<Map>()
                    .map((item) => Map<String, dynamic>.from(item))
                    .toList(),

            segmentationData: _buildDebugSegmentationSnapshot(response),

            pitchMappingData:
                (response['rejectedNoteheads'] as List? ?? const [])
                    .whereType<Map>()
                    .map((item) => Map<String, dynamic>.from(item))
                    .toList(),
            fretboardEvents: const [],

            tablatureResults: tablatureResults,

            processingTimestamp: DateTime.now(),
            modelVersion: 'v1',
            hasPipelineSnapshot: true,
          );

          // Generate display data
          final generatedTabs = const GenerationService().generateAll(
            results: tablatureResults,
          );
          response['pipelineReport'] = _buildPipelineReport(
            response: response,
            translateGroups: translateGroups,
            rhythmEvents: rhythmViewItems,
            generatedTabs: generatedTabs,
          );

          debugPrint('GENERATED TABS: ${generatedTabs.length} mode(s)');

          for (final tab in generatedTabs) {
            debugPrint(
              '${tab.mode.name}: '
              '${tab.columns.length} columns, '
              '${tab.fretboardFrames.length} fretboard frames, '
              '${tab.exportPages.length} export pages',
            );
          }

          final generatedTabViewItems = generatedTabs.map((tab) {
            final first = tab.columns.isNotEmpty ? tab.columns.first : null;

            return GeneratedTabViewItem(
              mode: tab.mode.name,
              columns: tab.columns.length,
              fretboardFrames: tab.fretboardFrames.length,
              exportPages: tab.exportPages.length,
              firstEventSummary: first == null
                  ? 'No events'
                  : '${first.label} → ${first.numbers.length} note(s)',
            );
          }).toList();

          final frozenDebugSnapshot = _buildFrozenDebugSnapshot(
            translateGroups: translateGroups,
            noteGroups: noteGroupViewItems,
            rhythmEvents: rhythmViewItems,
            grandStaffPairs: grandStaffPairViewItems,
            polyMonoResults: polyMonoViewItems,
            musicInterpretations: musicInterpretationViewItems,
            fretboardMappings: fretboardMappingViewItems,
            eventManagerResults: eventManagerViewItems,
            chordVoicingResults: chordVoicingViewItems,
            generatedTabs: generatedTabViewItems,
            pipelineReport: Map<String, dynamic>.from(
              response['pipelineReport'] as Map? ?? const {},
            ),
          );

          /// Apply an auto-save to the session data
          SessionData finalSession = session.copyWith(
            debugSnapshot: frozenDebugSnapshot,
          );

          try {
            final autoSaveEnabled = await _appSettingsRepository
                .getAutoSaveEnabled();

            if (autoSaveEnabled) {
              final savedFile = await _saveExportService.saveStalaFile(
                session: finalSession,
              );

              finalSession = finalSession.copyWith(
                autoSavedFilePath: savedFile.path,
                autoSavedAt: DateTime.now(),
                autoSaveFailed: false,
              );
            }
          } catch (error) {
            finalSession = finalSession.copyWith(autoSaveFailed: true);

            debugPrint('AUTO_SAVE_FAILED: $error');
          }

          response['sessionData'] = finalSession;
          response['generatedTabResults'] = generatedTabs;
          response['generatedTabViewItems'] = generatedTabViewItems;

          response['translateGroups'] = translateGroups;
          _processingResult = response;

          setState(() {
            _stages[4] = _stages[4].copyWith(
              status: ProcessingStageStatus.completed,
            );

            _isProcessingFinished = true;
            _statusMessage = 'Your guitar tablature is ready to review.';
          });
        } else {
          final segmentationMessage =
              segmentationResult['message']?.toString() ??
              'The staff lines could not be read clearly.';
          throw Exception(segmentationMessage);
        }
      } else {
        setState(() {
          _stages[1] = _stages[1].copyWith(
            status: ProcessingStageStatus.failed,
          );
          _hasProcessingFailed = true;
          _statusMessage = errors.isNotEmpty
              ? 'The sheet could not be read clearly. Please try a sharper crop.'
              : (message ??
                    'The sheet could not be processed. Please try again.');
        });
      }
    } on PlatformException catch (error, stackTrace) {
      print('STALA_PIPELINE: platform error $error');
      print(stackTrace);

      if (!mounted) return;

      setState(() {
        if (_activeStageIndex >= 0 && _activeStageIndex < _stages.length) {
          _stages[_activeStageIndex] = _stages[_activeStageIndex].copyWith(
            status: ProcessingStageStatus.failed,
          );
        }
        _hasProcessingFailed = true;
        _statusMessage =
            'STALA could not start the reading step. Please try again.';
      });
    } on SheetInterpretationException catch (error, stackTrace) {
      print('STALA_PIPELINE: interpretation data error ${error.message}');
      print(stackTrace);

      if (!mounted) return;

      setState(() {
        if (_activeStageIndex >= 0 && _activeStageIndex < _stages.length) {
          _stages[_activeStageIndex] = _stages[_activeStageIndex].copyWith(
            status: ProcessingStageStatus.failed,
          );
        }
        _hasProcessingFailed = true;
        _statusMessage = error.message;
      });
    } catch (error, stackTrace) {
      print('STALA_PIPELINE: interpretation error $error');
      print(stackTrace);

      if (!mounted) return;

      setState(() {
        if (_activeStageIndex >= 0 && _activeStageIndex < _stages.length) {
          _stages[_activeStageIndex] = _stages[_activeStageIndex].copyWith(
            status: ProcessingStageStatus.failed,
          );
        }
        _hasProcessingFailed = true;
        _statusMessage = 'Something went wrong while reading the sheet.';
      });
    } finally {
      _isProcessingActive = false;
    }
  }

  NoteGroupViewItem? _findNoteGroupViewItem(
    List<NoteGroupViewItem> items,
    String staffId,
  ) {
    for (final item in items) {
      if (item.staffId == staffId) return item;
    }
    return null;
  }

  /// Resets the page state and runs the mock pipeline again.
  Future<void> _retryProcessing() async {
    if (_isProcessingActive) return;
    setState(() {
      _activeStageIndex = -1;
      _isProcessingFinished = false;
      _hasProcessingFailed = false;
      _statusMessage = 'Getting your music sheet ready...';
      _stages = _buildInitialStages();
      _processingResult = null;
    });

    await _startProcessingPipeline();
  }

  /// Number of completed stages already finished in the current run.
  int get _completedStageCount {
    return _stages
        .where((stage) => stage.status == ProcessingStageStatus.completed)
        .length;
  }

  /// Progress value for the summary progress bar.
  double get _progressValue {
    if (_stages.isEmpty) return 0;
    return _completedStageCount / _stages.length;
  }

  /// This helps verify that the response from native side is really being received.
  Future<void> _showNextStepMessage() async {
    if (_processingResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.backgroundSecondary,
          content: Text(
            'No processing result available yet.',
            style: AppTextStyles.body,
          ),
        ),
      );
      return;
    }

    final result = _processingResult!;

    final croppedImagePath = _pickFirstNonEmptyString(result, const [
      'croppedImagePath',
    ]);

    final detectedImagePath = _pickFirstNonEmptyString(result, const [
      'detectedImagePath',
      'annotatedImagePath',
      'visualizedImagePath',
      'detectionImagePath',
      'preprocessedImagePath',
    ]);

    final segmentedImagePath = _pickFirstNonEmptyString(result, const [
      'segmentedImagePath',
    ]);

    final detections = _parseDetectionPoints(result['detections']);
    final classItems = _parseClassItems(
      result['translationDetections'] ??
          result['symbolGraph'] ??
          result['detections'],
    );
    final translateGroups =
        (result['translateGroups'] as List<StaffTranslateGroup>?) ?? const [];

    final noteGroups =
        (result['noteGroups'] as List<NoteGroupViewItem>?) ?? const [];

    final rhythmEvents =
        (result['rhythmEvents'] as List<RhythmEventViewItem>?) ?? const [];

    final grandStaffPairs =
        (result['grandStaffPairs'] as List<GrandStaffPairViewItem>?) ??
        const [];

    final polyMonoResults =
        (result['polyMonoResults'] as List<PolyMonoViewItem>?) ?? const [];

    final musicInterpretations =
        (result['musicInterpretations']
            as List<MusicInterpretationViewItem>?) ??
        const [];

    final fretboardMappings =
        (result['fretboardMappings'] as List<FretboardMappingViewItem>?) ??
        const [];

    final eventManagerResults =
        (result['eventManagerResults'] as List<EventManagerViewItem>?) ??
        const [];

    final chordVoicingResults =
        (result['chordVoicingResults'] as List<ChordVoicingViewItem>?) ??
        const [];

    final session = result['sessionData'] as SessionData;
    final generatedTabResults =
        (result['generatedTabResults'] as List<GeneratedTabResult>?) ??
        const [];

    final generatedTabs =
        (result['generatedTabViewItems'] as List<GeneratedTabViewItem>?) ??
        const [];

    final ledgerLines = _parseConfirmedLedgerLines(
      result['ledgerLines'],
      translateGroups,
    );

    final isDebugEnabled = await const DebugSettingsRepository()
        .isDebugPageEnabled();

    if (!mounted) return;

    if (isDebugEnabled) {
      final debugResult = await Navigator.push<Object?>(
        context,
        MaterialPageRoute(
          builder: (_) => DummyPage(
            croppedImagePath: croppedImagePath ?? widget.croppedImagePath,
            detectedImagePath:
                detectedImagePath ??
                croppedImagePath ??
                widget.croppedImagePath,
            segmentedImagePath: segmentedImagePath,
            detections: detections,
            classItems: classItems,
            staffOverlays: _normalizeMapList(result['validatedStaffs']),
            barLineOverlays: _normalizeMapList(result['barLines']),
            stemOverlays: _normalizeMapList(result['stems']),
            beamOverlays: _normalizeMapList(result['beams']),
            semanticRegions: _normalizeMapList(result['semanticRegions']),
            clefSafetyRegions: _normalizeMapList(result['clefSafetyRegions']),
            rejectedNoteheads: _normalizeMapList(result['rejectedNoteheads']),
            translateGroups: translateGroups,
            noteGroups: noteGroups,
            rhythmEvents: rhythmEvents,
            grandStaffPairs: grandStaffPairs,
            polyMonoResults: polyMonoResults,
            musicInterpretations: musicInterpretations,
            fretboardMappings: fretboardMappings,
            eventManagerResults: eventManagerResults,
            chordVoicingResults: chordVoicingResults,
            session: session,
            generatedTabResults: generatedTabResults,
            generatedTabs: generatedTabs,
            ledgerLines: ledgerLines,
            generateOutputs: const [],
            pipelineReport: Map<String, dynamic>.from(
              result['pipelineReport'] as Map? ?? const {},
            ),
            onRetry: () => Navigator.pop(context, 'retry'),
          ),
        ),
      );

      if (!mounted) return;

      if (debugResult == 'retry') {
        await _retryProcessing();
        if (!mounted || !_isProcessingFinished || _hasProcessingFailed) return;
        await _showNextStepMessage();
      } else if (debugResult == 'openResult') {
        final shouldRefreshHome = await Navigator.pushReplacement<bool, bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ResultPage(
              session: session,
              generatedTabs: generatedTabResults,
            ),
          ),
        );

        if (!mounted) return;

        if (shouldRefreshHome == true) {
          Navigator.pop(context, true);
        }
      } else if (debugResult == true) {
        Navigator.pop(context, true);
      }
    } else {
      final shouldRefreshHome = await Navigator.pushReplacement<bool, bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ResultPage(session: session, generatedTabs: generatedTabResults),
        ),
      );

      if (!mounted) return;

      if (shouldRefreshHome == true) {
        Navigator.pop(context, true);
      }
    }
  }

  String? _pickFirstNonEmptyString(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  List<DetectionPoint> _parseDetectionPoints(dynamic rawDetections) {
    if (rawDetections is! List) return const [];

    final List<DetectionPoint> points = [];

    for (final item in rawDetections) {
      if (item is! Map) continue;

      final map = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );

      final className =
          map['className']?.toString() ??
          map['labelName']?.toString() ??
          map['label']?.toString() ??
          'symbol';

      final score = _toDouble(map['score'] ?? map['confidence']);

      double? centerX;
      double? centerY;

      if (map['centerX'] != null && map['centerY'] != null) {
        centerX = _toDouble(map['centerX']);
        centerY = _toDouble(map['centerY']);
      } else if (map['bbox'] is List && (map['bbox'] as List).length >= 4) {
        final bbox = List.from(map['bbox']);
        final x1 = _toDouble(bbox[0]);
        final y1 = _toDouble(bbox[1]);
        final x2 = _toDouble(bbox[2]);
        final y2 = _toDouble(bbox[3]);

        if (x1 != null && y1 != null && x2 != null && y2 != null) {
          centerX = (x1 + x2) / 2.0;
          centerY = (y1 + y2) / 2.0;
        }
      } else {
        final left = _toDouble(map['left'] ?? map['x1'] ?? map['xmin']);
        final top = _toDouble(map['top'] ?? map['y1'] ?? map['ymin']);
        final right = _toDouble(map['right'] ?? map['x2'] ?? map['xmax']);
        final bottom = _toDouble(map['bottom'] ?? map['y2'] ?? map['ymax']);

        if (left != null && top != null && right != null && bottom != null) {
          centerX = (left + right) / 2.0;
          centerY = (top + bottom) / 2.0;
        }
      }

      if (centerX == null || centerY == null) continue;

      points.add(
        DetectionPoint(
          className: className,
          centerX: centerX,
          centerY: centerY,
          score: score,
        ),
      );
    }

    return points;
  }

  List<Map<String, dynamic>> _normalizeMapList(dynamic rawItems) {
    if (rawItems is! List) return const [];

    return rawItems.whereType<Map>().map((item) {
      return Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
    }).toList();
  }

  List<Map<String, dynamic>> _freezeValidatedStaffs(dynamic rawStaffs) {
    if (rawStaffs is! List) return const [];

    return rawStaffs
        .whereType<Map>()
        .map((item) {
          final staff = Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );

          final rawLines = staff['lines'];

          final List<double> lines;

          if (rawLines is List) {
            lines = rawLines
                .map((e) => _toDouble(e))
                .whereType<double>()
                .toList();

            lines.sort();
          } else {
            lines = <double>[];
          }

          final spacing =
              _toDouble(staff['validatedStaffSpacing']) ??
              _toDouble(staff['spacing']) ??
              _averageSpacing(lines);

          return Map<String, dynamic>.unmodifiable({
            ...staff,
            'lines': List<double>.unmodifiable(lines),
            'spacing': spacing,
            'validatedStaffSpacing': spacing,
            'locked': true,
            'coordinateSpace': 'original_image',
          });
        })
        .toList(growable: false);
  }

  Map<String, dynamic> _staffIntegrityReport(List<dynamic> validatedStaffs) {
    final staffs = _normalizeMapList(validatedStaffs);
    final spacings = staffs
        .map(
          (staff) =>
              _toDouble(staff['validatedStaffSpacing'] ?? staff['spacing']),
        )
        .whereType<double>()
        .where((spacing) => spacing > 0)
        .toList();
    final avgSpacing = spacings.isEmpty
        ? 0.0
        : spacings.reduce((a, b) => a + b) / spacings.length;
    final fragmented = staffs.where((staff) {
      final lines = staff['lines'];
      return lines is! List || lines.length != 5;
    }).length;

    return {
      'status': fragmented == 0 && staffs.isNotEmpty ? 'PASSED' : 'WARNING',
      'staffs': staffs.length,
      'avgSpacing': avgSpacing,
      'fragmented': fragmented,
    };
  }

  void _logStaffIntegrityCheck(String stage, List<dynamic> validatedStaffs) {
    final report = _staffIntegrityReport(validatedStaffs);
    print(
      'STAFF_INTEGRITY_CHECK: '
      'stage=$stage '
      'status=${report['status']} '
      'staffs=${report['staffs']} '
      'avgSpacing=${(_toDouble(report['avgSpacing']) ?? 0).toStringAsFixed(2)} '
      'fragmented=${report['fragmented']}',
    );
  }

  void _logInputCoordinateLock(Map<String, dynamic> response) {
    final originalWidth =
        response['originalImageWidth'] ??
        response['sourceImageWidth'] ??
        response['imageWidth'];
    final originalHeight =
        response['originalImageHeight'] ??
        response['sourceImageHeight'] ??
        response['imageHeight'];
    final letterboxWidth = response['imageWidth'];
    final letterboxHeight = response['imageHeight'];
    print(
      'INPUT_COORDINATE_LOCK: '
      'originalWidth=${originalWidth ?? '-'} '
      'originalHeight=${originalHeight ?? '-'} '
      'letterboxWidth=${letterboxWidth ?? '-'} '
      'letterboxHeight=${letterboxHeight ?? '-'} '
      'coordinateSpace=original_image',
    );
  }

  void _logDuplicateMeasureIds(List<dynamic> measures) {
    final ids = <String>{};
    final duplicates = <String>{};
    for (final item in measures.whereType<Map>()) {
      final id = item['id']?.toString();
      if (id == null || id.isEmpty) continue;
      if (!ids.add(id)) duplicates.add(id);
    }
    if (duplicates.isNotEmpty) {
      print('MEASURE_ID_WARNING: duplicates=${duplicates.join(',')}');
    }
  }

  void _warnCoordinateSpaceDrift(String stage, Iterable<dynamic> items) {
    for (final item in items.whereType<Map>()) {
      final space = item['coordinateSpace']?.toString();
      if (space != null && space != 'original_image') {
        print(
          'COORDINATE_SPACE_WARNING: '
          'stage=$stage id=${item['id'] ?? '-'} coordinateSpace=$space',
        );
      }
    }
  }

  Map<String, dynamic> _buildPipelineReport({
    required Map<String, dynamic> response,
    required List<StaffTranslateGroup> translateGroups,
    required List<RhythmEventViewItem> rhythmEvents,
    required List<GeneratedTabResult> generatedTabs,
  }) {
    final staffs = _normalizeMapList(response['validatedStaffs']);
    final symbolGraph = _normalizeMapList(response['symbolGraph']);
    final inferredSymbols = _normalizeMapList(response['inferredSymbols']);
    final rejectedNoteheads = _normalizeMapList(response['rejectedNoteheads']);
    final ledgerDiagnostics = Map<String, dynamic>.from(
      response['ledgerDiagnostics'] as Map? ?? const {},
    );
    final staffReport = staffs.map((staff) {
      final lines = (staff['lines'] as List?) ?? const [];
      return {
        'id': staff['id']?.toString() ?? '',
        'spacing':
            _toDouble(staff['validatedStaffSpacing'] ?? staff['spacing']) ??
            0.0,
        'lineCount': lines.length,
        'continuityScore':
            _toDouble(
              staff['continuityScore'] ??
                  staff['continuity'] ??
                  staff['confidence'],
            ) ??
            0.0,
        'region':
            '${_toDouble(staff['topBoundary'])?.toStringAsFixed(1) ?? '-'}-${_toDouble(staff['bottomBoundary'])?.toStringAsFixed(1) ?? '-'}',
        'grandStaffPairId': staff['grandStaffPairId']?.toString() ?? '-',
      };
    }).toList();

    final attachmentTypes = <String, int>{};
    var semanticPenalties = 0;
    var centerAttachmentPenalties = 0;
    for (final symbol in symbolGraph) {
      final attachment = symbol['stemAttachmentType']?.toString();
      if (attachment != null && attachment.isNotEmpty) {
        attachmentTypes[attachment] = (attachmentTypes[attachment] ?? 0) + 1;
      }
      final validationReason = symbol['validation'] is Map
          ? (symbol['validation'] as Map)['reason']?.toString()
          : null;
      final reason =
          symbol['validationReason']?.toString() ?? validationReason ?? '';
      if (reason.contains('semantic penalty')) semanticPenalties++;
      if (reason.contains('center_stem_attachment'))
        centerAttachmentPenalties++;
    }

    return {
      'staff': staffReport,
      'symbols': {
        'detectedSymbols': symbolGraph.length,
        'inferredSymbols': inferredSymbols.length,
        'rejectedSymbols': rejectedNoteheads.length,
        'rejectionReasons': response['rejectionStats'] ?? const {},
        'attachmentTypes': attachmentTypes,
      },
      'segments': {
        'stems': ((response['stems'] as List?) ?? const []).length,
        'beams': ((response['beams'] as List?) ?? const []).length,
        'ledgerLines': ((response['ledgerLines'] as List?) ?? const []).length,
        'barlines': ((response['barLines'] as List?) ?? const []).length,
        'measures': ((response['measures'] as List?) ?? const []).length,
        'semanticRegions':
            ((response['semanticRegions'] as List?) ?? const []).length,
        'clefSafetyRegions':
            ((response['clefSafetyRegions'] as List?) ?? const []).length,
      },
      'ledger': ledgerDiagnostics.isEmpty
          ? {
              'rawCandidates':
                  ((response['ledgerLines'] as List?) ?? const []).length,
              'validatedLedgers':
                  ((response['ledgerLines'] as List?) ?? const []).length,
              'rejectedFragments': 0,
              'rejectionReasons': const {},
            }
          : ledgerDiagnostics,
      'validation': {
        'semanticPenalties': semanticPenalties,
        'centerAttachmentPenalties': centerAttachmentPenalties,
        'inferredRecoveryCount': inferredSymbols.length,
        'accidentalAssociations': symbolGraph.where((symbol) {
          final sources = symbol['supportSources'];
          return sources is List && sources.contains('attached_notehead');
        }).length,
      },
      'translation': {
        'translationConsumedSymbols': translateGroups.fold<int>(
          0,
          (sum, group) => sum + group.symbols.length,
        ),
        'groupedNotes': ((response['noteGroups'] as List?) ?? const [])
            .whereType<NoteGroupViewItem>()
            .fold<int>(
              0,
              (sum, item) =>
                  sum +
                  item.groups.fold<int>(
                    0,
                    (inner, group) => inner + group.length,
                  ),
            ),
        'rhythmEvents': rhythmEvents.length,
        'generatedTablatureEvents': generatedTabs.fold<int>(
          0,
          (sum, tab) => sum + tab.columns.length,
        ),
      },
      'coordinates': {
        'coordinateSpace': 'original_image',
        'imageWidth': response['imageWidth'],
        'imageHeight': response['imageHeight'],
        'lockedStaffs': staffs.where((staff) => staff['locked'] == true).length,
      },
    };
  }

  Map<String, dynamic> _buildFrozenDebugSnapshot({
    required List<StaffTranslateGroup> translateGroups,
    required List<NoteGroupViewItem> noteGroups,
    required List<RhythmEventViewItem> rhythmEvents,
    required List<GrandStaffPairViewItem> grandStaffPairs,
    required List<PolyMonoViewItem> polyMonoResults,
    required List<MusicInterpretationViewItem> musicInterpretations,
    required List<FretboardMappingViewItem> fretboardMappings,
    required List<EventManagerViewItem> eventManagerResults,
    required List<ChordVoicingViewItem> chordVoicingResults,
    required List<GeneratedTabViewItem> generatedTabs,
    required Map<String, dynamic> pipelineReport,
  }) {
    return {
      'translateGroups': translateGroups
          .map(_staffTranslateGroupToJson)
          .toList(),
      'noteGroups': noteGroups.map((item) {
        return {'staffId': item.staffId, 'groups': item.groups};
      }).toList(),
      'rhythmEvents': rhythmEvents.map((item) {
        return {
          'staffId': item.staffId,
          'measureIndex': item.measureIndex,
          'label': item.label,
          'durationBeats': item.durationBeats,
          'timingSource': item.timingSource,
          'confidence': item.confidence,
          'hasStem': item.hasStem,
          'hasBeam': item.hasBeam,
        };
      }).toList(),
      'grandStaffPairs': grandStaffPairs.map((item) {
        return {
          'id': item.id,
          'trebleStaffId': item.trebleStaffId,
          'bassStaffId': item.bassStaffId,
          'trebleGroups': item.trebleGroups,
          'bassGroups': item.bassGroups,
        };
      }).toList(),
      'polyMonoResults': polyMonoResults.map((item) {
        return {
          'grandStaffId': item.grandStaffId,
          'harmonicStacks': item.harmonicStacks,
          'chordAwareStacks': item.chordAwareStacks,
          'strictMelody': item.strictMelody,
        };
      }).toList(),
      'musicInterpretations': musicInterpretations.map((item) {
        return {'title': item.title, 'labels': item.labels};
      }).toList(),
      'fretboardMappings': fretboardMappings.map((item) {
        return {'title': item.title, 'eventSummaries': item.eventSummaries};
      }).toList(),
      'eventManagerResults': eventManagerResults.map((item) {
        return {
          'title': item.title,
          'totalCost': item.totalCost,
          'events': item.events,
        };
      }).toList(),
      'chordVoicingResults': chordVoicingResults.map((item) {
        return {'title': item.title, 'events': item.events};
      }).toList(),
      'generatedTabs': generatedTabs.map((item) {
        return {
          'mode': item.mode,
          'columns': item.columns,
          'fretboardFrames': item.fretboardFrames,
          'exportPages': item.exportPages,
          'firstEventSummary': item.firstEventSummary,
        };
      }).toList(),
      'pipelineReport': pipelineReport,
    };
  }

  Map<String, dynamic> _staffTranslateGroupToJson(StaffTranslateGroup group) {
    return {
      'staffId': group.staffId,
      'summary': {
        'lineCount': group.summary.lineCount,
        'symbolCount': group.summary.symbolCount,
        'clefStatusLabel': group.summary.clefStatusLabel,
      },
      'segmentMap': group.segmentMap.map((item) {
        return {
          'id': item.id,
          'type': item.type,
          'centerY': item.centerY,
          'startY': item.startY,
          'endY': item.endY,
          'defaultKeyLabel': item.defaultKeyLabel,
        };
      }).toList(),
      'symbols': group.symbols.map((symbol) {
        return {
          'className': symbol.className,
          'centerX': symbol.centerX,
          'centerY': symbol.centerY,
          'score': symbol.score,
          'bbox': symbol.bbox,
          'staffId': symbol.staffId,
          'staffRole': symbol.staffRole,
          'locationId': symbol.locationId,
          'locationType': symbol.locationType,
          'assignmentStatus': symbol.assignmentStatus,
          'measureId': symbol.measureId,
          'measureIndex': symbol.measureIndex,
          'defaultKeyLabel': symbol.defaultKeyLabel,
          'accidentalState': symbol.accidentalState,
          'symbolState': symbol.symbolState.name,
          'inferredReason': symbol.inferredReason,
        };
      }).toList(),
    };
  }

  List<Map<String, dynamic>> _buildDebugSegmentationSnapshot(
    Map<String, dynamic> response,
  ) {
    final snapshot = <Map<String, dynamic>>[];

    void addList(String kind, dynamic rawItems) {
      if (rawItems is! List) return;
      for (final item in rawItems.whereType<Map>()) {
        snapshot.add({
          'kind': kind,
          ...Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        });
      }
    }

    addList('staffLine', response['staffLines']);
    addList('validatedStaff', response['validatedStaffs']);
    addList('ledgerLine', response['ledgerLines']);
    addList('barLine', response['barLines']);
    addList('stem', response['stems']);
    addList('beam', response['beams']);
    addList('measure', response['measures']);
    addList('semanticRegion', response['semanticRegions']);
    addList('clefSafetyRegion', response['clefSafetyRegions']);
    addList('inferredSymbol', response['inferredSymbols']);
    addList('symbolGraphNode', response['symbolGraph']);
    return snapshot;
  }

  _DetectionFilterResult _filterStructureAwareDetections({
    required List<dynamic> rawDetections,
    required List<dynamic> validatedStaffs,
    required List<dynamic> ledgerLines,
    required List<dynamic> stems,
    required List<dynamic> beams,
  }) {
    final symbols = rawDetections
        .whereType<Map>()
        .map((item) {
          return Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
        })
        .where((item) => _symbolGeometry(item) != null)
        .toList();

    print('STALA_COUNTS: AFTER STAFF ASSOCIATION symbols=${symbols.length}');

    final clefs = symbols.where((item) {
      final className = _symbolClassName(item);
      return className == 'treble_clef' || className == 'bass_clef';
    }).toList();

    final semanticRegions = _buildPostClefSemanticRegions(
      clefs: clefs,
      validatedStaffs: validatedStaffs,
    );
    final clefSafetyRegions = _buildClefSafetyRegions(
      clefs: clefs,
      validatedStaffs: validatedStaffs,
    );

    final noteheadCandidates = symbols.where((item) {
      return _symbolClassName(item) == 'notehead';
    }).toList();

    final timeSignatureLike = _likelyTimeSignatureNoteheads(
      noteheadCandidates: noteheadCandidates,
      semanticRegions: semanticRegions,
      stems: stems,
      beams: beams,
    );

    final symbolGraph = <Map<String, dynamic>>[];
    final translationDetections = <Map<String, dynamic>>[];
    final rejectedNoteheads = <Map<String, dynamic>>[];
    final rejectionReasonCounts = <String, int>{};
    final stemAttachmentCounts = {
      StemAttachmentType.leftEdge: 0,
      StemAttachmentType.rightEdge: 0,
      StemAttachmentType.center: 0,
      StemAttachmentType.unknown: 0,
    };
    var centerAttachmentPenaltyCount = 0;

    void countReasons(List<String> reasons) {
      for (final reason in reasons) {
        rejectionReasonCounts[reason] =
            (rejectionReasonCounts[reason] ?? 0) + 1;
      }
    }

    for (final item in symbols.where((item) {
      final className = _symbolClassName(item);
      return className == 'treble_clef' ||
          className == 'bass_clef' ||
          className == 'notehead';
    })) {
      final geometry = _symbolGeometry(item);
      if (geometry == null) continue;

      final className = _symbolClassName(item);
      if (className == 'treble_clef' || className == 'bass_clef') {
        final node = SymbolNode(
          rawDetection: item,
          state: SymbolState.detected,
          structuralScore:
              _toDouble(item['score'] ?? item['confidence']) ?? 1.0,
          isInferred: false,
          rejectionReasons: const [],
          supportSources: const ['onnx'],
          validation: const {'reason': 'clef preserved'},
        ).toMap();
        symbolGraph.add(node);
        translationDetections.add(node);
        continue;
      }

      if (className == 'notehead') {
        final validation = _validateNoteheadCandidate(
          item: item,
          allSymbols: symbols,
          validatedStaffs: validatedStaffs,
          ledgerLines: ledgerLines,
          stems: stems,
          beams: beams,
          semanticRegions: semanticRegions,
          clefSafetyRegions: clefSafetyRegions,
          timeSignatureLike: timeSignatureLike,
        );

        final enriched = {
          ...item,
          'baseValid': validation.baseValid,
          'structuralSupportScore': validation.supportScore,
          'nonStemSupportScore': validation.nonStemSupportScore,
          'stemAttachmentType': validation.attachmentType.name,
          'stemAttachmentX': validation.attachmentStemCenterX,
          'stemAttachmentPenalty': validation.attachmentPenalty,
          'finalValidationScore': validation.finalScore,
          'validationReason': validation.reason,
        };

        stemAttachmentCounts[validation.attachmentType] =
            (stemAttachmentCounts[validation.attachmentType] ?? 0) + 1;
        if (validation.attachmentPenalty > 0 &&
            validation.attachmentType == StemAttachmentType.center) {
          centerAttachmentPenaltyCount++;
        }

        if (validation.valid) {
          final node = SymbolNode(
            rawDetection: enriched,
            state: SymbolState.detected,
            structuralScore: validation.finalScore,
            isInferred: false,
            rejectionReasons: const [],
            supportSources: _supportSourcesForScore(enriched),
            validation: {
              'reason': validation.reason,
              'baseValid': validation.baseValid,
              'supportScore': validation.supportScore,
              'nonStemSupportScore': validation.nonStemSupportScore,
              'stemAttachmentType': validation.attachmentType.name,
              'stemAttachmentX': validation.attachmentStemCenterX,
              'stemAttachmentPenalty': validation.attachmentPenalty,
            },
          ).toMap();
          symbolGraph.add(node);
          translationDetections.add(node);
        } else {
          final reasons = _splitValidationReasons(validation.reason);
          final node = SymbolNode(
            rawDetection: enriched,
            state: SymbolState.rejected,
            structuralScore: validation.finalScore,
            isInferred: false,
            rejectionReasons: reasons,
            supportSources: _supportSourcesForScore(enriched),
            validation: {
              'reason': validation.reason,
              'baseValid': validation.baseValid,
              'supportScore': validation.supportScore,
              'nonStemSupportScore': validation.nonStemSupportScore,
              'stemAttachmentType': validation.attachmentType.name,
              'stemAttachmentX': validation.attachmentStemCenterX,
              'stemAttachmentPenalty': validation.attachmentPenalty,
            },
          ).toMap();
          symbolGraph.add(node);
          rejectedNoteheads.add({...node, 'className': 'notehead'});
          countReasons(reasons);
        }
        continue;
      }
    }

    print(
      'STEM_ATTACHMENT: '
      'left=${stemAttachmentCounts[StemAttachmentType.leftEdge] ?? 0} '
      'right=${stemAttachmentCounts[StemAttachmentType.rightEdge] ?? 0} '
      'center=${stemAttachmentCounts[StemAttachmentType.center] ?? 0} '
      'unknown=${stemAttachmentCounts[StemAttachmentType.unknown] ?? 0}',
    );
    print('CENTER_ATTACHMENT_PENALTIES=$centerAttachmentPenaltyCount');

    final inferredSymbols = _generateInferredLedgerNoteheads(
      validSymbols: translationDetections,
      rejectedNoteheads: rejectedNoteheads,
      ledgerLines: ledgerLines,
      stems: stems,
      validatedStaffs: validatedStaffs,
    );
    symbolGraph.addAll(inferredSymbols);
    translationDetections.addAll(inferredSymbols);

    for (final item in symbols.where((item) {
      final className = _symbolClassName(item);
      return className != 'treble_clef' &&
          className != 'bass_clef' &&
          className != 'notehead';
    })) {
      final geometry = _symbolGeometry(item);
      if (geometry == null) continue;

      final className = _symbolClassName(item);
      if (_isAccidentalClass(className)) {
        final validation = _validateAccidental(
          symbol: geometry,
          validSymbols: translationDetections,
          ledgerLines: ledgerLines,
          validatedStaffs: validatedStaffs,
          clefSafetyRegions: clefSafetyRegions,
        );
        if (validation.valid) {
          final node = SymbolNode(
            rawDetection: {...item, 'validationReason': validation.reason},
            state: SymbolState.detected,
            structuralScore:
                (_toDouble(item['score'] ?? item['confidence']) ?? 0.65)
                    .clamp(0.0, 1.0)
                    .toDouble(),
            isInferred: false,
            rejectionReasons: const [],
            supportSources: const ['attached_notehead'],
            validation: {'reason': validation.reason},
          ).toMap();
          symbolGraph.add(node);
          translationDetections.add(node);
        } else {
          final reasons = _splitValidationReasons(validation.reason);
          final node = SymbolNode(
            rawDetection: {...item, 'validationReason': validation.reason},
            state: SymbolState.rejected,
            structuralScore:
                (_toDouble(item['score'] ?? item['confidence']) ?? 0.45)
                    .clamp(0.0, 1.0)
                    .toDouble(),
            isInferred: false,
            rejectionReasons: reasons,
            supportSources: const [],
            validation: {'reason': validation.reason},
          ).toMap();
          symbolGraph.add(node);
          countReasons(reasons);
        }
        continue;
      }

      if (_insideAnyStaffRegion(geometry.centerY, validatedStaffs) ||
          _supportedByLedger(geometry, ledgerLines) ||
          _nearSupportedNotehead(geometry, translationDetections)) {
        final node = SymbolNode(
          rawDetection: item,
          state: SymbolState.detected,
          structuralScore:
              (_toDouble(item['score'] ?? item['confidence']) ?? 0.62)
                  .clamp(0.0, 1.0)
                  .toDouble(),
          isInferred: false,
          rejectionReasons: const [],
          supportSources: const ['staff_or_ledger_context'],
          validation: const {'reason': 'staff/ledger context'},
        ).toMap();
        symbolGraph.add(node);
        translationDetections.add(node);
      } else {
        const reasons = ['outside structural context'];
        final node = SymbolNode(
          rawDetection: item,
          state: SymbolState.rejected,
          structuralScore:
              (_toDouble(item['score'] ?? item['confidence']) ?? 0.40)
                  .clamp(0.0, 1.0)
                  .toDouble(),
          isInferred: false,
          rejectionReasons: reasons,
          supportSources: const [],
          validation: const {'reason': 'outside structural context'},
        ).toMap();
        symbolGraph.add(node);
        countReasons(reasons);
      }
    }

    final clefRegionStats = _clefRegionStats(
      symbolGraph: symbolGraph,
      clefSafetyRegions: clefSafetyRegions,
    );
    final clefCoreRejected = clefRegionStats['coreRejected'] ?? 0;
    final clefTransitionPenalties = clefRegionStats['transitionPenalties'] ?? 0;
    final validNearClef = clefRegionStats['validNearClef'] ?? 0;
    final overlapCoreCount = rejectionReasonCounts['overlap_core'] ?? 0;
    final centerNearClefCount =
        rejectionReasonCounts['center_attachment_near_clef'] ?? 0;
    final unsupportedAccidentalCount =
        rejectionReasonCounts['unsupported_accidental'] ?? 0;
    final numeralStackNearClefCount =
        rejectionReasonCounts['numeral_stack_near_clef'] ?? 0;
    print(
      'CLEF_REGION: '
      'coreRejected=$clefCoreRejected '
      'transitionPenalties=$clefTransitionPenalties '
      'validNearClef=$validNearClef',
    );
    print(
      'CLEF_REGION_REASONS: '
      'overlap_core=$overlapCoreCount '
      'center_attachment_near_clef=$centerNearClefCount '
      'unsupported_accidental=$unsupportedAccidentalCount '
      'numeral_stack_near_clef=$numeralStackNearClefCount',
    );

    return _DetectionFilterResult(
      symbolGraph: symbolGraph,
      translationDetections: translationDetections,
      rejectedNoteheads: rejectedNoteheads,
      semanticRegions: semanticRegions,
      clefSafetyRegions: clefSafetyRegions,
      inferredSymbols: inferredSymbols,
      rejectionReasonCounts: rejectionReasonCounts,
    );
  }

  List<Map<String, dynamic>> _buildClefSafetyRegions({
    required List<Map<String, dynamic>> clefs,
    required List<dynamic> validatedStaffs,
  }) {
    final regions = <Map<String, dynamic>>[];

    for (final clef in clefs) {
      final clefGeometry = _symbolGeometry(clef);
      if (clefGeometry == null) continue;

      final staff = _nearestStaffForSymbol(clefGeometry, validatedStaffs);
      if (staff == null) continue;

      final staffId = staff['id']?.toString() ?? '';
      final spacing =
          _toDouble(staff['validatedStaffSpacing'] ?? staff['spacing']) ?? 12.0;
      final top = _toDouble(staff['topBoundary']);
      final bottom = _toDouble(staff['bottomBoundary']);
      if (staffId.isEmpty || top == null || bottom == null || spacing <= 0) {
        continue;
      }

      final padding = spacing * 0.65;
      final expansionPaddingX = spacing * 0.9;
      final expansionPaddingY = spacing * 0.9;
      final transitionWidth = spacing * 3.2;
      regions.add({
        'id': 'clef_safety_${regions.length}',
        'staffId': staffId,
        'type': 'ClefSafetyRegion',
        'x1': clefGeometry.x1 - expansionPaddingX,
        'x2': clefGeometry.x2 + expansionPaddingX,
        'y1': top - expansionPaddingY,
        'y2': bottom + expansionPaddingY,
        'coreX1': clefGeometry.x1,
        'coreX2': clefGeometry.x2,
        'coreY1': clefGeometry.y1,
        'coreY2': clefGeometry.y2,
        'expansionX1': clefGeometry.x1 - expansionPaddingX,
        'expansionX2': clefGeometry.x2 + expansionPaddingX,
        'expansionY1': top - expansionPaddingY,
        'expansionY2': bottom + expansionPaddingY,
        'transitionX1': clefGeometry.x2,
        'transitionX2': clefGeometry.x2 + transitionWidth,
        'transitionY1': top - padding,
        'transitionY2': bottom + padding,
        'sourceClass': _symbolClassName(clef),
        'penalty': 0.30,
      });
    }

    return regions;
  }

  List<Map<String, dynamic>> _buildPostClefSemanticRegions({
    required List<Map<String, dynamic>> clefs,
    required List<dynamic> validatedStaffs,
  }) {
    final regions = <Map<String, dynamic>>[];

    for (final clef in clefs) {
      final clefGeometry = _symbolGeometry(clef);
      if (clefGeometry == null) continue;

      final staff = _nearestStaffForSymbol(clefGeometry, validatedStaffs);
      if (staff == null) continue;

      final staffId = staff['id']?.toString() ?? '';
      final spacing =
          _toDouble(staff['validatedStaffSpacing'] ?? staff['spacing']) ?? 12.0;
      final top = _toDouble(staff['topBoundary']);
      final bottom = _toDouble(staff['bottomBoundary']);
      if (staffId.isEmpty || top == null || bottom == null) continue;

      final width = spacing * 6.0;
      regions.add({
        'id': 'post_clef_${regions.length}',
        'staffId': staffId,
        'type': 'postClefSemanticRegion',
        'x1': clefGeometry.x2,
        'x2': clefGeometry.x2 + width,
        'y1': top - spacing * 0.5,
        'y2': bottom + spacing * 0.5,
        'sourceClass': _symbolClassName(clef),
        'penalty': 0.25,
      });
    }

    return regions;
  }

  List<String> _splitValidationReasons(String reason) {
    return reason
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _supportSourcesForScore(Map<String, dynamic> symbol) {
    final sources = <String>['onnx'];
    final support = _toDouble(symbol['structuralSupportScore']) ?? 0.0;
    final nonStem = _toDouble(symbol['nonStemSupportScore']) ?? 0.0;
    if (support > 0) sources.add('structural_support');
    if (nonStem > 0) sources.add('non_stem_support');
    return sources;
  }

  Map<String, int> _clefRegionStats({
    required List<Map<String, dynamic>> symbolGraph,
    required List<Map<String, dynamic>> clefSafetyRegions,
  }) {
    var coreRejected = 0;
    var transitionPenalties = 0;
    var validNearClef = 0;

    for (final item in symbolGraph) {
      final reasons = (item['rejectionReasons'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false);
      if (reasons.contains('overlap_core')) coreRejected++;
      if (reasons.contains('clef_transition_penalty')) transitionPenalties++;

      if (item['isRejected'] == true) continue;
      final className = _symbolClassName(item);
      if (className != 'notehead' && !_isAccidentalClass(className)) continue;
      final geometry = _symbolGeometry(item);
      if (geometry == null) continue;
      if (_regionContaining(geometry, clefSafetyRegions) == null) continue;

      final validation = item['validation'] as Map?;
      final reason = validation?['reason']?.toString() ?? '';
      final supportSources = (item['supportSources'] as List? ?? const [])
          .map((value) => value.toString())
          .toSet();
      final hasSupport =
          supportSources.contains('non_stem_support') ||
          reason.contains('attached') ||
          reason.contains('ledger') ||
          reason.contains('cluster');
      if (hasSupport) validNearClef++;
    }

    return {
      'coreRejected': coreRejected,
      'transitionPenalties': transitionPenalties,
      'validNearClef': validNearClef,
    };
  }

  _NoteheadValidation _validateNoteheadCandidate({
    required Map<String, dynamic> item,
    required List<Map<String, dynamic>> allSymbols,
    required List<dynamic> validatedStaffs,
    required List<dynamic> ledgerLines,
    required List<dynamic> stems,
    required List<dynamic> beams,
    required List<Map<String, dynamic>> semanticRegions,
    required List<Map<String, dynamic>> clefSafetyRegions,
    required Set<Map<String, dynamic>> timeSignatureLike,
  }) {
    final geometry = _symbolGeometry(item);
    if (geometry == null) {
      return const _NoteheadValidation.invalid('missing geometry');
    }

    final staff = _nearestStaffForSymbol(geometry, validatedStaffs);
    final spacing =
        _toDouble(staff?['validatedStaffSpacing'] ?? staff?['spacing']) ?? 12.0;
    final morphology = _noteheadMorphologyScore(geometry, spacing);
    final alignment = _staffAlignmentScore(geometry, staff);
    final confidence = (_toDouble(item['score'] ?? item['confidence']) ?? 0.50)
        .clamp(0.0, 1.0)
        .toDouble();
    final insideStaff = _insideAnyStaffRegion(
      geometry.centerY,
      validatedStaffs,
    );
    final ledgerSupported = _supportedByLedger(
      geometry,
      ledgerLines,
      spacing: spacing,
    );
    final overlapsClef = allSymbols.any((other) {
      final otherClass = _symbolClassName(other);
      if (otherClass != 'treble_clef' && otherClass != 'bass_clef')
        return false;
      final otherGeometry = _symbolGeometry(other);
      return otherGeometry != null && _iou(geometry, otherGeometry) >= 0.12;
    });

    final baseValid = _isBaseValidNotehead(
      insideStaff: insideStaff,
      ledgerSupported: ledgerSupported,
      morphology: morphology,
      alignment: alignment,
      overlapsClef: overlapsClef,
    );

    final wholeNote = _isWholeNoteShape(
      symbol: geometry,
      staff: staff,
      spacing: spacing,
      morphology: morphology,
      alignment: alignment,
      confidence: confidence,
      stems: stems,
    );

    final support = _computeNoteheadSupportScore(
      symbol: geometry,
      allSymbols: allSymbols,
      ledgerLines: ledgerLines,
      stems: stems,
      beams: beams,
      spacing: spacing,
    );

    double score = confidence;
    final reasons = <String>[];
    var attachmentPenalty = 0.0;

    if (!baseValid && !wholeNote) {
      if (!insideStaff && !ledgerSupported) reasons.add('outside staff/ledger');
      if (morphology < 0.38) reasons.add('weak morphology');
      if (alignment < 0.32) reasons.add('weak staff alignment');
    }

    score += (morphology - 0.50) * 0.20;
    score += (alignment - 0.50) * 0.18;
    score += support.total;

    if (overlapsClef) {
      score -= 0.12;
      reasons.add('clef overlap penalty');
    }

    final inPostClefRegion = _regionContaining(geometry, semanticRegions);
    final inClefSafetyRegion = _regionContaining(geometry, clefSafetyRegions);
    final attachment = wholeNote
        ? const _StemAttachmentAnalysis(
            type: StemAttachmentType.unknown,
            stem: null,
            stemCenterX: null,
          )
        : _analyzeStemAttachment(geometry, stems, spacing: spacing);
    final hasBeamSupport = _supportedByBeam(geometry, beams, spacing: spacing);
    final hasRhythmicNeighbor = _hasRhythmicNeighbor(
      geometry,
      allSymbols,
      spacing: spacing,
    );
    final hasNearbyNotehead = _nearSupportedNotehead(
      geometry,
      allSymbols,
      spacing: spacing,
    );
    final attachedToValidEdgeStem =
        attachment.type == StemAttachmentType.leftEdge ||
        attachment.type == StemAttachmentType.rightEdge;
    final structuralSupport = _StructuralSupportContext(
      ledger: ledgerSupported,
      edgeStem: attachedToValidEdgeStem,
      beam: hasBeamSupport,
      chord: hasNearbyNotehead,
      rhythmicGrouping: hasRhythmicNeighbor,
      centerStem: attachment.type == StemAttachmentType.center,
    );

    if (inPostClefRegion != null) {
      score -= 0.25;
      reasons.add('post-clef semantic penalty');
    }

    if (!wholeNote && inClefSafetyRegion != null) {
      final outsideClefCore = !_insideClefCore(geometry, inClefSafetyRegion);
      final stronglySupportedNearbyNote =
          attachedToValidEdgeStem &&
          hasBeamSupport &&
          hasRhythmicNeighbor &&
          outsideClefCore &&
          confidence >= 0.72;

      if (!stronglySupportedNearbyNote) {
        final protectedNearClef =
            outsideClefCore &&
            (ledgerSupported || hasNearbyNotehead || attachedToValidEdgeStem);
        var clefPenalty = protectedNearClef ? 0.08 : 0.30;
        reasons.add('clef safety region penalty');
        if (attachment.type == StemAttachmentType.center) {
          clefPenalty += 0.18;
          reasons.add('clef safety center_stem_attachment');
        }
        if (!hasBeamSupport) clefPenalty += 0.05;
        if (!hasRhythmicNeighbor) clefPenalty += 0.04;
        score -= clefPenalty.clamp(0.0, 0.50).toDouble();
      }
    }

    if (!wholeNote) {
      final clefPenalty = computeClefOverlapPenalty(
        symbol: geometry,
        clefSafetyRegions: clefSafetyRegions,
        staffSpacing: spacing,
        support: structuralSupport,
      );
      if (clefPenalty.reasons.isNotEmpty) {
        score -= clefPenalty.penalty;
        reasons.addAll(clefPenalty.reasons);
      }
    }

    if (!wholeNote &&
        attachment.type == StemAttachmentType.center &&
        inPostClefRegion != null) {
      var penalty = 0.45;
      reasons.add('center_stem_attachment');

      if (!hasBeamSupport) {
        penalty += 0.08;
        reasons.add('no beam support');
      }
      if (!hasRhythmicNeighbor) {
        penalty += 0.05;
        reasons.add('no rhythmic grouping');
      }
      if (!hasNearbyNotehead && support.nonStem < 0.08 && !ledgerSupported) {
        penalty += 0.06;
        reasons.add('isolated center-stem notehead');
      }
      if (overlapsClef) {
        penalty += 0.05;
        reasons.add('near clef center-stem');
      }
      if (timeSignatureLike.contains(item)) {
        penalty += 0.08;
        reasons.add('vertical numeral stack nearby');
      }

      attachmentPenalty = penalty.clamp(0.0, 0.72).toDouble();
      score -= attachmentPenalty;
    }

    if (!wholeNote &&
        inPostClefRegion != null &&
        _hasStemDirectionMismatch(
          notehead: geometry,
          stem: attachment.stem,
          attachmentType: attachment.type,
        )) {
      score -= 0.06;
      attachmentPenalty += 0.06;
      reasons.add('stem direction attachment mismatch');
    }

    if (timeSignatureLike.contains(item)) {
      score -= 0.38;
      reasons.add('vertical time-signature-like stack');
      if (inPostClefRegion != null || inClefSafetyRegion != null) {
        reasons.add('numeral_stack_near_clef');
      }
    }

    if (!wholeNote &&
        !hasNearbyNotehead &&
        support.total < 0.12 &&
        !ledgerSupported) {
      score -= 0.10;
      reasons.add('isolated notehead');
    }

    final threshold = inPostClefRegion == null ? 0.45 : 0.52;
    final finalScore = score.clamp(0.0, 1.0).toDouble();
    final valid = wholeNote
        ? finalScore >= 0.56 && !timeSignatureLike.contains(item)
        : baseValid && finalScore >= threshold;

    return _NoteheadValidation(
      valid: valid,
      baseValid: baseValid || wholeNote,
      finalScore: finalScore,
      supportScore: support.total,
      nonStemSupportScore: support.nonStem,
      attachmentType: attachment.type,
      attachmentStemCenterX: attachment.stemCenterX,
      attachmentPenalty: attachmentPenalty.clamp(0.0, 1.0).toDouble(),
      reason: valid
          ? wholeNote
                ? 'accepted whole-note geometry score=${finalScore.toStringAsFixed(2)}'
                : 'accepted score=${finalScore.toStringAsFixed(2)} support=${support.total.toStringAsFixed(2)} nonStem=${support.nonStem.toStringAsFixed(2)} attachment=${attachment.type.name}'
          : (reasons.isEmpty ? 'score below threshold' : reasons.join(', ')),
    );
  }

  bool _isBaseValidNotehead({
    required bool insideStaff,
    required bool ledgerSupported,
    required double morphology,
    required double alignment,
    required bool overlapsClef,
  }) {
    return (insideStaff || ledgerSupported) &&
        morphology >= 0.38 &&
        alignment >= 0.32;
  }

  _SupportScore _computeNoteheadSupportScore({
    required _SymbolGeometry symbol,
    required List<Map<String, dynamic>> allSymbols,
    required List<dynamic> ledgerLines,
    required List<dynamic> stems,
    required List<dynamic> beams,
    required double spacing,
  }) {
    var score = 0.0;
    var nonStem = 0.0;

    void add(double value, {required bool stem}) {
      score += value;
      if (!stem) nonStem += value;
    }

    if (_supportedByLedger(symbol, ledgerLines, spacing: spacing)) {
      add(0.18, stem: false);
    }
    if (_supportedByStem(symbol, stems, spacing: spacing)) score += 0.12;
    if (_supportedByBeam(symbol, beams, spacing: spacing)) {
      add(0.08, stem: false);
    }
    if (_nearSupportedNotehead(symbol, allSymbols, spacing: spacing)) {
      add(0.08, stem: false);
    }
    if (_hasRhythmicNeighbor(symbol, allSymbols, spacing: spacing)) {
      add(0.05, stem: false);
    }
    return _SupportScore(
      total: score.clamp(0.0, 0.36).toDouble(),
      nonStem: nonStem.clamp(0.0, 0.36).toDouble(),
    );
  }

  bool _isWholeNoteShape({
    required _SymbolGeometry symbol,
    required Map<String, dynamic>? staff,
    required double spacing,
    required double morphology,
    required double alignment,
    required double confidence,
    required List<dynamic> stems,
  }) {
    if (staff == null || spacing <= 0) return false;
    if (confidence < 0.68 || morphology < 0.62 || alignment < 0.58) {
      return false;
    }
    if (_supportedByStem(symbol, stems, spacing: spacing)) return false;

    final width = symbol.width;
    final height = symbol.height;
    if (width <= 0 || height <= 0) return false;
    final ratio = width > height ? width / height : height / width;
    if (ratio > 2.05) return false;
    if (width < spacing * 0.55 || width > spacing * 1.95) return false;
    if (height < spacing * 0.40 || height > spacing * 1.55) return false;

    return _insideExtendedStaffRegion(symbol.centerY, staff, spacing);
  }

  bool _isAccidentalClass(String className) {
    return className == 'sharp' ||
        className == 'flat' ||
        className == 'natural';
  }

  List<Map<String, dynamic>> _generateInferredLedgerNoteheads({
    required List<Map<String, dynamic>> validSymbols,
    required List<Map<String, dynamic>> rejectedNoteheads,
    required List<dynamic> ledgerLines,
    required List<dynamic> stems,
    required List<dynamic> validatedStaffs,
  }) {
    final inferred = <Map<String, dynamic>>[];

    for (final ledgerItem in ledgerLines.whereType<Map>()) {
      final ledger = Map<String, dynamic>.from(
        ledgerItem.map((key, value) => MapEntry(key.toString(), value)),
      );
      final staffId = ledger['staffId']?.toString();
      final x1 = _toDouble(ledger['x1']);
      final x2 = _toDouble(ledger['x2']);
      final y = _toDouble(ledger['y']);
      if (staffId == null || x1 == null || x2 == null || y == null) continue;

      final staff = _staffById(validatedStaffs, staffId);
      final spacing =
          _toDouble(staff?['validatedStaffSpacing'] ?? staff?['spacing']) ??
          12.0;
      if (spacing <= 0) continue;

      final ledgerCenterX = (x1 + x2) / 2.0;
      Map<String, dynamic>? supportingStem;
      for (final rawStem in stems.whereType<Map>()) {
        final stem = Map<String, dynamic>.from(
          rawStem.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (stem['staffId']?.toString() != staffId) continue;
        final sx = _toDouble(stem['x']);
        final sy1 = _toDouble(stem['y1']);
        final sy2 = _toDouble(stem['y2']);
        if (sx == null || sy1 == null || sy2 == null) continue;
        final xClose = sx >= x1 - spacing * 1.3 && sx <= x2 + spacing * 1.3;
        final yClose = y >= sy1 - spacing * 0.9 && y <= sy2 + spacing * 0.9;
        if (xClose && yClose) {
          supportingStem = stem;
          break;
        }
      }
      if (supportingStem == null) continue;

      final stemX = _toDouble(supportingStem['x']) ?? ledgerCenterX;
      final centerX = (stemX - ledgerCenterX).abs() <= spacing * 1.3
          ? (stemX + ledgerCenterX) / 2.0
          : ledgerCenterX;

      final candidate = _SymbolGeometry(
        x1: centerX - spacing * 0.52,
        y1: y - spacing * 0.38,
        x2: centerX + spacing * 0.52,
        y2: y + spacing * 0.38,
        centerX: centerX,
        centerY: y,
      );

      final alreadyRepresented =
          validSymbols.any((symbol) {
            if (_symbolClassName(symbol) != 'notehead') return false;
            final geometry = _symbolGeometry(symbol);
            if (geometry == null) return false;
            return (geometry.centerX - candidate.centerX).abs() <=
                    spacing * 0.9 &&
                (geometry.centerY - candidate.centerY).abs() <= spacing * 0.7;
          }) ||
          rejectedNoteheads.any((symbol) {
            final geometry = _symbolGeometry(symbol);
            if (geometry == null) return false;
            return (geometry.centerX - candidate.centerX).abs() <=
                    spacing * 0.55 &&
                (geometry.centerY - candidate.centerY).abs() <= spacing * 0.45;
          }) ||
          inferred.any((symbol) {
            final geometry = _symbolGeometry(symbol);
            if (geometry == null) return false;
            return (geometry.centerX - candidate.centerX).abs() <=
                    spacing * 0.9 &&
                (geometry.centerY - candidate.centerY).abs() <= spacing * 0.7;
          });
      if (alreadyRepresented) continue;

      final ledgerId = ledger['id']?.toString() ?? 'ledger_${inferred.length}';
      final stemId = supportingStem['id']?.toString() ?? 'stem_unknown';
      inferred.add({
        'id': 'inferred_notehead_${inferred.length}',
        'className': 'notehead',
        'centerX': candidate.centerX,
        'centerY': candidate.centerY,
        'x': candidate.centerX,
        'y': candidate.centerY,
        'bbox': [candidate.x1, candidate.y1, candidate.x2, candidate.y2],
        'score': 0.64,
        'confidence': 0.64,
        'symbolState': 'inferred',
        'structuralScore': 0.64,
        'isInferred': true,
        'isRejected': false,
        'inferred': true,
        'inferredReason':
            'validated ledger and stem with missing ONNX notehead',
        'supportingLedgerId': ledgerId,
        'supportingStemId': stemId,
        'supportingStructureIds': [ledgerId, stemId],
        'supportSources': [ledgerId, stemId],
        'rejectionReasons': const <String>[],
        'validation': const {
          'reason': 'inferred from ledger/stem structure',
          'baseValid': true,
          'supportScore': 0.30,
          'nonStemSupportScore': 0.18,
        },
        'validationReason': 'inferred from ledger/stem structure',
        'structuralSupportScore': 0.30,
        'nonStemSupportScore': 0.18,
        'finalValidationScore': 0.64,
      });
    }

    return inferred;
  }

  Map<String, dynamic>? _staffById(List<dynamic> validatedStaffs, String id) {
    for (final item in validatedStaffs) {
      if (item is! Map) continue;
      if (item['id']?.toString() != id) continue;
      return Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return null;
  }

  _SymbolAttachmentValidation _validateAccidental({
    required _SymbolGeometry symbol,
    required List<Map<String, dynamic>> validSymbols,
    required List<dynamic> ledgerLines,
    required List<dynamic> validatedStaffs,
    required List<Map<String, dynamic>> clefSafetyRegions,
  }) {
    final staff = _nearestStaffForSymbol(symbol, validatedStaffs);
    final spacing =
        _toDouble(staff?['validatedStaffSpacing'] ?? staff?['spacing']) ?? 12.0;
    final clefPenalty = computeClefOverlapPenalty(
      symbol: symbol,
      clefSafetyRegions: clefSafetyRegions,
      staffSpacing: spacing,
      support: const _StructuralSupportContext(
        ledger: false,
        edgeStem: false,
        beam: false,
        chord: false,
        rhythmicGrouping: false,
        centerStem: false,
      ),
    );

    final attachedNotehead = validSymbols.any((item) {
      if (_symbolClassName(item) != 'notehead') return false;
      final note = _symbolGeometry(item);
      if (note == null) return false;
      final leftOfNote = symbol.centerX < note.centerX;
      final horizontalDistance = note.centerX - symbol.centerX;
      final verticallyClose =
          (note.centerY - symbol.centerY).abs() <= spacing * 1.35;
      return leftOfNote &&
          horizontalDistance >= spacing * 0.20 &&
          horizontalDistance <= spacing * 3.2 &&
          verticallyClose;
    });
    if (attachedNotehead) {
      return const _SymbolAttachmentValidation(
        valid: true,
        reason: 'attached to validated notehead',
      );
    }

    if (clefPenalty.reasons.isNotEmpty && clefPenalty.penalty >= 0.18) {
      return _SymbolAttachmentValidation(
        valid: false,
        reason: ['unsupported_accidental', ...clefPenalty.reasons].join(', '),
      );
    }

    final ledgerContext =
        _supportedByLedger(symbol, ledgerLines, spacing: spacing) &&
        validSymbols.any((item) {
          if (_symbolClassName(item) != 'notehead') return false;
          final note = _symbolGeometry(item);
          if (note == null) return false;
          return (note.centerX - symbol.centerX).abs() <= spacing * 3.6 &&
              (note.centerY - symbol.centerY).abs() <= spacing * 1.8;
        });
    if (ledgerContext) {
      return const _SymbolAttachmentValidation(
        valid: true,
        reason: 'ledger note accidental context',
      );
    }

    final clusterContext = validSymbols.where((item) {
      final className = _symbolClassName(item);
      if (className != 'notehead' && !_isAccidentalClass(className)) {
        return false;
      }
      final other = _symbolGeometry(item);
      if (other == null) return false;
      return (other.centerX - symbol.centerX).abs() <= spacing * 3.0 &&
          (other.centerY - symbol.centerY).abs() <= spacing * 2.0;
    }).length;

    if (clusterContext >= 2 &&
        _insideExtendedStaffRegion(symbol.centerY, staff, spacing)) {
      return const _SymbolAttachmentValidation(
        valid: true,
        reason: 'musical context cluster',
      );
    }

    return const _SymbolAttachmentValidation(
      valid: false,
      reason: 'no validated note attachment',
    );
  }

  String _symbolClassName(Map<String, dynamic> item) {
    return (item['className'] ?? item['labelName'] ?? item['label'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
  }

  _SymbolGeometry? _symbolGeometry(Map<String, dynamic> item) {
    if (item['bbox'] is List && (item['bbox'] as List).length >= 4) {
      final bbox = List.from(item['bbox']);
      final x1 = _toDouble(bbox[0]);
      final y1 = _toDouble(bbox[1]);
      final x2 = _toDouble(bbox[2]);
      final y2 = _toDouble(bbox[3]);
      if (x1 == null || y1 == null || x2 == null || y2 == null) return null;

      final left = x1 < x2 ? x1 : x2;
      final right = x1 < x2 ? x2 : x1;
      final top = y1 < y2 ? y1 : y2;
      final bottom = y1 < y2 ? y2 : y1;
      return _SymbolGeometry(
        x1: left,
        y1: top,
        x2: right,
        y2: bottom,
        centerX: (left + right) / 2.0,
        centerY: (top + bottom) / 2.0,
      );
    }

    final centerX = _toDouble(item['centerX'] ?? item['x']);
    final centerY = _toDouble(item['centerY'] ?? item['y']);
    if (centerX == null || centerY == null) return null;
    return _SymbolGeometry(
      x1: centerX,
      y1: centerY,
      x2: centerX,
      y2: centerY,
      centerX: centerX,
      centerY: centerY,
    );
  }

  Map<String, dynamic>? _nearestStaffForSymbol(
    _SymbolGeometry symbol,
    List<dynamic> validatedStaffs,
  ) {
    Map<String, dynamic>? best;
    double? bestDistance;

    for (final item in validatedStaffs) {
      if (item is! Map) continue;
      final staff = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
      final top = _toDouble(staff['topBoundary']);
      final bottom = _toDouble(staff['bottomBoundary']);
      if (top == null || bottom == null) continue;
      final center = (top + bottom) / 2.0;
      final distance = symbol.centerY >= top && symbol.centerY <= bottom
          ? 0.0
          : (symbol.centerY - center).abs();
      if (bestDistance == null || distance < bestDistance) {
        best = staff;
        bestDistance = distance;
      }
    }

    return best;
  }

  bool _insideAnyStaffRegion(double y, List<dynamic> validatedStaffs) {
    for (final item in validatedStaffs) {
      if (item is! Map) continue;
      final top = _toDouble(item['topBoundary']);
      final bottom = _toDouble(item['bottomBoundary']);
      final spacing = _toDouble(item['spacing']) ?? 12.0;
      if (top == null || bottom == null) continue;
      if (y >= top - spacing * 0.35 && y <= bottom + spacing * 0.35) {
        return true;
      }
    }
    return false;
  }

  bool _insideExtendedStaffRegion(
    double y,
    Map<String, dynamic>? staff,
    double spacing,
  ) {
    if (staff == null) return false;
    final top = _toDouble(staff['topBoundary']);
    final bottom = _toDouble(staff['bottomBoundary']);
    if (top == null || bottom == null) return false;
    return y >= top - spacing * 5.5 && y <= bottom + spacing * 5.5;
  }

  double _noteheadMorphologyScore(_SymbolGeometry symbol, double spacing) {
    final width = symbol.width;
    final height = symbol.height;
    if (width <= 0 || height <= 0 || spacing <= 0) return 0.0;

    final ratio = width > height ? width / height : height / width;
    final ratioScore = (1.0 - ((ratio - 1.25).abs() / 1.25))
        .clamp(0.0, 1.0)
        .toDouble();
    final widthScore =
        (1.0 - ((width - spacing * 0.95).abs() / (spacing * 0.9)))
            .clamp(0.0, 1.0)
            .toDouble();
    final heightScore =
        (1.0 - ((height - spacing * 0.75).abs() / (spacing * 0.75)))
            .clamp(0.0, 1.0)
            .toDouble();

    return (ratioScore * 0.42 + widthScore * 0.30 + heightScore * 0.28)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _staffAlignmentScore(
    _SymbolGeometry symbol,
    Map<String, dynamic>? staff,
  ) {
    if (staff == null) return 0.0;
    final rawLines = staff['lines'];
    if (rawLines is! List || rawLines.length < 2) return 0.0;
    final lines = rawLines.map(_toDouble).whereType<double>().toList()..sort();
    if (lines.length < 2) return 0.0;
    final spacing = _toDouble(staff['spacing']) ?? _averageSpacing(lines);
    if (spacing <= 0) return 0.0;

    final anchors = <double>[];
    for (var i = -5; i <= 9; i++) {
      anchors.add(lines.first + spacing * 0.5 * i);
    }

    final nearest = anchors
        .map((anchor) => (anchor - symbol.centerY).abs())
        .fold<double>(
          double.infinity,
          (best, value) => value < best ? value : best,
        );

    return (1.0 - (nearest / (spacing * 0.34))).clamp(0.0, 1.0).toDouble();
  }

  double _averageSpacing(List<double> lines) {
    if (lines.length < 2) return 12.0;
    final spacings = <double>[];
    for (var i = 1; i < lines.length; i++) {
      spacings.add((lines[i] - lines[i - 1]).abs());
    }
    return spacings.reduce((a, b) => a + b) / spacings.length;
  }

  bool _supportedByLedger(
    _SymbolGeometry symbol,
    List<dynamic> ledgerLines, {
    double? spacing,
  }) {
    final unit = spacing ?? 12.0;
    for (final item in ledgerLines) {
      if (item is! Map) continue;
      final x1 = _toDouble(item['x1']);
      final x2 = _toDouble(item['x2']);
      final y = _toDouble(item['y']);
      if (x1 == null || x2 == null || y == null) continue;

      final yClose = (symbol.centerY - y).abs() <= unit * 1.35;
      final xClose =
          symbol.centerX >= x1 - unit * 1.8 &&
          symbol.centerX <= x2 + unit * 1.8;
      if (yClose && xClose) return true;
    }
    return false;
  }

  bool _supportedByStem(
    _SymbolGeometry symbol,
    List<dynamic> stems, {
    double? spacing,
  }) {
    final unit = spacing ?? 12.0;
    for (final item in stems) {
      if (item is! Map) continue;
      final x = _toDouble(item['x']);
      final y1 = _toDouble(item['y1']);
      final y2 = _toDouble(item['y2']);
      if (x == null || y1 == null || y2 == null) continue;

      final xClose =
          x >= symbol.x1 - unit * 0.65 && x <= symbol.x2 + unit * 0.65;
      final yClose =
          y2 >= symbol.y1 - unit * 0.9 && y1 <= symbol.y2 + unit * 4.2;
      if (xClose && yClose) return true;
    }
    return false;
  }

  _StemAttachmentAnalysis _analyzeStemAttachment(
    _SymbolGeometry notehead,
    List<dynamic> stems, {
    required double spacing,
  }) {
    final stem = _supportingStemForNotehead(notehead, stems, spacing: spacing);
    if (stem == null) {
      return const _StemAttachmentAnalysis(
        type: StemAttachmentType.unknown,
        stem: null,
        stemCenterX: null,
      );
    }

    final stemGeometry = _stemGeometry(stem, spacing: spacing);
    if (stemGeometry == null) {
      return _StemAttachmentAnalysis(
        type: StemAttachmentType.unknown,
        stem: stem,
        stemCenterX: null,
      );
    }

    return _StemAttachmentAnalysis(
      type: computeStemAttachmentType(notehead, stemGeometry),
      stem: stem,
      stemCenterX: stemGeometry.centerX,
    );
  }

  StemAttachmentType computeStemAttachmentType(
    _SymbolGeometry noteheadBBox,
    _SymbolGeometry stemBBox,
  ) {
    final width = noteheadBBox.width;
    if (width <= 0) return StemAttachmentType.unknown;

    final stemCenterX = stemBBox.centerX;
    if (stemCenterX.isNaN || stemCenterX.isInfinite) {
      return StemAttachmentType.unknown;
    }

    final centerLeft = noteheadBBox.x1 + width * 0.30;
    final centerRight = noteheadBBox.x1 + width * 0.70;
    if (centerLeft >= centerRight) return StemAttachmentType.unknown;

    if (stemCenterX < centerLeft) return StemAttachmentType.leftEdge;
    if (stemCenterX > centerRight) return StemAttachmentType.rightEdge;
    return StemAttachmentType.center;
  }

  Map<String, dynamic>? _supportingStemForNotehead(
    _SymbolGeometry notehead,
    List<dynamic> stems, {
    required double spacing,
  }) {
    Map<String, dynamic>? bestStem;
    double bestDistance = double.infinity;
    final unit = spacing > 0 ? spacing : 12.0;

    for (final item in stems) {
      if (item is! Map) continue;
      final stem = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
      final stemGeometry = _stemGeometry(stem, spacing: unit);
      if (stemGeometry == null) continue;

      final xClose =
          stemGeometry.centerX >= notehead.x1 - unit * 0.65 &&
          stemGeometry.centerX <= notehead.x2 + unit * 0.65;
      final yIntersects =
          stemGeometry.y2 >= notehead.y1 - unit * 0.9 &&
          stemGeometry.y1 <= notehead.y2 + unit * 4.2;
      if (!xClose || !yIntersects) continue;

      final edgeDistance = [
        (stemGeometry.centerX - notehead.x1).abs(),
        (stemGeometry.centerX - notehead.x2).abs(),
      ].reduce((a, b) => a < b ? a : b);
      final verticalOverlapPenalty =
          stemGeometry.y1 <= notehead.y2 && stemGeometry.y2 >= notehead.y1
          ? 0.0
          : unit * 0.25;
      final distance = edgeDistance + verticalOverlapPenalty;

      if (distance < bestDistance) {
        bestDistance = distance;
        bestStem = stem;
      }
    }

    return bestStem;
  }

  _SymbolGeometry? _stemGeometry(
    Map<String, dynamic> stem, {
    required double spacing,
  }) {
    final rawX1 = _toDouble(stem['x1'] ?? stem['left'] ?? stem['xmin']);
    final rawX2 = _toDouble(stem['x2'] ?? stem['right'] ?? stem['xmax']);
    final rawY1 = _toDouble(stem['y1'] ?? stem['top'] ?? stem['ymin']);
    final rawY2 = _toDouble(stem['y2'] ?? stem['bottom'] ?? stem['ymax']);
    final x = _toDouble(stem['x'] ?? stem['centerX']);

    if (rawY1 == null || rawY2 == null) return null;
    if (x == null && (rawX1 == null || rawX2 == null)) return null;

    final halfWidth = (spacing > 0 ? spacing : 12.0) * 0.08;
    final left = rawX1 ?? (x! - halfWidth);
    final right = rawX2 ?? (x! + halfWidth);
    final top = rawY1 < rawY2 ? rawY1 : rawY2;
    final bottom = rawY1 < rawY2 ? rawY2 : rawY1;
    final normalizedLeft = left < right ? left : right;
    final normalizedRight = left < right ? right : left;

    if (bottom <= top || normalizedRight < normalizedLeft) return null;

    return _SymbolGeometry(
      x1: normalizedLeft,
      y1: top,
      x2: normalizedRight,
      y2: bottom,
      centerX: (normalizedLeft + normalizedRight) / 2.0,
      centerY: (top + bottom) / 2.0,
    );
  }

  bool _hasStemDirectionMismatch({
    required _SymbolGeometry notehead,
    required Map<String, dynamic>? stem,
    required StemAttachmentType attachmentType,
  }) {
    if (stem == null) return false;
    if (attachmentType != StemAttachmentType.leftEdge &&
        attachmentType != StemAttachmentType.rightEdge) {
      return false;
    }

    final y1 = _toDouble(stem['y1'] ?? stem['top'] ?? stem['ymin']);
    final y2 = _toDouble(stem['y2'] ?? stem['bottom'] ?? stem['ymax']);
    if (y1 == null || y2 == null) return false;

    final top = y1 < y2 ? y1 : y2;
    final bottom = y1 < y2 ? y2 : y1;
    final extendsUp = top < notehead.centerY && bottom <= notehead.y2;
    final extendsDown = bottom > notehead.centerY && top >= notehead.y1;

    if (extendsUp && attachmentType == StemAttachmentType.leftEdge) return true;
    if (extendsDown && attachmentType == StemAttachmentType.rightEdge)
      return true;
    return false;
  }

  bool _supportedByBeam(
    _SymbolGeometry symbol,
    List<dynamic> beams, {
    double? spacing,
  }) {
    final unit = spacing ?? 12.0;
    for (final item in beams) {
      if (item is! Map) continue;
      final x1 = _toDouble(item['x1']);
      final x2 = _toDouble(item['x2']);
      final y = _toDouble(item['y']);
      if (x1 == null || x2 == null || y == null) continue;
      final xClose = symbol.centerX >= x1 - unit && symbol.centerX <= x2 + unit;
      final yClose = (symbol.centerY - y).abs() <= unit * 5.0;
      if (xClose && yClose) return true;
    }
    return false;
  }

  bool _nearSupportedNotehead(
    _SymbolGeometry symbol,
    List<Map<String, dynamic>> symbols, {
    double? spacing,
  }) {
    final unit = spacing ?? 12.0;
    return symbols.any((item) {
      if (_symbolClassName(item) != 'notehead') return false;
      final notehead = _symbolGeometry(item);
      if (notehead == null) return false;
      if ((notehead.centerX - symbol.centerX).abs() < 0.01 &&
          (notehead.centerY - symbol.centerY).abs() < 0.01) {
        return false;
      }
      return (notehead.centerX - symbol.centerX).abs() <= unit * 1.2 &&
          (notehead.centerY - symbol.centerY).abs() <= unit * 2.0;
    });
  }

  bool _hasRhythmicNeighbor(
    _SymbolGeometry symbol,
    List<Map<String, dynamic>> symbols, {
    required double spacing,
  }) {
    return symbols.any((item) {
      if (_symbolClassName(item) != 'notehead') return false;
      final other = _symbolGeometry(item);
      if (other == null) return false;
      if ((other.centerX - symbol.centerX).abs() < 0.01 &&
          (other.centerY - symbol.centerY).abs() < 0.01) {
        return false;
      }
      final dx = (other.centerX - symbol.centerX).abs();
      if (dx <= spacing * 1.2 || dx > spacing * 8.0) return false;
      return (other.centerY - symbol.centerY).abs() <= spacing * 4.0;
    });
  }

  Map<String, dynamic>? _regionContaining(
    _SymbolGeometry symbol,
    List<Map<String, dynamic>> regions,
  ) {
    for (final region in regions) {
      final x1 = _toDouble(region['x1']);
      final x2 = _toDouble(region['x2']);
      final y1 = _toDouble(region['y1']);
      final y2 = _toDouble(region['y2']);
      if (x1 == null || x2 == null || y1 == null || y2 == null) continue;
      if (symbol.centerX >= x1 &&
          symbol.centerX <= x2 &&
          symbol.centerY >= y1 &&
          symbol.centerY <= y2) {
        return region;
      }
    }
    return null;
  }

  bool _insideClefCore(
    _SymbolGeometry symbol,
    Map<String, dynamic> clefSafetyRegion,
  ) {
    final x1 = _toDouble(clefSafetyRegion['coreX1']);
    final x2 = _toDouble(clefSafetyRegion['coreX2']);
    final y1 = _toDouble(clefSafetyRegion['coreY1']);
    final y2 = _toDouble(clefSafetyRegion['coreY2']);
    if (x1 == null || x2 == null || y1 == null || y2 == null) return false;
    final core = _SymbolGeometry(
      x1: x1 < x2 ? x1 : x2,
      y1: y1 < y2 ? y1 : y2,
      x2: x1 < x2 ? x2 : x1,
      y2: y1 < y2 ? y2 : y1,
      centerX: (x1 + x2) / 2.0,
      centerY: (y1 + y2) / 2.0,
    );
    return _iou(symbol, core) >= 0.08 || _centerInside(symbol, core);
  }

  _ClefOverlapPenalty computeClefOverlapPenalty({
    required _SymbolGeometry symbol,
    required List<Map<String, dynamic>> clefSafetyRegions,
    required double staffSpacing,
    required _StructuralSupportContext support,
  }) {
    final spacing = staffSpacing > 0 ? staffSpacing : 12.0;

    for (final region in clefSafetyRegions) {
      final core = _regionGeometry(
        region,
        x1Key: 'coreX1',
        x2Key: 'coreX2',
        y1Key: 'coreY1',
        y2Key: 'coreY2',
      );
      final expansion = _regionGeometry(
        region,
        x1Key: 'expansionX1',
        x2Key: 'expansionX2',
        y1Key: 'expansionY1',
        y2Key: 'expansionY2',
      );
      final transition = _regionGeometry(
        region,
        x1Key: 'transitionX1',
        x2Key: 'transitionX2',
        y1Key: 'transitionY1',
        y2Key: 'transitionY2',
      );
      if (core == null || expansion == null || transition == null) continue;

      final inCore = _iou(symbol, core) >= 0.06 || _centerInside(symbol, core);
      final inExpansion =
          !inCore &&
          (_iou(symbol, expansion) >= 0.04 || _centerInside(symbol, expansion));
      final inTransition = _centerInside(symbol, transition);
      if (!inCore && !inExpansion && !inTransition) continue;

      final hasProtectiveSupport =
          support.ledger || support.edgeStem || support.beam || support.chord;
      final outsideTransition = symbol.centerX > transition.x2 + spacing * 0.35;
      if (outsideTransition) {
        return const _ClefOverlapPenalty(
          penalty: 0.0,
          reasons: [],
          coreRejected: false,
          transitionPenalty: false,
          validNearClef: false,
        );
      }

      if (hasProtectiveSupport && !inCore) {
        return const _ClefOverlapPenalty(
          penalty: 0.0,
          reasons: [],
          coreRejected: false,
          transitionPenalty: false,
          validNearClef: true,
        );
      }

      final reasons = <String>[];
      var penalty = 0.0;

      if (inCore) {
        penalty += hasProtectiveSupport ? 0.34 : 0.62;
        reasons.add('overlap_core');
      } else if (inExpansion) {
        penalty += hasProtectiveSupport ? 0.10 : 0.34;
        reasons.add('clef_expansion_overlap');
      } else if (inTransition) {
        penalty += hasProtectiveSupport ? 0.06 : 0.18;
        reasons.add('clef_transition_penalty');
      }

      if (support.centerStem && (inCore || inExpansion || inTransition)) {
        penalty += 0.22;
        reasons.add('center_attachment_near_clef');
      }

      if (!support.rhythmicGrouping && !hasProtectiveSupport) {
        penalty += inCore ? 0.18 : 0.08;
        reasons.add('no rhythmic grouping');
      }

      return _ClefOverlapPenalty(
        penalty: penalty.clamp(0.0, 0.82).toDouble(),
        reasons: reasons,
        coreRejected: inCore && penalty >= 0.50,
        transitionPenalty: inTransition,
        validNearClef: hasProtectiveSupport && penalty < 0.20,
      );
    }

    return const _ClefOverlapPenalty(
      penalty: 0.0,
      reasons: [],
      coreRejected: false,
      transitionPenalty: false,
      validNearClef: false,
    );
  }

  _SymbolGeometry? _regionGeometry(
    Map<String, dynamic> region, {
    required String x1Key,
    required String x2Key,
    required String y1Key,
    required String y2Key,
  }) {
    final x1 = _toDouble(region[x1Key]);
    final x2 = _toDouble(region[x2Key]);
    final y1 = _toDouble(region[y1Key]);
    final y2 = _toDouble(region[y2Key]);
    if (x1 == null || x2 == null || y1 == null || y2 == null) return null;
    final left = x1 < x2 ? x1 : x2;
    final right = x1 < x2 ? x2 : x1;
    final top = y1 < y2 ? y1 : y2;
    final bottom = y1 < y2 ? y2 : y1;
    return _SymbolGeometry(
      x1: left,
      y1: top,
      x2: right,
      y2: bottom,
      centerX: (left + right) / 2.0,
      centerY: (top + bottom) / 2.0,
    );
  }

  Set<Map<String, dynamic>> _likelyTimeSignatureNoteheads({
    required List<Map<String, dynamic>> noteheadCandidates,
    required List<Map<String, dynamic>> semanticRegions,
    required List<dynamic> stems,
    required List<dynamic> beams,
  }) {
    final likely = <Map<String, dynamic>>{};

    for (final region in semanticRegions) {
      final regionSpacing =
          ((_toDouble(region['x2']) ?? 0) - (_toDouble(region['x1']) ?? 0)) /
          6.0;
      final spacing = regionSpacing > 0 ? regionSpacing : 12.0;
      final inside = noteheadCandidates.where((item) {
        final geometry = _symbolGeometry(item);
        if (geometry == null || _regionContaining(geometry, [region]) == null) {
          return false;
        }
        final hasStructure =
            _supportedByStem(geometry, stems, spacing: spacing) ||
            _supportedByBeam(geometry, beams, spacing: spacing);
        return !hasStructure;
      }).toList();

      for (var i = 0; i < inside.length; i++) {
        final a = _symbolGeometry(inside[i]);
        if (a == null) continue;
        final stack = inside.where((item) {
          final b = _symbolGeometry(item);
          if (b == null) return false;
          return (a.centerX - b.centerX).abs() <= spacing * 1.15 &&
              (a.centerY - b.centerY).abs() >= spacing * 0.65 &&
              (a.centerY - b.centerY).abs() <= spacing * 4.8;
        }).toList();
        if (stack.length >= 1) {
          likely.add(inside[i]);
          likely.addAll(stack);
        }
      }
    }

    return likely;
  }

  bool _centerInside(_SymbolGeometry inner, _SymbolGeometry outer) {
    return inner.centerX >= outer.x1 &&
        inner.centerX <= outer.x2 &&
        inner.centerY >= outer.y1 &&
        inner.centerY <= outer.y2;
  }

  double _iou(_SymbolGeometry a, _SymbolGeometry b) {
    final left = a.x1 > b.x1 ? a.x1 : b.x1;
    final top = a.y1 > b.y1 ? a.y1 : b.y1;
    final right = a.x2 < b.x2 ? a.x2 : b.x2;
    final bottom = a.y2 < b.y2 ? a.y2 : b.y2;
    final intersection =
        ((right - left) > 0 ? right - left : 0.0) *
        ((bottom - top) > 0 ? bottom - top : 0.0);
    if (intersection <= 0) return 0;

    final areaA =
        ((a.x2 - a.x1) > 0 ? a.x2 - a.x1 : 0.0) *
        ((a.y2 - a.y1) > 0 ? a.y2 - a.y1 : 0.0);
    final areaB =
        ((b.x2 - b.x1) > 0 ? b.x2 - b.x1 : 0.0) *
        ((b.y2 - b.y1) > 0 ? b.y2 - b.y1 : 0.0);
    final union = areaA + areaB - intersection;
    if (union <= 0) return 0;
    return intersection / union;
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.backgroundSecondary,
                AppColors.background,
                AppColors.surface,
              ],
            ),
          ),
          child: Column(
            children: [
              _ProcessingHeader(
                helpTourKey: _processingHelpTourKey,
                onBackTap: () => Navigator.pop(context),
                onHelpTap: () {
                  TutorialService.showHowToUse(
                    context,
                    page: TutorialPage.processingPage,
                    onStartTour: () => TutorialService.showProcessingGuide(
                      context,
                      _processingTourKeys,
                    ),
                  );
                },
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// Top summary card with thumbnail, status, and progress.
                      TutorialService.showcase(
                        key: _processingProgressTourKey,
                        title: 'Reading Progress',
                        description:
                            'This shows how far STALA has read your sheet and what it is doing now.',
                        child: _ProcessingSummaryCard(
                          progressValue: _progressValue,
                          title: _hasProcessingFailed
                              ? 'Could Not Read Sheet'
                              : _isProcessingFinished
                              ? 'Tablature Ready'
                              : 'Reading Your Music',
                          subtitle: _statusMessage,
                          imagePath: widget.croppedImagePath,
                          completedCount: _completedStageCount,
                          totalCount: _stages.length,
                          isFinished: _isProcessingFinished,
                          hasFailed: _hasProcessingFailed,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Current Steps',
                        style: AppTextStyles.sectionTitle.copyWith(
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 12),

                      /// Scrollable list of pipeline stage cards.
                      Expanded(
                        child: TutorialService.showcase(
                          key: _processingStepsTourKey,
                          title: 'Reading Steps',
                          description:
                              'These steps show the path from your sheet image to the final guitar tab.',
                          child: ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            itemCount: _stages.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final stage = _stages[index];
                              return _ProcessingStageCard(
                                stage: stage,
                                isActive:
                                    index == _activeStageIndex &&
                                    !_isProcessingFinished &&
                                    !_hasProcessingFailed,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              /// Footer reacts to three states:
              /// running, failed, and completed.
              TutorialService.showcase(
                key: _processingFooterTourKey,
                title: 'Next Step',
                description:
                    'When reading is finished, use this area to open the result or try again if needed.',
                child: _ProcessingFooter(
                  isFinished: _isProcessingFinished,
                  hasFailed: _hasProcessingFailed,
                  onRetry: _retryProcessing,
                  onContinue: _showNextStepMessage,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<SymbolClassItem> _parseClassItems(dynamic rawDetections) {
    if (rawDetections is! List) return const [];

    final List<SymbolClassItem> items = [];

    for (final item in rawDetections) {
      if (item is! Map) continue;

      final map = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );

      final className =
          map['className']?.toString() ??
          map['labelName']?.toString() ??
          map['label']?.toString() ??
          'unknown';

      final score = _toDouble(map['score'] ?? map['confidence']);

      double? centerX;
      double? centerY;
      List<double>? bbox;

      if (map['bbox'] is List && (map['bbox'] as List).length >= 4) {
        final rawBbox = List.from(map['bbox']);
        final x1 = _toDouble(rawBbox[0]);
        final y1 = _toDouble(rawBbox[1]);
        final x2 = _toDouble(rawBbox[2]);
        final y2 = _toDouble(rawBbox[3]);

        if (x1 != null && y1 != null && x2 != null && y2 != null) {
          bbox = [x1, y1, x2, y2];
          centerX = (x1 + x2) / 2.0;
          centerY = (y1 + y2) / 2.0;
        }
      }

      centerX ??= _toDouble(map['centerX']);
      centerY ??= _toDouble(map['centerY']);

      if (centerX == null || centerY == null) continue;

      items.add(
        SymbolClassItem(
          className: className,
          x: centerX,
          y: centerY,
          score: score,
          bbox: bbox,
          symbolState: SymbolState.fromValue(map['symbolState']),
          validationReason: map['validationReason']?.toString(),
          inferredReason: map['inferredReason']?.toString(),
        ),
      );
    }

    return _sortSymbolsTopLeftToBottomRight(items);
  }

  List<SymbolClassItem> _sortSymbolsTopLeftToBottomRight(
    List<SymbolClassItem> items,
  ) {
    final sorted = List<SymbolClassItem>.from(items);

    const double rowTolerance = 12.0;

    sorted.sort((a, b) {
      final yDiff = (a.y - b.y).abs();

      if (yDiff <= rowTolerance) {
        return a.x.compareTo(b.x);
      }

      return a.y.compareTo(b.y);
    });

    return sorted;
  }

  List<LedgerLineViewItem> _parseConfirmedLedgerLines(
    dynamic rawLedgerLines,
    List<StaffTranslateGroup> groups,
  ) {
    if (rawLedgerLines is! List) return const [];

    final result = <LedgerLineViewItem>[];

    for (final item in rawLedgerLines) {
      if (item is! Map) continue;

      final map = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );

      final staffId = map['staffId']?.toString();
      final x1 = _toDouble(map['x1']);
      final x2 = _toDouble(map['x2']);
      final y = _toDouble(map['y']);

      if (staffId == null || x1 == null || x2 == null || y == null) continue;

      result.add(LedgerLineViewItem(staffId: staffId, x1: x1, x2: x2, y: y));
    }

    return result;
  }
}

/// Top app header for the processing page.
class _ProcessingHeader extends StatelessWidget {
  final GlobalKey helpTourKey;
  final VoidCallback onBackTap;
  final VoidCallback onHelpTap;

  const _ProcessingHeader({
    required this.helpTourKey,
    required this.onBackTap,
    required this.onHelpTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          _HeaderCircleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: onBackTap,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Reading Sheet',
              style: AppTextStyles.sectionTitle.copyWith(fontSize: 20),
            ),
          ),
          TutorialService.showcase(
            key: helpTourKey,
            title: 'Need Processing Help?',
            description:
                'Tap this if you want a quick reminder about what this screen is doing.',
            targetShapeBorder: const CircleBorder(),
            child: _HeaderCircleButton(
              icon: Icons.help_outline_rounded,
              onTap: onHelpTap,
            ),
          ),
        ],
      ),
    );
  }
}

/// Top summary card showing:
/// - source image thumbnail
/// - overall processing state
/// - current message
/// - progress bar and completed count
class _ProcessingSummaryCard extends StatelessWidget {
  final double progressValue;
  final String title;
  final String subtitle;
  final String imagePath;
  final int completedCount;
  final int totalCount;
  final bool isFinished;
  final bool hasFailed;

  const _ProcessingSummaryCard({
    required this.progressValue,
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.completedCount,
    required this.totalCount,
    required this.isFinished,
    required this.hasFailed,
  });

  Color _progressColor() {
    if (hasFailed) return AppColors.accentSoft;
    if (isFinished) return AppColors.success;
    return AppColors.accent;
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = !isFinished && !hasFailed;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 82,
              height: 100,
              color: AppColors.card,
              child: Image.file(
                File(imagePath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return const Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: AppColors.textSecondary,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusPill(
                  label: hasFailed
                      ? 'Needs Retry'
                      : isFinished
                      ? 'Ready'
                      : 'Working',
                  icon: hasFailed
                      ? Icons.error_outline_rounded
                      : isFinished
                      ? Icons.check_circle_outline_rounded
                      : Icons.sync_rounded,
                  accentColor: hasFailed
                      ? AppColors.accentSoft
                      : isFinished
                      ? AppColors.success
                      : AppColors.warning,
                  animate: isRunning,
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: AppTextStyles.cardTitle.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySecondary.copyWith(
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                if (isRunning) ...[
                  const _RunningActivityIndicator(),
                  const SizedBox(height: 12),
                ],
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progressValue,
                    minHeight: 8,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(_progressColor()),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$completedCount of $totalCount steps complete',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Single stage card inside the pipeline list.
///
/// Shows:
/// - stage order
/// - functional icon
/// - title and explanation
/// - current status marker
class _ProcessingStageCard extends StatelessWidget {
  final ProcessingStageItem stage;
  final bool isActive;

  const _ProcessingStageCard({required this.stage, required this.isActive});

  Color _statusColor() {
    switch (stage.status) {
      case ProcessingStageStatus.pending:
        return AppColors.textMuted;
      case ProcessingStageStatus.active:
        return AppColors.warning;
      case ProcessingStageStatus.completed:
        return AppColors.success;
      case ProcessingStageStatus.failed:
        return AppColors.accentSoft;
    }
  }

  IconData _statusIcon() {
    switch (stage.status) {
      case ProcessingStageStatus.pending:
        return Icons.schedule_rounded;
      case ProcessingStageStatus.active:
        return Icons.autorenew_rounded;
      case ProcessingStageStatus.completed:
        return Icons.check_circle_rounded;
      case ProcessingStageStatus.failed:
        return Icons.error_rounded;
    }
  }

  String _statusLabel() {
    switch (stage.status) {
      case ProcessingStageStatus.pending:
        return 'Waiting';
      case ProcessingStageStatus.active:
        return 'Working';
      case ProcessingStageStatus.completed:
        return 'Done';
      case ProcessingStageStatus.failed:
        return 'Failed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive ? AppColors.card : const Color(0xFF101C31),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive
              ? statusColor.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.04),
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(stage.icon, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.title,
                  style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  stage.subtitle,
                  style: AppTextStyles.bodySecondary.copyWith(
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              isActive
                  ? _RotatingStatusIcon(
                      icon: _statusIcon(),
                      color: statusColor,
                      size: 20,
                    )
                  : Icon(_statusIcon(), size: 20, color: statusColor),
              const SizedBox(height: 6),
              Text(
                _statusLabel(),
                style: AppTextStyles.caption.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RunningActivityIndicator extends StatefulWidget {
  const _RunningActivityIndicator();

  @override
  State<_RunningActivityIndicator> createState() =>
      _RunningActivityIndicatorState();
}

class _RunningActivityIndicatorState extends State<_RunningActivityIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        return SizedBox(
          height: 18,
          child: Row(
            children: List.generate(4, (index) {
              final offset = (index / 4.0);
              final value = ((_pulse.value + offset) % 1.0);
              final height = 6.0 + (value * 12.0);

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == 3 ? 0 : 6),
                  child: Align(
                    alignment: Alignment.center,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: height,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(
                          alpha: 0.28 + (value * 0.42),
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _RotatingStatusIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _RotatingStatusIcon({
    required this.icon,
    required this.color,
    this.size = 24,
  });

  @override
  State<_RotatingStatusIcon> createState() => _RotatingStatusIconState();
}

class _RotatingStatusIconState extends State<_RotatingStatusIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(widget.icon, color: widget.color, size: widget.size),
    );
  }
}

/// Footer action area.
///
/// States:
/// - running: informational disabled label
/// - failed: retry button
/// - finished: continue button
class _ProcessingFooter extends StatelessWidget {
  final bool isFinished;
  final bool hasFailed;
  final VoidCallback onRetry;
  final VoidCallback onContinue;

  const _ProcessingFooter({
    required this.isFinished,
    required this.hasFailed,
    required this.onRetry,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: hasFailed
                ? _FooterActionButton(
                    icon: Icons.refresh_rounded,
                    label: 'Retry',
                    onTap: onRetry,
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.warning,
                  )
                : isFinished
                ? _FooterActionButton(
                    icon: Icons.arrow_forward_rounded,
                    label: 'Review Result',
                    onTap: onContinue,
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.textPrimary,
                  )
                : const _FooterInfoLabel(
                    icon: Icons.auto_awesome_rounded,
                    label: 'Keep this screen open while STALA reads the sheet.',
                  ),
          ),
        ],
      ),
    );
  }
}

/// Shared circular header button used for back navigation.
class _HeaderCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0x220B162B),
        border: Border.all(color: AppColors.border),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 19, color: AppColors.textSecondary),
      ),
    );
  }
}

/// Small pill that summarizes the overall processing state.
class _StatusPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accentColor;
  final bool animate;

  const _StatusPill({
    required this.label,
    required this.icon,
    required this.accentColor,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          animate
              ? _RotatingStatusIcon(icon: icon, color: accentColor, size: 15)
              : Icon(icon, size: 15, color: accentColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable tappable footer button for retry and continue actions.
class _FooterActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color backgroundColor;
  final Color foregroundColor;

  const _FooterActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          height: 54,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foregroundColor, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.button.copyWith(color: foregroundColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Passive footer label shown while the pipeline is still running.
class _FooterInfoLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FooterInfoLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 19),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySecondary.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
