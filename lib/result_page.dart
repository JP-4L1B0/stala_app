import 'dart:async';
import 'package:flutter/material.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_text_styles.dart';
import 'services/generation_service.dart';
import 'services/save_export_service.dart';
import 'services/audio_playback_service.dart';
import 'models/session_data.dart';

class ResultPage extends StatefulWidget {
  final SessionData session;
  final List<GeneratedTabResult> generatedTabs;

  const ResultPage({
    super.key,
    required this.session,
    required this.generatedTabs,
  });

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  final AudioPlaybackService _audioService = AudioPlaybackService();

  bool _isMuted = false;
  List<int> _activeMidiNotes = [];

  int _toMidiNote({
    required int stringNumber,
    required int fret,
  }) {
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
  bool _didSave = false;

  List<GeneratedTabResult> get _availableTabs =>                             // fix(result): handle empty generated tablature modes
      widget.generatedTabs.where((tab) => tab.columns.isNotEmpty).toList();  // fix(result): handle empty generated tablature modes

  GeneratedTabResult get _currentTab => _availableTabs[_selectedModeIndex];  // fix(result): handle empty generated tablature modes

  GeneratedTabColumn get _currentColumn =>
      _currentTab.columns[_currentColumnIndex];

  @override
  void dispose() {
    _timer?.cancel();
    _audioService.stopAll();
    _tabScrollController.dispose();
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

    // Play tapped note/chord once, unless muted.
    await _playCurrentColumnAudio();

    await Future.delayed(
      Duration(
        milliseconds: (_currentColumn.durationSeconds * 1000)
            .round()
            .clamp(250, 900),
      ),
    );

    await _stopActiveAudio();
  }

  void _previous() {
    _jumpToColumn(_currentColumnIndex - 1);
  }

  void _next() {
    _jumpToColumn(_currentColumnIndex + 1);
  }

  Future<void> _togglePlay() async {
    print('Play pressed');
    if (_isPlaying) {
      _timer?.cancel();
      await _stopActiveAudio();

      if (!mounted) return;

      setState(() {
        _isPlaying = false;
      });

      return;
    }

    setState(() => _isPlaying = true);

    await _playCurrentColumnAudio();
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();

    final duration = Duration(
      milliseconds: (_currentColumn.durationSeconds * 1000).round(),
    );

    _timer = Timer(duration, () async {
      if (!mounted || !_isPlaying) return;

      await _stopActiveAudio();

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

  void _scrollToCurrent() {
    if (!_tabScrollController.hasClients) return;

    final viewportWidth = _tabScrollController.position.viewportDimension;

    final target =
        (_currentColumnIndex * _currentTab.columnWidth) -
            (viewportWidth / 2) +
            (_currentTab.columnWidth / 2);

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

  bool get _shouldRefreshRecent {
    return _didSave || widget.session.autoSavedAt != null;
  }

  void _exitResultPage() {
    _timer?.cancel();
    _stopActiveAudio();
    Navigator.pop(context, _shouldRefreshRecent);
  }

  @override
  Widget build(BuildContext context) {
    final availableTabs = widget.generatedTabs
        .where((tab) => tab.columns.isNotEmpty)
        .toList();

    if (availableTabs.isEmpty) {
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
          color: AppColors.surface,
          onPressed: _exitResultPage,
        ),
        title: Text(
          'Result',
          style: AppTextStyles.sectionTitle.copyWith(fontSize: 20),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopDropdown(),
            _buildAutoSaveStatus(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _ResultCard(
                    title: 'Tablature',
                    subtitle: 'Tap a fret number to jump to that event.',
                    child: _TablatureViewer(
                      tab: _currentTab,
                      currentColumnIndex: _currentColumnIndex,
                      scrollController: _tabScrollController,
                      onColumnTap: _jumpToColumn,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildControlCard(),
                  const SizedBox(height: 14),
                  _ResultCard(
                    title: 'Fretboard Map',
                    subtitle: 'Highlighted positions update per event.',
                    child: _FretboardViewer(
                      column: _currentColumn,
                      onPositionTap: _showFretDetail,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildBottomActions(),
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
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedModeIndex,
                  dropdownColor: AppColors.card,
                  iconEnabledColor: AppColors.textPrimary,
                  style: AppTextStyles.button,
                  items: List.generate(_availableTabs.length, (index) { // fix(result): handle empty generated tablature modes
                    final tab = _availableTabs[index];                  // fix(result): handle empty generated tablature modes
                    return DropdownMenuItem(
                      value: index,
                      child: Text(_formatMode(tab.mode.name)),
                    );
                  }),
                  onChanged: (value) {
                    if (value != null) _changeMode(value);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoSaveStatus() {
    final session = widget.session;

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
          Row(
            children: [
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
                icon: _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                onTap: () async {
                  final nextMuted = !_isMuted;

                  setState(() {
                    _isMuted = nextMuted;
                  });

                  if (nextMuted) {
                    await _stopActiveAudio();
                  } else if (_isPlaying) {
                    await _playCurrentColumnAudio();
                  }
                },
              ),

              const SizedBox(width: 14),
              Expanded(
                child: LinearProgressIndicator(
                  value: _currentTab.columns.isEmpty
                      ? 0
                      : (_currentColumnIndex + 1) / _currentTab.columns.length,
                  minHeight: 8,
                  backgroundColor: AppColors.border,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
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
                  'Event ${_currentColumnIndex + 1} of ${_currentTab.columns.length}',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  detail.displayTitle,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail.displaySubtitle,
                  style: AppTextStyles.bodySecondary.copyWith(fontSize: 12.5),
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

  Widget _buildBottomActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _exitResultPage,
            child: const Text('Back'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _showSaveOptions,
            child: const Text('Save As'),
          ),
        ),
      ],
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

  void _showSaveOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                title: const Text('Save as PNG', style: AppTextStyles.cardTitle),
                subtitle: const Text('Export tablature image pages', style: AppTextStyles.caption),
                onTap: () async {
                  Navigator.pop(context);

                  final files = await const SaveExportService().saveTabPngPages(
                    title: _currentTab.title,
                    tab: _currentTab,
                  );

                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Saved PNG page(s) successfully.'),
                    ),
                  );
                  setState(() {
                    _didSave = true;
                  });
                },
              ),
              ListTile(
                title: const Text('Save as .stala', style: AppTextStyles.cardTitle),
                subtitle: const Text('Export structured project data', style: AppTextStyles.caption),
                onTap: () async {
                  Navigator.pop(context);

                  final file = await const SaveExportService().saveStalaFile(
                    session: widget.session,
                  );

                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Saved .stala file successfully.'),
                    ),
                  );
                  setState(() {
                    _didSave = true;
                  });
                },
              ),
              ListTile(
                title: const Text('Save as ZIP', style: AppTextStyles.cardTitle),
                subtitle: const Text('Export PNG pages + .stala file', style: AppTextStyles.caption),
                onTap: () async {
                  Navigator.pop(context);

                  final file = await const SaveExportService().saveZipPackage(
                    session: widget.session,
                    selectedModeIndex: _selectedModeIndex,
                  );

                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Saved ZIP package successfully.'),
                    ),
                  );
                  setState(() {
                    _didSave = true;
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatMode(String raw) {
    switch (raw) {
      case 'strict':
        return 'Strict Melody';
      case 'continuity':
        return 'Continuity Melody';
      case 'chordAware':
        return 'Chord-Aware';
      default:
        return raw;
    }
  }

  /// This is the audio helper block
  Future<void> _playCurrentColumnAudio() async {
    if (_isMuted) {
      print('AUDIO: muted, skipping column $_currentColumnIndex');
      return;
    }

    print('--- PLAY COLUMN ---');
    print('Column Index: $_currentColumnIndex');

    final notes = _currentColumn.numbers.map((number) {
      final midi = _toMidiNote(
        stringNumber: number.stringNumber,
        fret: number.fret,
      );

      print('String ${number.stringNumber}, Fret ${number.fret} → MIDI $midi');

      return midi;
    }).toList();

    print('Total notes: ${notes.length}');
    print('--------------------');

    if (notes.isEmpty) {
      print('No notes to play');
      return;
    }

    _activeMidiNotes = notes;

    await _audioService.playChord(notes);
  }

  Future<void> _stopActiveAudio() async {
    final notes = List<int>.from(_activeMidiNotes);
    _activeMidiNotes = [];

    if (notes.isNotEmpty) {
      await _audioService.stopChord(notes);
    }

    await _audioService.stopAll();
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
                Text(title, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
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
            final index = (dx / tab.columnWidth).floor();
            onColumnTap(index);
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
}

class _TabPainter extends CustomPainter {
  final GeneratedTabResult tab;
  final int currentColumnIndex;

  _TabPainter({
    required this.tab,
    required this.currentColumnIndex,
  });

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

    final currentColumnPaint = Paint()
      ..color = AppColors.success.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    final currentX =
        leftLabelWidth + (currentColumnIndex * tab.columnWidth);

    canvas.drawRect(
      Rect.fromLTWH(currentX, 12, tab.columnWidth, 190),
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
          ..color = column.eventIndex == tab.columns[currentColumnIndex].eventIndex
              ? AppColors.accent
              : AppColors.surface;

        canvas.drawRRect(bgRect, bgPaint);
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, y - textPainter.height / 2),
        );
      }
    }

    final progressX = leftLabelWidth +
        (currentColumnIndex * tab.columnWidth) +
        (tab.columnWidth / 2);

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

  const _FretboardViewer({
    required this.column,
    required this.onPositionTap,
  });

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
          color: onTap == null
              ? AppColors.textMuted
              : AppColors.textPrimary,
        ),
      ),
    );
  }
}