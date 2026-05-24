import 'dart:async';
import 'package:flutter/material.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_text_styles.dart';
import 'services/generation_service.dart';
import 'services/save_export_service.dart';
import 'services/audio_playback_service.dart';
import 'data/app_settings_repository.dart';
import 'data/debug_settings_repository.dart';
import 'data/recent_items_repository.dart';
import 'dummy_page.dart';
import 'models/session_data.dart';
import 'models/saved_item_data.dart';
import 'models/translation_group_models.dart';
import 'processing_page.dart';
import 'services/processing_session_navigation.dart';
import 'services/tutorial_service.dart';

class ResultPage extends StatefulWidget {
  final SessionData session;
  final List<GeneratedTabResult> generatedTabs;
  final SavedItemData? sourceItem;

  const ResultPage({
    super.key,
    required this.session,
    required this.generatedTabs,
    this.sourceItem,
  });

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  final AudioPlaybackService _audioService = AudioPlaybackService();
  final AppSettingsRepository _appSettingsRepository =
      const AppSettingsRepository();
  late final TextEditingController _titleController;
  late SessionData _session;
  late String _persistedTitle;
  SavedItemData? _sourceItem;
  final GlobalKey _resultHelpTourKey = GlobalKey();
  final GlobalKey _resultSaveTourKey = GlobalKey();
  final GlobalKey _resultModeTourKey = GlobalKey();
  final GlobalKey _resultTabTourKey = GlobalKey();
  final GlobalKey _resultPlaybackTourKey = GlobalKey();
  final GlobalKey _resultFretboardTourKey = GlobalKey();

  bool _isSustainEnabled = false;
  double _playbackSpeed = 1.0;
  List<int> _activeMidiNotes = [];
  final Map<int, int> _noteSustainGeneration = {};
  final List<Timer> _sustainTimers = [];

  static const List<double> _playbackSpeedOptions = [
    0.50,
    0.75,
    1.00,
    1.25,
    1.50,
    1.75,
    2.00,
  ];

  static const Duration _sustainTailDuration = Duration(seconds: 4);

  int _toMidiNote({required int stringNumber, required int fret}) {
    const openStringMidi = {
      6: 40, // E2
      5: 45, // A2
      4: 50, // D3
      3: 55, // G3
      2: 59, // B3
      1: 64, // E4
    };

    final openNote = openStringMidi[stringNumber];
    if (openNote == null) return 64;

    return openNote + fret;
  }

  final ScrollController _tabScrollController = ScrollController();

  int _selectedModeIndex = 0;
  int _currentColumnIndex = 0;
  bool _isPlaying = false;
  Timer? _timer;
  Timer? _autoSaveStatusTimer;
  bool _isSavingTitle = false;
  bool _isExporting = false;
  bool _showAutoSaveStatus = false;
  bool _debugPageEnabled = false;

  GeneratedTabResult get _currentTab =>
      widget.generatedTabs[_selectedModeIndex];

  GeneratedTabColumn get _currentColumn =>
      _currentTab.columns[_currentColumnIndex];

  @override
  void initState() {
    super.initState();
    _session = widget.session.copyWith(
      projectName: _initialProjectName(widget.session),
    );
    _persistedTitle = widget.session.projectName.trim();
    _sourceItem = widget.sourceItem;
    _titleController = TextEditingController(text: _session.projectName);

    final hasAutoSaveStatus =
        _session.autoSavedAt != null || _session.autoSaveFailed;

    if (hasAutoSaveStatus) {
      _showAutoSaveStatus = true;
      _autoSaveStatusTimer = Timer(const Duration(seconds: 4), () {
        if (!mounted) return;

        setState(() {
          _showAutoSaveStatus = false;
        });
      });
    }

    TutorialService.autoStartTour(
      context,
      pageKey: TutorialService.resultPageKey,
      keys: _resultTourKeys,
      page: TutorialPage.resultPage,
    );

    _loadDebugSetting();
    ProcessingSessionNavigation.enterResult(_session.id);
  }

  Future<void> _loadDebugSetting() async {
    final enabled = await const DebugSettingsRepository().isDebugPageEnabled();
    if (!mounted) return;
    setState(() {
      _debugPageEnabled = enabled;
    });
  }

  List<GlobalKey> get _resultTourKeys => [
    _resultTabTourKey,
    _resultPlaybackTourKey,
    _resultFretboardTourKey,
    _resultModeTourKey,
    _resultSaveTourKey,
    _resultHelpTourKey,
  ];

  @override
  void dispose() {
    _timer?.cancel();
    _cancelSustainTimers();
    _autoSaveStatusTimer?.cancel();
    _audioService.stopAll();
    _tabScrollController.dispose();
    _titleController.dispose();
    ProcessingSessionNavigation.exitResult(_session.id);
    super.dispose();
  }

  Future<void> _changeMode(int index) async {
    _timer?.cancel();
    await _stopActiveAudio();

    if (!mounted) return;

    setState(() {
      _selectedModeIndex = index;
      _currentColumnIndex = 0;
      _isPlaying = false;
    });

    _scrollToCurrent();
  }

  Future<void> _jumpToColumn(int index) async {
    if (index < 0 || index >= _currentTab.columns.length) return;

    _timer?.cancel();
    await _stopActiveAudio();

    if (!mounted) return;

    setState(() {
      _currentColumnIndex = index;
      _isPlaying = false;
    });

    _scrollToCurrent();

    // Play tapped note/chord once.
    await _playCurrentColumnAudio();

    await Future.delayed(_previewDurationForColumn(_currentColumn));

    await _stopActiveAudio();
  }

  void _previous() {
    _jumpToColumn(_currentColumnIndex - 1);
  }

  void _next() {
    _jumpToColumn(_currentColumnIndex + 1);
  }

  Future<void> _startProgression() async {
    if (_currentTab.columns.isEmpty) return;

    _timer?.cancel();
    await _stopActiveAudio();

    if (!mounted) return;

    setState(() {
      _currentColumnIndex = 0;
      _isPlaying = false;
    });

    _scrollToCurrent();
  }

  Future<void> _endProgression() async {
    if (_currentTab.columns.isEmpty) return;

    _timer?.cancel();
    await _stopActiveAudio();

    if (!mounted) return;

    setState(() {
      _currentColumnIndex = _currentTab.columns.length - 1;
      _isPlaying = false;
    });

    _scrollToCurrent();
  }

  Future<void> _togglePlay() async {
    if (_currentTab.columns.isEmpty) return;

    if (_isPlaying) {
      _timer?.cancel();
      await _stopActiveAudio();

      if (!mounted) return;

      setState(() {
        _isPlaying = false;
      });

      return;
    }

    final shouldRestart = _currentColumnIndex >= _currentTab.columns.length - 1;

    setState(() {
      if (shouldRestart) {
        _currentColumnIndex = 0;
      }
      _isPlaying = true;
    });

    if (shouldRestart) {
      _scrollToCurrent();
    }

    await _playCurrentColumnAudio();
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();

    final duration = _durationForColumn(_currentColumn);

    _timer = Timer(duration, () async {
      if (!mounted || !_isPlaying) return;

      if (!_isSustainEnabled) {
        await _stopActiveAudio();
      }

      if (_currentColumnIndex >= _currentTab.columns.length - 1) {
        _timer?.cancel();
        await _stopActiveAudio();

        if (!mounted) return;

        setState(() {
          _isPlaying = false;
        });

        return;
      }

      setState(() => _currentColumnIndex++);
      _scrollToCurrent();

      await _playCurrentColumnAudio();

      if (!mounted || !_isPlaying) return;
      _scheduleNext();
    });
  }

  Duration _durationForColumn(GeneratedTabColumn column) {
    final milliseconds = ((column.durationSeconds * 1000) / _playbackSpeed)
        .round();
    return Duration(milliseconds: milliseconds.clamp(120, 6000));
  }

  Duration _previewDurationForColumn(GeneratedTabColumn column) {
    final milliseconds = _durationForColumn(
      column,
    ).inMilliseconds.clamp(160, 900);
    return Duration(milliseconds: milliseconds);
  }

  void _scrollToCurrent() {
    if (!_tabScrollController.hasClients) return;
    if (_currentTab.columns.isEmpty) return;

    final viewportWidth = _tabScrollController.position.viewportDimension;
    final column = _currentTab.columns[_currentColumnIndex];

    final target = column.x - (viewportWidth / 2) + (column.width / 2);

    final safeTarget = target.clamp(
      0.0,
      _tabScrollController.position.maxScrollExtent,
    );

    _tabScrollController.animateTo(
      safeTarget,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _exitResultPage() async {
    _timer?.cancel();
    await _stopActiveAudio();
    final didCommitTitle = await _commitTitleChange();
    if (!didCommitTitle) return;
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _openDebugPage() async {
    final session = _session;
    final snapshot = session.segmentationData;
    final debugSnapshot = session.debugSnapshot;
    final generatedTabViews = _parseGeneratedTabViews(
      debugSnapshot['generatedTabs'],
    );

    ProcessingSessionNavigation.logTransition(
      session.id,
      debugReused: true,
      resultReused: true,
    );
    await Navigator.pushReplacement<Object?, Object?>(
      context,
      MaterialPageRoute(
        builder: (debugContext) => DummyPage(
          croppedImagePath:
              session.croppedImagePath ?? session.originalImagePath,
          detectedImagePath:
              session.detectionImagePath ??
              session.preprocessedImagePath ??
              session.croppedImagePath ??
              session.originalImagePath,
          segmentedImagePath: session.segmentationImagePath,
          detections: _parseDetectionPoints(session.detectedSymbols),
          classItems: _parseClassItems(session.detectedSymbols),
          staffOverlays: _snapshotItems(snapshot, 'validatedStaff'),
          barLineOverlays: _snapshotItems(snapshot, 'barLine'),
          stemOverlays: _snapshotItems(snapshot, 'stem'),
          beamOverlays: _snapshotItems(snapshot, 'beam'),
          semanticRegions: _snapshotItems(snapshot, 'semanticRegion'),
          clefSafetyRegions: _snapshotItems(snapshot, 'clefSafetyRegion'),
          rejectedNoteheads: session.pitchMappingData,
          translateGroups: _parseTranslateGroups(
            debugSnapshot['translateGroups'],
          ),
          noteGroups: _parseNoteGroups(debugSnapshot['noteGroups']),
          rhythmEvents: _parseRhythmEvents(debugSnapshot['rhythmEvents']),
          grandStaffPairs: _parseGrandStaffPairs(
            debugSnapshot['grandStaffPairs'],
          ),
          polyMonoResults: _parsePolyMonoResults(
            debugSnapshot['polyMonoResults'],
          ),
          musicInterpretations: _parseMusicInterpretations(
            debugSnapshot['musicInterpretations'],
          ),
          fretboardMappings: _parseFretboardMappings(
            debugSnapshot['fretboardMappings'],
          ),
          eventManagerResults: _parseEventManagerResults(
            debugSnapshot['eventManagerResults'],
          ),
          chordVoicingResults: _parseChordVoicingResults(
            debugSnapshot['chordVoicingResults'],
          ),
          session: session,
          onRetry: () {
            final sourcePath = session.originalImagePath;
            final croppedPath =
                session.croppedImagePath ?? session.originalImagePath;
            if (sourcePath.trim().isEmpty || croppedPath.trim().isEmpty) {
              return;
            }
            ProcessingSessionNavigation.logTransition(
              session.id,
              debugReused: true,
              resultReused: true,
            );
            Navigator.of(debugContext).pushReplacement(
              MaterialPageRoute(
                builder: (_) => ProcessingPage(
                  sourceImagePath: sourcePath,
                  croppedImagePath: croppedPath,
                ),
              ),
            );
          },
          replaceWithResultPage: true,
          generatedTabResults: widget.generatedTabs,
          generatedTabs: generatedTabViews.isNotEmpty
              ? generatedTabViews
              : widget.generatedTabs.map((tab) {
                  final first = tab.columns.isNotEmpty
                      ? tab.columns.first
                      : null;
                  return GeneratedTabViewItem(
                    mode: tab.mode.name,
                    columns: tab.columns.length,
                    fretboardFrames: tab.fretboardFrames.length,
                    exportPages: tab.exportPages.length,
                    firstEventSummary: first == null
                        ? 'No events'
                        : '${first.label} -> ${first.numbers.length} note(s)',
                  );
                }).toList(),
          pipelineReport: Map<String, dynamic>.from(
            debugSnapshot['pipelineReport'] as Map? ?? const {},
          ),
          ledgerLines: _snapshotItems(snapshot, 'ledgerLine').map((item) {
            return LedgerLineViewItem(
              staffId: item['staffId']?.toString() ?? '',
              x1: _toDouble(item['x1']) ?? 0.0,
              x2: _toDouble(item['x2']) ?? 0.0,
              y: _toDouble(item['y']) ?? 0.0,
            );
          }).toList(),
        ),
      ),
    );
  }

  String _initialProjectName(SessionData session) {
    final rawName = session.projectName.trim();
    if (rawName.isNotEmpty && rawName != 'Untitled' && rawName != 'Sample 1') {
      return rawName;
    }

    return _formatDefaultFileName(session.processingTimestamp);
  }

  String _formatDefaultFileName(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.month)}/${two(value.day)}/${value.year}_${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  List<Map<String, dynamic>> _snapshotItems(
    List<Map<String, dynamic>> snapshot,
    String kind,
  ) {
    return snapshot.where((item) => item['kind'] == kind).map((item) {
      final copy = Map<String, dynamic>.from(item);
      copy.remove('kind');
      return copy;
    }).toList();
  }

  List<DetectionPoint> _parseDetectionPoints(List<Map<String, dynamic>> raw) {
    return _parseClassItems(raw).map((item) {
      return DetectionPoint(
        className: item.className,
        centerX: item.x,
        centerY: item.y,
        score: item.score,
      );
    }).toList();
  }

  List<SymbolClassItem> _parseClassItems(List<Map<String, dynamic>> raw) {
    final items = <SymbolClassItem>[];

    for (final map in raw) {
      final className =
          map['className']?.toString() ??
          map['labelName']?.toString() ??
          map['label']?.toString() ??
          'unknown';
      final score = _toDouble(map['score'] ?? map['confidence']);
      List<double>? bbox;
      double? centerX = _toDouble(map['centerX'] ?? map['x']);
      double? centerY = _toDouble(map['centerY'] ?? map['y']);

      if (map['bbox'] is List && (map['bbox'] as List).length >= 4) {
        final rawBbox = List.from(map['bbox']);
        final x1 = _toDouble(rawBbox[0]);
        final y1 = _toDouble(rawBbox[1]);
        final x2 = _toDouble(rawBbox[2]);
        final y2 = _toDouble(rawBbox[3]);
        if (x1 != null && y1 != null && x2 != null && y2 != null) {
          bbox = [x1, y1, x2, y2];
          centerX ??= (x1 + x2) / 2.0;
          centerY ??= (y1 + y2) / 2.0;
        }
      }

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

    return items;
  }

  List<StaffTranslateGroup> _parseTranslateGroups(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) {
      final map = Map<String, dynamic>.from(item);
      final summary = Map<String, dynamic>.from(
        map['summary'] as Map? ?? const {},
      );
      return StaffTranslateGroup(
        staffId: map['staffId']?.toString() ?? '',
        summary: StaffSummary(
          lineCount: _toInt(summary['lineCount']) ?? 0,
          symbolCount: _toInt(summary['symbolCount']) ?? 0,
          clefStatusLabel: summary['clefStatusLabel']?.toString() ?? '',
        ),
        segmentMap: _mapList(map['segmentMap']).map((segment) {
          return SegmentMapItem(
            id: segment['id']?.toString() ?? '',
            type: segment['type']?.toString() ?? 'line',
            centerY: _toDouble(segment['centerY']) ?? 0.0,
            startY: _toDouble(segment['startY']),
            endY: _toDouble(segment['endY']),
            defaultKeyLabel: segment['defaultKeyLabel']?.toString() ?? '',
          );
        }).toList(),
        symbols: _mapList(map['symbols']).map((symbol) {
          return TranslatedSymbolViewItem(
            className: symbol['className']?.toString() ?? 'unknown',
            centerX: _toDouble(symbol['centerX']) ?? 0.0,
            centerY: _toDouble(symbol['centerY']) ?? 0.0,
            score: _toDouble(symbol['score']),
            bbox: _doubleList(symbol['bbox']),
            staffId: symbol['staffId']?.toString() ?? '',
            staffRole: symbol['staffRole']?.toString() ?? 'unknown',
            locationId: symbol['locationId']?.toString() ?? '',
            locationType: symbol['locationType']?.toString() ?? '',
            assignmentStatus: symbol['assignmentStatus']?.toString() ?? '',
            measureId: symbol['measureId']?.toString(),
            measureIndex: _toInt(symbol['measureIndex']),
            defaultKeyLabel: symbol['defaultKeyLabel']?.toString(),
            accidentalState: symbol['accidentalState']?.toString(),
            symbolState: SymbolState.fromValue(symbol['symbolState']),
            inferredReason: symbol['inferredReason']?.toString(),
          );
        }).toList(),
      );
    }).toList();
  }

  List<NoteGroupViewItem> _parseNoteGroups(dynamic raw) {
    return _mapList(raw).map((item) {
      return NoteGroupViewItem(
        staffId: item['staffId']?.toString() ?? '',
        groups: _stringGroups(item['groups']),
      );
    }).toList();
  }

  List<RhythmEventViewItem> _parseRhythmEvents(dynamic raw) {
    return _mapList(raw).map((item) {
      return RhythmEventViewItem(
        staffId: item['staffId']?.toString() ?? '',
        measureIndex: _toInt(item['measureIndex']),
        label: item['label']?.toString() ?? '',
        durationBeats: _toDouble(item['durationBeats']) ?? 0.0,
        timingSource: item['timingSource']?.toString() ?? '',
        confidence: _toDouble(item['confidence']) ?? 0.0,
        hasStem: item['hasStem'] == true,
        hasBeam: item['hasBeam'] == true,
      );
    }).toList();
  }

  List<GrandStaffPairViewItem> _parseGrandStaffPairs(dynamic raw) {
    return _mapList(raw).map((item) {
      return GrandStaffPairViewItem(
        id: item['id']?.toString() ?? '',
        trebleStaffId: item['trebleStaffId']?.toString() ?? '',
        bassStaffId: item['bassStaffId']?.toString(),
        trebleGroups: _stringGroups(item['trebleGroups']),
        bassGroups: _stringGroups(item['bassGroups']),
      );
    }).toList();
  }

  List<PolyMonoViewItem> _parsePolyMonoResults(dynamic raw) {
    return _mapList(raw).map((item) {
      return PolyMonoViewItem(
        grandStaffId: item['grandStaffId']?.toString() ?? '',
        harmonicStacks: _stringGroups(item['harmonicStacks']),
        chordAwareStacks: _stringList(item['chordAwareStacks']),
        strictMelody: _stringList(item['strictMelody']),
      );
    }).toList();
  }

  List<MusicInterpretationViewItem> _parseMusicInterpretations(dynamic raw) {
    return _mapList(raw).map((item) {
      return MusicInterpretationViewItem(
        title: item['title']?.toString() ?? '',
        labels: _stringList(item['labels']),
      );
    }).toList();
  }

  List<FretboardMappingViewItem> _parseFretboardMappings(dynamic raw) {
    return _mapList(raw).map((item) {
      return FretboardMappingViewItem(
        title: item['title']?.toString() ?? '',
        eventSummaries: _stringList(item['eventSummaries']),
      );
    }).toList();
  }

  List<EventManagerViewItem> _parseEventManagerResults(dynamic raw) {
    return _mapList(raw).map((item) {
      return EventManagerViewItem(
        title: item['title']?.toString() ?? '',
        totalCost: item['totalCost']?.toString() ?? '',
        events: _stringList(item['events']),
      );
    }).toList();
  }

  List<ChordVoicingViewItem> _parseChordVoicingResults(dynamic raw) {
    return _mapList(raw).map((item) {
      return ChordVoicingViewItem(
        title: item['title']?.toString() ?? '',
        events: _stringList(item['events']),
      );
    }).toList();
  }

  List<GeneratedTabViewItem> _parseGeneratedTabViews(dynamic raw) {
    return _mapList(raw).map((item) {
      return GeneratedTabViewItem(
        mode: item['mode']?.toString() ?? '',
        columns: _toInt(item['columns']) ?? 0,
        fretboardFrames: _toInt(item['fretboardFrames']) ?? 0,
        exportPages: _toInt(item['exportPages']) ?? 0,
        firstEventSummary: item['firstEventSummary']?.toString() ?? 'No events',
      );
    }).toList();
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<List<String>> _stringGroups(dynamic value) {
    if (value is! List) return const [];
    return value.map((group) => _stringList(group)).toList();
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value.map((item) => item.toString()).toList();
  }

  List<double>? _doubleList(dynamic value) {
    if (value is! List) return null;
    final result = value.map(_toDouble).whereType<double>().toList();
    return result.isEmpty ? null : result;
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  String get _currentExportTitle {
    final title = _titleController.text.trim();
    return title.isEmpty ? _session.projectName : title;
  }

  Widget _buildTitleField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _titleController,
        style: AppTextStyles.body,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _commitTitleChange(),
        decoration: InputDecoration(
          filled: true,
          fillColor: AppColors.card,
          labelText: 'Filename',
          labelStyle: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
          ),
          prefixIcon: const Icon(
            Icons.drive_file_rename_outline_rounded,
            color: AppColors.accent,
          ),
          suffixIcon: IconButton(
            tooltip: 'Apply filename',
            onPressed: _isSavingTitle ? null : _commitTitleChange,
            icon: _isSavingTitle
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            color: AppColors.accent,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.accent),
          ),
        ),
      ),
    );
  }

  Future<bool> _commitTitleChange() async {
    final nextTitle = _currentExportTitle.trim();
    if (nextTitle.isEmpty || nextTitle == _persistedTitle) return true;

    setState(() {
      _isSavingTitle = true;
      _session = _session.copyWith(projectName: nextTitle);
    });

    try {
      if (_sourceItem != null) {
        _sourceItem = await RecentItemsRepository.updateItemTitle(
          _sourceItem!,
          nextTitle,
        );
        final updatedPath = _sourceItem?.filePath;
        if (updatedPath != null && updatedPath.trim().isNotEmpty) {
          _session = _session.copyWith(autoSavedFilePath: updatedPath);
        }
      } else if (_session.autoSavedFilePath != null) {
        final updatedPath = await RecentItemsRepository.updateFileTitle(
          filePath: _session.autoSavedFilePath!,
          newTitle: nextTitle,
        );
        if (updatedPath != null) {
          _session = _session.copyWith(autoSavedFilePath: updatedPath);
        }
      }

      _persistedTitle = nextTitle;
      return true;
    } on DuplicateFileNameException catch (error) {
      if (!mounted) return false;

      setState(() {
        _session = _session.copyWith(projectName: _persistedTitle);
        _titleController.text = _persistedTitle;
        _titleController.selection = TextSelection.collapsed(
          offset: _titleController.text.length,
        );
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      return false;
    } catch (error) {
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update filename: $error')),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isSavingTitle = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.generatedTabs.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Text(
            'No generated tablature available.',
            style: AppTextStyles.bodySecondary,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: AppColors.textPrimary,
          onPressed: _exitResultPage,
        ),
        title: Text(
          'Result',
          style: AppTextStyles.sectionTitle.copyWith(fontSize: 20),
        ),
        actions: [
          if (_debugPageEnabled)
            IconButton(
              tooltip: 'Open debug page',
              icon: const Icon(Icons.code_rounded),
              color: AppColors.textPrimary,
              onPressed: _openDebugPage,
            ),
          TutorialService.showcase(
            key: _resultHelpTourKey,
            title: 'Need Result Help?',
            description:
                'Tap this if you want a reminder about this page or want to replay the tour.',
            targetShapeBorder: const CircleBorder(),
            child: IconButton(
              tooltip: 'Result help',
              icon: const Icon(Icons.help_outline_rounded),
              color: AppColors.textPrimary,
              onPressed: () {
                TutorialService.showHowToUse(
                  context,
                  page: TutorialPage.resultPage,
                  onStartTour: () =>
                      TutorialService.showResultGuide(context, _resultTourKeys),
                );
              },
            ),
          ),
          TutorialService.showcase(
            key: _resultSaveTourKey,
            title: 'Save or Export',
            description:
                'Use these buttons when you are ready to save the tablature as an image or PDF.',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Save as PNG',
                  icon: const Icon(Icons.image_outlined),
                  color: AppColors.textPrimary,
                  onPressed: _isExporting ? null : _saveCurrentTabAsPng,
                ),
                IconButton(
                  tooltip: 'Save as PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  color: AppColors.textPrimary,
                  onPressed: _isExporting ? null : _saveCurrentTabAsPdf,
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildTitleField(),
            TutorialService.showcase(
              key: _resultModeTourKey,
              title: 'Choose a Tab Style',
              description:
                  'If more than one version is available, switch between them here.',
              child: _buildTopDropdown(),
            ),
            _buildAutoSaveStatus(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TutorialService.showcase(
                    key: _resultTabTourKey,
                    title: 'Your Generated Tab',
                    description:
                        'This is the tab STALA created. Tap a fret number to focus on that note.',
                    child: _ResultCard(
                      title: 'Tablature',
                      subtitle: 'Tap a fret number to jump to that event.',
                      child: _TablatureViewer(
                        tab: _currentTab,
                        currentColumnIndex: _currentColumnIndex,
                        scrollController: _tabScrollController,
                        onColumnTap: _jumpToColumn,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TutorialService.showcase(
                    key: _resultPlaybackTourKey,
                    title: 'Listen and Check',
                    description:
                        'Use these controls to play the result, pause it, or step through notes.',
                    child: _buildControlCard(),
                  ),
                  const SizedBox(height: 14),
                  TutorialService.showcase(
                    key: _resultFretboardTourKey,
                    title: 'Fretboard Map',
                    description:
                        'This shows where the selected note is played on the guitar neck.',
                    child: _ResultCard(
                      title: 'Fretboard Map',
                      subtitle: 'Highlighted positions update per event.',
                      child: _FretboardViewer(
                        column: _currentColumn,
                        onPositionTap: _showFretDetail,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopDropdown() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _AnchoredOptionButton<int>(
              value: _selectedModeIndex,
              options: List.generate(widget.generatedTabs.length, (index) {
                return _OptionItem<int>(
                  value: index,
                  label: _formatMode(widget.generatedTabs[index].mode.name),
                );
              }),
              onChanged: (value) {
                if (value != null) {
                  _changeMode(value);
                }
              },
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.textPrimary,
              minHeight: 46,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoSaveStatus() {
    if (!_showAutoSaveStatus) return const SizedBox.shrink();

    final session = _session;

    if (session.autoSavedAt == null && !session.autoSaveFailed) {
      return const SizedBox.shrink();
    }

    final isFailed = session.autoSaveFailed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isFailed ? AppColors.warning : AppColors.success,
          ),
        ),
        child: Text(
          isFailed
              ? 'Auto-save failed. Manual export is still available.'
              : 'Auto-saved successfully.',
          style: AppTextStyles.caption.copyWith(
            color: isFailed ? AppColors.warning : AppColors.success,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildControlCard() {
    final detail = _currentColumn.eventDetail;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: _currentTab.columns.isEmpty
                ? 0
                : (_currentColumnIndex + 1) / _currentTab.columns.length,
            minHeight: 8,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.success),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RoundControlButton(
                icon: Icons.first_page_rounded,
                onTap: _currentColumnIndex == 0 ? null : _startProgression,
              ),
              const SizedBox(width: 10),
              _RoundControlButton(
                icon: Icons.skip_previous_rounded,
                onTap: _currentColumnIndex == 0 ? null : _previous,
              ),
              const SizedBox(width: 10),
              _RoundControlButton(
                icon: _isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                emphasized: true,
                onTap: _togglePlay,
              ),
              const SizedBox(width: 10),
              _RoundControlButton(
                icon: Icons.skip_next_rounded,
                onTap: _currentColumnIndex >= _currentTab.columns.length - 1
                    ? null
                    : _next,
              ),
              const SizedBox(width: 10),
              _RoundControlButton(
                icon: Icons.last_page_rounded,
                onTap: _currentColumnIndex >= _currentTab.columns.length - 1
                    ? null
                    : _endProgression,
              ),
            ],
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _EventDetailPanel(
                    eventLabel:
                        'Event ${_currentColumnIndex + 1} of ${_currentTab.columns.length}',
                    title: detail.displayTitle,
                    subtitle: detail.displaySubtitle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PlaybackSettingsPanel(
                    speed: _playbackSpeed,
                    speedOptions: _playbackSpeedOptions,
                    sustainEnabled: _isSustainEnabled,
                    onSpeedChanged: (value) {
                      if (value == null) return;

                      setState(() {
                        _playbackSpeed = value;
                      });

                      if (_isPlaying) {
                        _scheduleNext();
                      }
                    },
                    onSustainChanged: (value) {
                      setState(() {
                        _isSustainEnabled = value;
                      });

                      if (!value && _isPlaying) {
                        _stopActiveAudio().then((_) {
                          if (!mounted || !_isPlaying) return;
                          _playCurrentColumnAudio();
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          /// Commented out, but helps for sound debugging
          /*
          ElevatedButton(
            onPressed: () async {
              print('Manual test note');
              await _audioService.playNote(64); // E4
            },
            child: const Text('Test Sound'),
          ),
          ElevatedButton(
            onPressed: () => _audioService.scanPrograms(),
            child: const Text('Scan Instruments'),
          ),
          */
        ],
      ),
    );
  }

  void _showFretDetail(GeneratedTabNumber number) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fretboard Position', style: AppTextStyles.sectionTitle),
                const SizedBox(height: 10),
                Text('Pitch: ${number.pitch}', style: AppTextStyles.body),
                Text(
                  'String ${number.stringNumber}, Fret ${number.fret}',
                  style: AppTextStyles.bodySecondary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveCurrentTabAsPng() async {
    if (_isExporting) return;

    setState(() {
      _isExporting = true;
    });

    try {
      final didCommitTitle = await _commitTitleChange();
      if (!didCommitTitle) return;
      final orientation = await _getExportOrientation();

      await const SaveExportService().saveTabPngPages(
        title: _currentExportTitle,
        tab: _currentTab,
        orientation: orientation,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved PNG page(s) successfully.')),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save PNG: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _saveCurrentTabAsPdf() async {
    if (_isExporting) return;

    setState(() {
      _isExporting = true;
    });

    try {
      final didCommitTitle = await _commitTitleChange();
      if (!didCommitTitle) return;
      final orientation = await _getExportOrientation();

      await const SaveExportService().saveTabPdf(
        title: _currentExportTitle,
        tab: _currentTab,
        orientation: orientation,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved PDF successfully.')));
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save PDF: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<TablatureExportOrientation> _getExportOrientation() async {
    final value = await _appSettingsRepository.getTablatureExportOrientation();
    return value == 'landscape'
        ? TablatureExportOrientation.landscape
        : TablatureExportOrientation.portrait;
  }

  String _formatMode(String raw) {
    switch (raw) {
      case 'trebleOnly':
        return 'Treble Only';
      case 'grandStaff':
        return 'Grand Staff';
      default:
        return raw;
    }
  }

  /// This is the audio helper block
  Future<void> _playCurrentColumnAudio() async {
    final notes = _currentColumn.numbers.map((number) {
      final midi = _toMidiNote(
        stringNumber: number.stringNumber,
        fret: number.fret,
      );

      return midi;
    }).toList();

    if (notes.isEmpty) {
      return;
    }

    _activeMidiNotes = _isSustainEnabled
        ? {..._activeMidiNotes, ...notes}.toList()
        : notes;

    await _audioService.playChord(notes);

    if (_isSustainEnabled) {
      _scheduleSustainStop(notes, _durationForColumn(_currentColumn));
    }
  }

  Future<void> _stopActiveAudio() async {
    _cancelSustainTimers();
    final notes = List<int>.from(_activeMidiNotes);
    _activeMidiNotes = [];
    _noteSustainGeneration.clear();

    if (notes.isNotEmpty) {
      await _audioService.stopChord(notes);
    }

    await _audioService.stopAll();
  }

  void _scheduleSustainStop(List<int> notes, Duration eventDuration) {
    final delay = eventDuration + _sustainTailDuration;

    for (final note in notes) {
      final generation = (_noteSustainGeneration[note] ?? 0) + 1;
      _noteSustainGeneration[note] = generation;

      final timer = Timer(delay, () async {
        if (_noteSustainGeneration[note] != generation) return;

        _noteSustainGeneration.remove(note);
        _activeMidiNotes.remove(note);
        await _audioService.stopNote(note);
      });

      _sustainTimers.add(timer);
    }
  }

  void _cancelSustainTimers() {
    for (final timer in _sustainTimers) {
      timer.cancel();
    }
    _sustainTimers.clear();
  }
}

class _EventDetailPanel extends StatelessWidget {
  final String eventLabel;
  final String title;
  final String subtitle;

  const _EventDetailPanel({
    required this.eventLabel,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 128),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eventLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySecondary.copyWith(fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _OptionItem<T> {
  final T value;
  final String label;

  const _OptionItem({required this.value, required this.label});
}

class _AnchoredOptionButton<T> extends StatelessWidget {
  final T value;
  final List<_OptionItem<T>> options;
  final ValueChanged<T?> onChanged;
  final Color backgroundColor;
  final Color foregroundColor;
  final double minHeight;
  final bool dense;

  const _AnchoredOptionButton({
    required this.value,
    required this.options,
    required this.onChanged,
    this.backgroundColor = AppColors.card,
    this.foregroundColor = AppColors.textPrimary,
    this.minHeight = 42,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }

    final selected = options.firstWhere(
      (option) => option.value == value,
      orElse: () => options.first,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(dense ? 10 : 14),
        onTap: options.isEmpty ? null : () => _showMenu(context),
        child: Ink(
          height: minHeight,
          padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(dense ? 10 : 14),
            border: Border.all(
              color: backgroundColor == AppColors.accent
                  ? AppColors.accent
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    color: foregroundColor,
                    fontSize: dense ? 13 : 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: foregroundColor,
                size: dense ? 19 : 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;

    if (box == null || overlay == null) return;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );

    final selectedValue = await showMenu<T>(
      context: context,
      color: AppColors.card,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        bottomRight.dy + 4,
        overlay.size.width - bottomRight.dx,
        overlay.size.height - bottomRight.dy,
      ),
      constraints: BoxConstraints(minWidth: box.size.width),
      items: options.map((option) {
        final isSelected = option.value == value;

        return PopupMenuItem<T>(
          value: option.value,
          padding: EdgeInsets.zero,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            color: isSelected
                ? AppColors.accent.withValues(alpha: 0.18)
                : Colors.transparent,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option.label,
                    style: AppTextStyles.body.copyWith(
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.textPrimary,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: AppColors.accent,
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );

    if (selectedValue != null && selectedValue != value) {
      onChanged(selectedValue);
    }
  }
}

class _PlaybackSettingsPanel extends StatelessWidget {
  final double speed;
  final List<double> speedOptions;
  final bool sustainEnabled;
  final ValueChanged<double?> onSpeedChanged;
  final ValueChanged<bool> onSustainChanged;

  const _PlaybackSettingsPanel({
    required this.speed,
    required this.speedOptions,
    required this.sustainEnabled,
    required this.onSpeedChanged,
    required this.onSustainChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 128),
      padding: const EdgeInsets.all(12),
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
              const Icon(
                Icons.speed_rounded,
                size: 17,
                color: AppColors.accent,
              ),
              const SizedBox(width: 6),
              Text(
                'Speed',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _AnchoredOptionButton<double>(
            value: speed,
            options: speedOptions.map((option) {
              return _OptionItem<double>(
                value: option,
                label: '${option.toStringAsFixed(2)}x',
              );
            }).toList(),
            onChanged: onSpeedChanged,
            minHeight: 36,
            dense: true,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sustain notes',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Transform.scale(
                scale: 0.78,
                child: Switch(
                  value: sustainEnabled,
                  activeThumbColor: AppColors.accent,
                  onChanged: onSustainChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _ResultCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(subtitle, style: AppTextStyles.caption),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.divider),
          child,
        ],
      ),
    );
  }
}

class _TablatureViewer extends StatelessWidget {
  final GeneratedTabResult tab;
  final int currentColumnIndex;
  final ScrollController scrollController;
  final ValueChanged<int> onColumnTap;

  const _TablatureViewer({
    required this.tab,
    required this.currentColumnIndex,
    required this.scrollController,
    required this.onColumnTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 230,
      child: SingleChildScrollView(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            const leftLabelWidth = 36.0;
            final dx = details.localPosition.dx - leftLabelWidth;
            final index = _columnIndexAtDx(dx);
            if (index != null) {
              onColumnTap(index);
            }
          },
          child: CustomPaint(
            size: Size(tab.totalWidth + 72, 220),
            painter: _TabPainter(
              tab: tab,
              currentColumnIndex: currentColumnIndex,
            ),
          ),
        ),
      ),
    );
  }

  int? _columnIndexAtDx(double dx) {
    if (tab.columns.isEmpty || dx < 0) return null;

    for (int i = 0; i < tab.columns.length; i++) {
      final column = tab.columns[i];
      final left = column.x;
      final right = column.x + column.width;

      if (dx >= left && dx <= right) {
        return i;
      }
    }

    return null;
  }
}

class _TabPainter extends CustomPainter {
  final GeneratedTabResult tab;
  final int currentColumnIndex;

  _TabPainter({required this.tab, required this.currentColumnIndex});

  @override
  void paint(Canvas canvas, Size size) {
    const leftLabelWidth = 36.0;
    const topPadding = 32.0;

    final linePaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1;

    final progressPaint = Paint()
      ..color = AppColors.success
      ..strokeWidth = 2.5;

    final measurePaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1.4;

    final currentColumnPaint = Paint()
      ..color = AppColors.success.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    final currentColumn = tab.columns[currentColumnIndex];
    final currentX = leftLabelWidth + currentColumn.x;

    canvas.drawRect(
      Rect.fromLTWH(currentX, 12, currentColumn.width, 190),
      currentColumnPaint,
    );

    for (final row in tab.rows) {
      final y = topPadding + row.visualIndex * tab.rowHeight;

      textPainter.text = TextSpan(
        text: '${row.label}|',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(10, y - 8));

      canvas.drawLine(
        Offset(leftLabelWidth, y),
        Offset(leftLabelWidth + tab.totalWidth + 28, y),
        linePaint,
      );
    }

    final tabTop = topPadding;
    final tabBottom = topPadding + (tab.rows.length - 1) * tab.rowHeight;
    canvas.drawLine(
      Offset(leftLabelWidth, tabTop),
      Offset(leftLabelWidth, tabBottom),
      measurePaint,
    );
    for (final column in tab.columns) {
      if (!column.startsMeasure ||
          column.eventIndex == tab.columns.first.eventIndex) {
        continue;
      }
      final x = leftLabelWidth + column.x - (tab.columnWidth * 0.22);
      canvas.drawLine(Offset(x, tabTop), Offset(x, tabBottom), measurePaint);
    }
    canvas.drawLine(
      Offset(leftLabelWidth + tab.totalWidth + 28, tabTop),
      Offset(leftLabelWidth + tab.totalWidth + 28, tabBottom),
      measurePaint,
    );

    for (final column in tab.columns) {
      for (final number in column.numbers) {
        final y = topPadding + number.visualRowIndex * tab.rowHeight;
        final x = leftLabelWidth + number.x;

        textPainter.text = TextSpan(
          text: number.fret.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        );
        textPainter.layout();

        final bgRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, y),
            width: textPainter.width + 10,
            height: 22,
          ),
          const Radius.circular(8),
        );

        final bgPaint = Paint()
          ..color = column.eventIndex == currentColumn.eventIndex
              ? AppColors.accent
              : AppColors.surface;

        canvas.drawRRect(bgRect, bgPaint);
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, y - textPainter.height / 2),
        );
      }
    }

    final progressX =
        leftLabelWidth + currentColumn.x + (currentColumn.width / 2);

    canvas.drawLine(
      Offset(progressX, 12),
      Offset(progressX, 205),
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TabPainter oldDelegate) {
    return oldDelegate.currentColumnIndex != currentColumnIndex ||
        oldDelegate.tab != tab;
  }
}

class _FretboardViewer extends StatelessWidget {
  final GeneratedTabColumn column;
  final ValueChanged<GeneratedTabNumber> onPositionTap;

  const _FretboardViewer({required this.column, required this.onPositionTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: GestureDetector(
        onTapUp: (details) {
          final hit = _hitTestFretboard(details.localPosition, context);
          if (hit != null) onPositionTap(hit);
        },
        child: CustomPaint(
          painter: _FretboardPainter(column: column),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  GeneratedTabNumber? _hitTestFretboard(Offset tap, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return null;

    final size = box.size;
    const frets = 12;
    const strings = 6;

    for (final number in column.numbers) {
      final stringVisualIndex = 6 - number.stringNumber;
      final y = (size.height / (strings - 1)) * stringVisualIndex;
      final fret = number.fret.clamp(0, frets);
      final x = fret == 0
          ? 10.0
          : ((size.width / frets) * fret) - ((size.width / frets) / 2);

      if ((tap - Offset(x, y)).distance <= 18) {
        return number;
      }
    }

    return null;
  }
}

class _FretboardPainter extends CustomPainter {
  final GeneratedTabColumn column;

  _FretboardPainter({required this.column});

  @override
  void paint(Canvas canvas, Size size) {
    const frets = 12;
    const strings = 6;

    final linePaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;

    final nutPaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 3;

    final highlightPaint = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < strings; i++) {
      final y = (size.height / (strings - 1)) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    for (int i = 0; i <= frets; i++) {
      final x = (size.width / frets) * i;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        i == 0 ? nutPaint : linePaint,
      );
    }

    for (final number in column.numbers) {
      final stringVisualIndex = 6 - number.stringNumber;
      final y = (size.height / (strings - 1)) * stringVisualIndex;
      final fret = number.fret.clamp(0, frets);
      final x = fret == 0
          ? 10.0
          : ((size.width / frets) * fret) - ((size.width / frets) / 2);

      canvas.drawCircle(Offset(x, y), 12, highlightPaint);

      textPainter.text = TextSpan(
        text: number.fret.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FretboardPainter oldDelegate) {
    return oldDelegate.column != column;
  }
}

class _RoundControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool emphasized;

  const _RoundControlButton({
    required this.icon,
    required this.onTap,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: emphasized ? 48 : 42,
        height: emphasized ? 48 : 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: emphasized ? AppColors.accent : AppColors.surface,
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(
          icon,
          color: onTap == null ? AppColors.textMuted : AppColors.textPrimary,
        ),
      ),
    );
  }
}
