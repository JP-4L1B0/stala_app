import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_text_styles.dart';
import 'models/translation_group_models.dart';

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

  const GenerateOutputItem({
    required this.title,
    required this.value,
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
        );

      case DummyViewOption.generate:
        return _GeneratePanel(
          title: 'F. Generating - Generate',
          subtitle: 'Prepared output for graph / API generation',
          outputs: widget.generateOutputs,
        );
    }
  }
}

class _OptionDropdown extends StatelessWidget {
  final DummyViewOption value;
  final ValueChanged<DummyViewOption?> onChanged;

  const _OptionDropdown({
    required this.value,
    required this.onChanged,
  });

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

  const _PanelHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.divider),
        ),
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
                              color: AppColors.surface.withOpacity(0.92),
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
          return const Center(
            child: CircularProgressIndicator(),
          );
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
              Positioned.fill(
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                ),
              ),
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
    listener = ImageStreamListener((info, _) {
      completer.complete(info);
      stream.removeListener(listener);
    }, onError: (error, stackTrace) {
      completer.completeError(error, stackTrace);
      stream.removeListener(listener);
    });

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
      ..color = AppColors.accent.withOpacity(0.60)
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

      canvas.drawLine(
        Offset(x1, y),
        Offset(x2, y),
        ledgerPaint,
      );
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
        child: Center(
          child: Image.file(
            File(imagePath!),
            fit: BoxFit.contain,
          ),
        ),
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
                          _expandedClassKey =
                          isExpanded ? null : classKey;
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
                      Container(
                        height: 1,
                        color: AppColors.divider,
                      ),
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
                                border: Border.all(
                                  color: AppColors.border,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
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

  const _TranslatePanel({
    required this.title,
    required this.subtitle,
    required this.groups,
  });

  @override
  State<_TranslatePanel> createState() => _TranslatePanelState();
}

class _TranslatePanelState extends State<_TranslatePanel> {
  String? _expandedStaffId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PanelHeader(title: widget.title, subtitle: widget.subtitle),
        Expanded(
          child: widget.groups.isEmpty
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
                          _expandedStaffId =
                          isExpanded ? null : group.staffId;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
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
                      Container(
                        height: 1,
                        color: AppColors.divider,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            _TranslateBox(
                              title: 'Segment Map',
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: group.segmentMap
                                    .map(
                                      (item) => Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 5,
                                    ),
                                    child: Text(
                                      '${item.id} -- ${item.yDisplay} -- ${item.defaultKeyLabel}',
                                      style: AppTextStyles.bodySecondary.copyWith(
                                        fontSize: 12,
                                        color: item.id.startsWith('v_') ? Colors.lightBlueAccent : null,
                                        fontStyle: item.id.startsWith('v_') ? FontStyle.italic : null,
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
                                    .where((symbol) => symbol.assignmentStatus != 'ledgerCandidate')
                                    .map(
                                      (symbol) => Padding(
                                    padding:
                                    const EdgeInsets.only(
                                      bottom: 6,
                                    ),
                                    child: Text(
                                      _buildSymbolLine(symbol),
                                      style: AppTextStyles
                                          .bodySecondary
                                          .copyWith(
                                        fontSize: 12,
                                      ),
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
          ),
        ),
      ],
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
}

class _TranslateBox extends StatelessWidget {
  final String title;
  final Widget child;

  const _TranslateBox({
    required this.title,
    required this.child,
  });

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
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _GeneratePanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<GenerateOutputItem> outputs;

  const _GeneratePanel({
    required this.title,
    required this.subtitle,
    required this.outputs,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PanelHeader(title: title, subtitle: subtitle),
        Expanded(
          child: outputs.isEmpty
              ? const _EmptyPanelMessage(
            message: 'No generation payload available yet.',
          )
              : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: outputs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = outputs[index];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: RichText(
                  text: TextSpan(
                    style: AppTextStyles.body,
                    children: [
                      TextSpan(
                        text: '${item.title}: ',
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: item.value,
                        style: AppTextStyles.bodySecondary,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyPanelMessage extends StatelessWidget {
  final String message;

  const _EmptyPanelMessage({
    required this.message,
  });

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