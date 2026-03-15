import 'dart:io';

import 'package:flutter/material.dart';

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
  late List<ProcessingStageItem> _stages;
  int _activeStageIndex = -1;
  bool _isProcessingFinished = false;
  bool _hasProcessingFailed = false;
  String _statusMessage = 'Preparing image for processing...';

  @override
  void initState() {
    super.initState();
    _stages = _buildInitialStages();
    _startMockProcessingPipeline();
  }

  /// Creates the initial ordered pipeline list.
  ///
  /// These labels match the intended STALA workflow and can later
  /// be connected to real backend/model calls.
  List<ProcessingStageItem> _buildInitialStages() {
    return const [
      ProcessingStageItem(
        title: 'Preprocessing Image',
        subtitle: 'Applying crop, cleanup, and enhancement.',
        icon: Icons.tune_rounded,
        status: ProcessingStageStatus.pending,
      ),
      ProcessingStageItem(
        title: 'Detecting Symbols',
        subtitle: 'Running Faster R-CNN multi-class detection.',
        icon: Icons.center_focus_strong_rounded,
        status: ProcessingStageStatus.pending,
      ),
      ProcessingStageItem(
        title: 'Segmenting Staff Lines',
        subtitle: 'Analyzing line and space structure for pitch mapping.',
        icon: Icons.horizontal_rule_rounded,
        status: ProcessingStageStatus.pending,
      ),
      ProcessingStageItem(
        title: 'Translating Notes',
        subtitle: 'Combining detection and segmentation outputs.',
        icon: Icons.music_note_rounded,
        status: ProcessingStageStatus.pending,
      ),
      ProcessingStageItem(
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
  Future<void> _startMockProcessingPipeline() async {
    try {
      for (int index = 0; index < _stages.length; index++) {
        if (!mounted) return;

        setState(() {
          _activeStageIndex = index;
          _statusMessage = _stages[index].subtitle;
          _stages[index] = _stages[index].copyWith(
            status: ProcessingStageStatus.active,
          );
        });

        await Future.delayed(const Duration(seconds: 2));

        if (!mounted) return;

        setState(() {
          _stages[index] = _stages[index].copyWith(
            status: ProcessingStageStatus.completed,
          );
        });
      }

      if (!mounted) return;

      setState(() {
        _activeStageIndex = _stages.length - 1;
        _isProcessingFinished = true;
        _statusMessage = 'Processing complete. Result is ready.';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _hasProcessingFailed = true;
        _statusMessage = 'Processing failed. Please try again.';
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
    });

    await _startMockProcessingPipeline();
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

  /// Placeholder for the next navigation step after processing completes.
  void _showNextStepMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF091425),
        content: Text('Result page navigation goes here.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF081222),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0B162B),
                Color(0xFF081222),
                Color(0xFF05101D),
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
                      const Text(
                        'Pipeline Stages',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                        ),
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
                              indexLabel: '${index + 1}',
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
          const Expanded(
            child: Text(
              'Processing',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
              ),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF091425),
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
              color: const Color(0xFF16243B),
              child: Image.file(
                File(imagePath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return const Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: Color(0xFFA0AFC4),
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
                      ? const Color(0xFFFF7E57)
                      : isFinished
                      ? const Color(0xFF4DD0A9)
                      : const Color(0xFFFFA36A),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFA0AFC4),
                    fontSize: 13,
                    height: 1.45,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progressValue,
                    minHeight: 8,
                    backgroundColor: const Color(0xFF20304A),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      hasFailed
                          ? const Color(0xFFFF7E57)
                          : const Color(0xFFFF8F69),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$completedCount of $totalCount stages completed',
                  style: const TextStyle(
                    color: Color(0xFFB4C0D0),
                    fontSize: 12,
                    fontFamily: 'Inter',
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
  final String indexLabel;
  final ProcessingStageItem stage;
  final bool isActive;

  const _ProcessingStageCard({
    required this.indexLabel,
    required this.stage,
    required this.isActive,
  });

  Color _statusColor() {
    switch (stage.status) {
      case ProcessingStageStatus.pending:
        return const Color(0xFF566487);
      case ProcessingStageStatus.active:
        return const Color(0xFFFFA36A);
      case ProcessingStageStatus.completed:
        return const Color(0xFF4DD0A9);
      case ProcessingStageStatus.failed:
        return const Color(0xFFFF7E57);
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
        color: isActive ? const Color(0xFF16243B) : const Color(0xFF101C31),
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
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF20304A),
              border: Border.all(
                color: Colors.white.withOpacity(0.05),
              ),
            ),
            child: Text(
              indexLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF20304A),
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  stage.subtitle,
                  style: const TextStyle(
                    color: Color(0xFFA0AFC4),
                    fontSize: 12.5,
                    height: 1.45,
                    fontFamily: 'Inter',
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
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Inter',
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
        color: const Color(0xFF091425),
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
              backgroundColor: const Color(0xFF16243B),
              foregroundColor: const Color(0xFFFFA36A),
            )
                : isFinished
                ? _FooterActionButton(
              icon: Icons.arrow_forward_rounded,
              label: 'Continue',
              onTap: onContinue,
              backgroundColor: const Color(0xFFFF8F69),
              foregroundColor: Colors.white,
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
          color: const Color(0xFF22314B),
        ),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(
          icon,
          size: 19,
          color: const Color(0xFFB4C0D0),
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
        color: const Color(0xFF16243B),
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
            style: TextStyle(
              color: accentColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter',
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
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
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
        color: const Color(0xFF16243B),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: const Color(0xFFA0AFC4),
            size: 19,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFA0AFC4),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}