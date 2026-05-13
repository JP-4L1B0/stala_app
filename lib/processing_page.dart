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
import 'services/chord_voicing_service.dart';
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

class _ProcessingPageState extends State<ProcessingPage> {
  static const MethodChannel _visionPipelineChannel = MethodChannel(
    'stala/python_bridge',
  );

  late List<ProcessingStageItem> _stages;
  int _activeStageIndex = -1;
  bool _isProcessingFinished = false;
  bool _hasProcessingFailed = false;
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

  final ChordVoicingService _chordVoicingService = ChordVoicingService();

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
        final classItems = _parseClassItems(response['detections']);

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
        );

        if (segmentationResult['status'] == 'success') {
          response['segmentedImagePath'] =
              segmentationResult['segmentedImagePath'];
          response['staffLineCount'] = segmentationResult['staffLineCount'];
          response['staffLines'] = segmentationResult['staffLines'];
          response['validatedStaffs'] = segmentationResult['validatedStaffs'];
          response['ledgerLines'] = segmentationResult['ledgerLines'];
          response['barLines'] = segmentationResult['barLines'];
          response['stems'] = segmentationResult['stems'];
          response['beams'] = segmentationResult['beams'];
          response['measures'] = segmentationResult['measures'];

          final refinedBarlines = _barlineRefinementService.refine(
            rawBarLines: (response['barLines'] as List?) ?? const [],
            rawMeasures: (response['measures'] as List?) ?? const [],
            rawValidatedStaffs:
                (response['validatedStaffs'] as List?) ?? const [],
            classItems: classItems,
          );

          response['barLines'] = refinedBarlines.barLines;
          response['measures'] = refinedBarlines.measures;

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
            'detections=${classItems.length} '
            'staffs=${(response['validatedStaffs'] as List?)?.length ?? 0} '
            'measures=${(response['measures'] as List?)?.length ?? 0}',
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

          print(
            'STALA_PIPELINE: groupedNotes=${groupedNotes.length} '
            'noteEvents=${groupedNotes.values.fold<int>(0, (sum, groups) => sum + groups.length)}',
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

          final grandStaffPairs = _grandStaffPairingService.pairStaffs(
            noteGroups: noteGroupViewItems,
            translateGroups: translateGroups,
          );

          print('STALA_PIPELINE: grandStaffPairs=${grandStaffPairs.length}');

          final grandStaffPairViewItems = grandStaffPairs.map((pair) {
            final trebleView = noteGroupViewItems.firstWhere(
              (item) => item.staffId == pair.trebleStaffId,
            );

            final bassView = pair.bassStaffId == null
                ? null
                : noteGroupViewItems.firstWhere(
                    (item) => item.staffId == pair.bassStaffId,
                  );

            return GrandStaffPairViewItem(
              id: pair.id,
              trebleStaffId: pair.trebleStaffId,
              bassStaffId: pair.bassStaffId,
              trebleGroups: trebleView.groups,
              bassGroups: bassView?.groups ?? const [],
            );
          }).toList();

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
              continuityMelody: result.continuityMelody
                  .map((n) => n.pitch)
                  .toList(),
            );
          }).toList();

          response['polyMonoResults'] = polyMonoViewItems;

          // Music interpretation service
          final musicInterpretation = _musicalInterpretationService.interpret(
            polyMonoResults: polyMonoResults,
          );

          print(
            'STALA_PIPELINE: musicInterpretation '
            'chord=${musicInterpretation.chordAwareLine.events.length} '
            'strict=${musicInterpretation.strictMelodyLine.events.length} '
            'continuity=${musicInterpretation.continuityMelodyLine.events.length}',
          );

          final musicInterpretationViewItems = [
            MusicInterpretationViewItem(
              title: musicInterpretation.chordAwareLine.title,
              labels: musicInterpretation.chordAwareLine.events
                  .map((event) => event.label)
                  .toList(),
            ),
            MusicInterpretationViewItem(
              title: musicInterpretation.strictMelodyLine.title,
              labels: musicInterpretation.strictMelodyLine.events
                  .map((event) => event.label)
                  .toList(),
            ),
            MusicInterpretationViewItem(
              title: musicInterpretation.continuityMelodyLine.title,
              labels: musicInterpretation.continuityMelodyLine.events
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

          // Chord voicing
          final chordVoicingResult = _chordVoicingService.voice(
            fretboardMapping: fretboardMapping,
          );

          print(
            'STALA_PIPELINE: chordVoicing '
            'lines=${chordVoicingResult.lines.length}',
          );

          final chordVoicingViewItems = chordVoicingResult.lines.map((line) {
            return ChordVoicingViewItem(
              title: line.title,
              events: line.events.map((event) {
                final positions = event.chosenPositions
                    .map((pos) {
                      return '${pos.pitch}: S${pos.stringNumber} F${pos.fret}';
                    })
                    .join(' + ');

                return '${event.label} → $positions (${event.voicingReason})';
              }).toList(),
            );
          }).toList();

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
            chordVoicingResult: chordVoicingResult,
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

            detectedSymbols: (response['detections'] as List? ?? const [])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(),

            segmentationData: (response['staffLines'] as List? ?? const [])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(),

            pitchMappingData: const [],
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

          /// Apply an auto-save to the session data
          SessionData finalSession = session;

          try {
            final autoSaveEnabled = await _appSettingsRepository
                .getAutoSaveEnabled();

            if (autoSaveEnabled) {
              final savedFile = await _saveExportService.saveStalaFile(
                session: session,
              );

              finalSession = session.copyWith(
                autoSavedFilePath: savedFile.path,
                autoSavedAt: DateTime.now(),
                autoSaveFailed: false,
              );
            }
          } catch (error) {
            finalSession = session.copyWith(autoSaveFailed: true);

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
    }
  }

  /// Resets the page state and runs the mock pipeline again.
  Future<void> _retryProcessing() async {
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
    final classItems = _parseClassItems(result['detections']);
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
      final shouldRefreshHome = await Navigator.push<bool>(
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
          ),
        ),
      );

      if (!mounted) return;

      if (shouldRefreshHome == true) {
        Navigator.pop(context, true);
      }
    } else {
      final shouldRefreshHome = await Navigator.push<bool>(
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
                        title: 'Processing Progress',
                        description:
                            'This area shows the selected sheet, current status, and overall processing progress.',
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
                          title: 'Processing Steps',
                          description:
                              'STALA moves through cleanup, detection, staff analysis, translation, and tablature generation.',
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
                title: 'Result Navigation',
                description:
                    'When processing completes, use this area to review the generated result or retry if needed.',
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

    final confirmedSymbols = groups
        .expand((group) => group.symbols)
        .where((symbol) => symbol.assignmentStatus == 'ledgerConfirmed')
        .toList();

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

      final hasMatchingConfirmedNote = confirmedSymbols.any((symbol) {
        final yClose = (symbol.centerY - y).abs() <= 24.0;
        final xClose =
            symbol.centerX >= x1 - 36.0 && symbol.centerX <= x2 + 36.0;
        return yClose && xClose;
      });

      if (!hasMatchingConfirmedNote) continue;

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
            title: 'Processing Help',
            description:
                'Open this anytime to read what the processing screen is doing or replay the tour.',
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
