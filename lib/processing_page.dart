import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_text_styles.dart';
import 'dummy_page.dart';
import 'services/staff_segmentation_service.dart';
import 'models/translation_group_models.dart';
import 'services/translation_grouping_service.dart';

/// Processing screen shown after the image crop is confirmed.
///
/// Responsibilities:
/// - display overall processing progress
/// - show each pipeline stage and its status
/// - simulate the current workflow for UI development
/// - prepare the structure for future Python/model integration
class ProcessingPage extends StatefulWidget {
  final String imagePath;

  const ProcessingPage({
    super.key,
    required this.imagePath,
  });

  @override
  State<ProcessingPage> createState() => _ProcessingPageState();
}

/// High-level state of one processing stage in the pipeline.
enum ProcessingStageStatus {
  pending,
  active,
  completed,
  failed,
}

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
  static const MethodChannel _processingChannel =
  MethodChannel('stala/python_bridge');

  late List<ProcessingStageItem> _stages;
  int _activeStageIndex = -1;
  bool _isProcessingFinished = false;
  bool _hasProcessingFailed = false;
  String _statusMessage = 'Preparing image for processing...';

  final StaffSegmentationService _segmentationService =
  StaffSegmentationService();

  final TranslationGroupingService _translationGroupingService =
  TranslationGroupingService();

  Map<String, dynamic>? _processingResult;

  @override
  void initState() {
    super.initState();
    _stages = _buildInitialStages();
    _startProcessingPipeline();
  }

  /// Creates the initial ordered pipeline list.
  ///
  /// These labels match the intended STALA workflow and can later
  /// be connected to real backend/model calls.
  List<ProcessingStageItem> _buildInitialStages() {
    return [
      const ProcessingStageItem(
        title: 'Preprocessing Image',
        subtitle: 'Applying crop, cleanup, and enhancement.',
        icon: Icons.tune_rounded,
        status: ProcessingStageStatus.pending,
      ),
      const ProcessingStageItem(
        title: 'Detecting Symbols',
        subtitle: 'Running Faster R-CNN multiclass symbol detection.',
        icon: Icons.center_focus_strong_rounded,
        status: ProcessingStageStatus.pending,
      ),
      const ProcessingStageItem(
        title: 'Segmenting Staff Lines',
        subtitle: 'Analyzing line and space structure for pitch mapping.',
        icon: Icons.horizontal_rule_rounded,
        status: ProcessingStageStatus.pending,
      ),
      const ProcessingStageItem(
        title: 'Translating Notes',
        subtitle: 'Combining detection and segmentation outputs.',
        icon: Icons.music_note_rounded,
        status: ProcessingStageStatus.pending,
      ),
      const ProcessingStageItem(
        title: 'Generating Results',
        subtitle: 'Preparing tablature and fretboard mapping.',
        icon: Icons.library_music_rounded,
        status: ProcessingStageStatus.pending,
      ),
    ];
  }

  /// Temporary simulated pipeline runner.
  ///
  /// Later, this can be replaced with real async steps such as:
  /// - preprocessing
  /// - symbol detection
  /// - staff segmentation
  /// - note translation
  /// - result generation
  Future<void> _startProcessingPipeline() async {
    print('DEBUG: _startProcessingPipeline started');
    try {
      if (!mounted) return;

      setState(() {
        print('DEBUG: activating stage 0');
        _activeStageIndex = 0;
        _statusMessage = 'Preparing image for processing...';
        _stages[0] = _stages[0].copyWith(
          status: ProcessingStageStatus.active,
        );
      });

      await Future.delayed(const Duration(milliseconds: 400));

      if (!mounted) return;

      setState(() {
        _stages[0] = _stages[0].copyWith(
          status: ProcessingStageStatus.completed,
        );
        _activeStageIndex = 1;
        _statusMessage = 'Running detection model...';
        _stages[1] = _stages[1].copyWith(
          status: ProcessingStageStatus.active,
        );
      });

      print('DEBUG: calling processImage');

      setState(() {
        _statusMessage = 'About to call native processImage...';
      });

      final dynamic result = await _processingChannel.invokeMethod(
        'processImage',
        {'imagePath': widget.imagePath},
      );

      print('DEBUG: processImage returned');

      setState(() {
        _statusMessage = 'Native processImage returned.';
      });

      if (!mounted) return;

      final response = Map<String, dynamic>.from(result as Map);
      _processingResult = response;

      final status = response['status']?.toString() ?? 'error';
      final message = response['message']?.toString();
      final errors = (response['errors'] as List?)?.cast<dynamic>() ?? const [];

      if (status == 'success') {
        setState(() {
          _stages[1] = _stages[1].copyWith(
            status: ProcessingStageStatus.completed,
          );
          _activeStageIndex = 2;
          _statusMessage = 'Running staff line segmentation...';
          _stages[2] = _stages[2].copyWith(
            status: ProcessingStageStatus.active,
          );
        });

        final segmentationInputPath =
            response['preprocessedImagePath'] ??
                response['detectionImagePath'] ??
                response['croppedImagePath'] ??
                widget.imagePath;

        print('DEBUG: segmentationInputPath = $segmentationInputPath');
        print('DEBUG: preprocessedImagePath = ${response['preprocessedImagePath']}');
        print('DEBUG: detectionImagePath = ${response['detectionImagePath']}');
        print('DEBUG: croppedImagePath = ${response['croppedImagePath']}');

        final segmentationResult =
        await _segmentationService.segmentStaffLines(
          imagePath: segmentationInputPath,
        );

        print('DEBUG: segmentedImagePath = ${segmentationResult['segmentedImagePath']}');

        if (segmentationResult['status'] == 'success') {
          response['segmentedImagePath'] =
          segmentationResult['segmentedImagePath'];
          response['staffLineCount'] =
          segmentationResult['staffLineCount'];
          response['staffLines'] =
          segmentationResult['staffLines'];
          response['validatedStaffs'] =
          segmentationResult['validatedStaffs'];

          setState(() {
            _stages[2] = _stages[2].copyWith(
              status: ProcessingStageStatus.completed,
            );
            _activeStageIndex = 3;
            _statusMessage = 'Building translation groups...';
            _stages[3] = _stages[3].copyWith(
              status: ProcessingStageStatus.active,
            );
          });

          final classItems = _parseClassItems(response['detections']);
          final translateGroups = _translationGroupingService.buildGroups(
            classItems: classItems,
            staffLines: (response['staffLines'] as List?) ?? const [],
          );

          response['translateGroups'] = translateGroups;
          _processingResult = response;

          setState(() {
            _stages[3] = _stages[3].copyWith(
              status: ProcessingStageStatus.completed,
            );

            _activeStageIndex = 4;
            _statusMessage = 'Generation stage placeholder ready.';
            _stages[4] = _stages[4].copyWith(
              status: ProcessingStageStatus.completed,
            );

            _isProcessingFinished = true;
            _statusMessage = message ?? 'Processing complete. Result is ready.';
          });
        } else {
          final segmentationMessage =
              segmentationResult['message']?.toString() ?? 'Unknown segmentation error';
          throw Exception('Segmentation failed: $segmentationMessage');
        }
      } else {
        setState(() {
          _stages[1] = _stages[1].copyWith(
            status: ProcessingStageStatus.failed,
          );
          _hasProcessingFailed = true;
          _statusMessage = errors.isNotEmpty
              ? errors.first.toString()
              : (message ?? 'Processing failed. Please try again.');
        });
      }
    } on PlatformException catch (error) {
      if (!mounted) return;

      setState(() {
        if (_activeStageIndex >= 0 && _activeStageIndex < _stages.length) {
          _stages[_activeStageIndex] = _stages[_activeStageIndex].copyWith(
            status: ProcessingStageStatus.failed,
          );
        }
        _hasProcessingFailed = true;
        _statusMessage =
        'Bridge error: ${error.message ?? error.code}';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        if (_activeStageIndex >= 0 && _activeStageIndex < _stages.length) {
          _stages[_activeStageIndex] = _stages[_activeStageIndex].copyWith(
            status: ProcessingStageStatus.failed,
          );
        }
        _hasProcessingFailed = true;
        _statusMessage = 'Processing failed: $error';
      });
    }
  }

  /// Resets the page state and runs the mock pipeline again.
  Future<void> _retryProcessing() async {
    setState(() {
      _activeStageIndex = -1;
      _isProcessingFinished = false;
      _hasProcessingFailed = false;
      _statusMessage = 'Preparing image for processing...';
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
  void _showNextStepMessage() {
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
      'preprocessedImagePath',
      'processedImagePath',
      'outputImagePath',
    ]);

    final detectedImagePath = _pickFirstNonEmptyString(result, const [
      'detectedImagePath',
      'annotatedImagePath',
      'visualizedImagePath',
      'detectionImagePath',
    ]);

    final segmentedImagePath = _pickFirstNonEmptyString(result, const [
      'segmentedImagePath',
    ]);

    final detections = _parseDetectionPoints(result['detections']);
    final classItems = _parseClassItems(result['detections']);
    final translateGroups =
        (result['translateGroups'] as List<StaffTranslateGroup>?) ?? const [];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DummyPage(
          croppedImagePath: croppedImagePath ?? widget.imagePath,
          detectedImagePath:
          detectedImagePath ?? croppedImagePath ?? widget.imagePath,
          segmentedImagePath: segmentedImagePath,
          detections: detections,
          classItems: classItems,
          translateGroups: translateGroups,
          generateOutputs: const [],
        ),
      ),
    );
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
                onBackTap: () => Navigator.pop(context),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// Top summary card with thumbnail, status, and progress.
                      _ProcessingSummaryCard(
                        progressValue: _progressValue,
                        title: _hasProcessingFailed
                            ? 'Processing Interrupted'
                            : _isProcessingFinished
                            ? 'Processing Complete'
                            : 'Processing Image',
                        subtitle: _statusMessage,
                        imagePath: widget.imagePath,
                        completedCount: _completedStageCount,
                        totalCount: _stages.length,
                        isFinished: _isProcessingFinished,
                        hasFailed: _hasProcessingFailed,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Pipeline Stages',
                        style: AppTextStyles.sectionTitle.copyWith(fontSize: 20),
                      ),
                      const SizedBox(height: 12),

                      /// Scrollable list of pipeline stage cards.
                      Expanded(
                        child: ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          itemCount: _stages.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final stage = _stages[index];
                            return _ProcessingStageCard(
                              stage: stage,
                              isActive: index == _activeStageIndex &&
                                  !_isProcessingFinished &&
                                  !_hasProcessingFailed,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              /// Footer reacts to three states:
              /// running, failed, and completed.
              _ProcessingFooter(
                isFinished: _isProcessingFinished,
                hasFailed: _hasProcessingFailed,
                onRetry: _retryProcessing,
                onContinue: _showNextStepMessage,
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
}

/// Top app header for the processing page.
class _ProcessingHeader extends StatelessWidget {
  final VoidCallback onBackTap;

  const _ProcessingHeader({
    required this.onBackTap,
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
              'Processing',
              style: AppTextStyles.sectionTitle.copyWith(fontSize: 20),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
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
                      ? 'Failed'
                      : isFinished
                      ? 'Completed'
                      : 'Running',
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progressValue,
                    minHeight: 8,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _progressColor(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$completedCount of $totalCount stages completed',
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

  const _ProcessingStageCard({
    required this.stage,
    required this.isActive,
  });

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
        return 'Pending';
      case ProcessingStageStatus.active:
        return 'Active';
      case ProcessingStageStatus.completed:
        return 'Completed';
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
              ? statusColor.withOpacity(0.55)
              : Colors.white.withOpacity(0.04),
        ),
        boxShadow: isActive
            ? [
          BoxShadow(
            color: statusColor.withOpacity(0.10),
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
            child: Icon(
              stage.icon,
              color: statusColor,
            ),
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
              Icon(
                _statusIcon(),
                size: 20,
                color: statusColor,
              ),
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
          top: BorderSide(
            color: Colors.white.withOpacity(0.04),
          ),
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
              label: 'Continue',
              onTap: onContinue,
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.textPrimary,
            )
                : const _FooterInfoLabel(
              icon: Icons.hourglass_top_rounded,
              label: 'Processing is running...',
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

  const _HeaderCircleButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0x220B162B),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(
          icon,
          size: 19,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Small pill that summarizes the overall processing state.
class _StatusPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accentColor;

  const _StatusPill({
    required this.label,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withOpacity(0.04),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: accentColor,
          ),
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
              Icon(
                icon,
                color: foregroundColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.button.copyWith(
                  color: foregroundColor,
                ),
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

  const _FooterInfoLabel({
    required this.icon,
    required this.label,
  });

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
          Icon(
            icon,
            color: AppColors.textSecondary,
            size: 19,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTextStyles.bodySecondary.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}