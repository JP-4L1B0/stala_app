import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

enum TutorialPage {
  homeTab,
  homePage,
  importPage,
  cropPage,
  processingPage,
  resultPage,
}

class TutorialService {
  TutorialService._();

  static const String _prefix = 'stala_tutorial_seen_';

  static const String homeTabKey = 'home_tab';
  static const String homePageKey = 'home_page';
  static const String importPageKey = 'import_page';
  static const String cropPageKey = 'crop_page';
  static const String processingPageKey = 'processing_page';
  static const String resultPageKey = 'result_page';

  static Future<bool> hasSeenTour(String pageKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$pageKey') ?? false;
  }

  static Future<void> markTourSeen(String pageKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$pageKey', true);
  }

  static Future<void> resetTutorials() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in const [
      homeTabKey,
      homePageKey,
      importPageKey,
      cropPageKey,
      processingPageKey,
      resultPageKey,
    ]) {
      await prefs.remove('$_prefix$key');
    }
  }

  static Future<void> showHomeTabGuide(
    BuildContext context,
    List<GlobalKey> keys, {
    bool markSeen = false,
  }) {
    return startTour(
      context,
      keys: keys,
      pageKey: homeTabKey,
      markSeen: markSeen,
    );
  }

  static Future<void> showHomeGuide(
    BuildContext context,
    List<GlobalKey> keys, {
    bool markSeen = false,
  }) {
    return startTour(
      context,
      keys: keys,
      pageKey: homePageKey,
      markSeen: markSeen,
    );
  }

  static Future<void> showImportGuide(
    BuildContext context,
    List<GlobalKey> keys, {
    bool markSeen = false,
  }) {
    return startTour(
      context,
      keys: keys,
      pageKey: importPageKey,
      markSeen: markSeen,
    );
  }

  static Future<void> showCropGuide(
    BuildContext context,
    List<GlobalKey> keys, {
    bool markSeen = false,
  }) {
    return startTour(
      context,
      keys: keys,
      pageKey: cropPageKey,
      markSeen: markSeen,
    );
  }

  static Future<void> showProcessingGuide(
    BuildContext context,
    List<GlobalKey> keys, {
    bool markSeen = false,
  }) {
    return startTour(
      context,
      keys: keys,
      pageKey: processingPageKey,
      markSeen: markSeen,
    );
  }

  static Future<void> showResultGuide(
    BuildContext context,
    List<GlobalKey> keys, {
    bool markSeen = false,
  }) {
    return startTour(
      context,
      keys: keys,
      pageKey: resultPageKey,
      markSeen: markSeen,
    );
  }

  static Future<void> autoStartTour(
    BuildContext context, {
    required String pageKey,
    required List<GlobalKey> keys,
    Duration delay = const Duration(milliseconds: 450),
  }) async {
    if (!context.mounted || await hasSeenTour(pageKey)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(delay);
      if (!context.mounted) return;
      await startTour(context, keys: keys, pageKey: pageKey, markSeen: true);
    });
  }

  static Future<void> startTour(
    BuildContext context, {
    required List<GlobalKey> keys,
    required String pageKey,
    bool markSeen = false,
  }) async {
    if (!context.mounted) return;

    final visibleKeys = keys
        .where((key) => key.currentContext != null)
        .toList(growable: false);
    if (visibleKeys.isEmpty) {
      return;
    }

    try {
      // The context-bound API reliably targets the active page scope after
      // dialogs and route changes.
      // ignore: deprecated_member_use
      ShowCaseWidget.of(
        context,
      ).startShowCase(visibleKeys, delay: const Duration(milliseconds: 80));
      if (markSeen) await markTourSeen(pageKey);
    } catch (error) {
      // A page can opt into help text before every target is wired. Missing
      // showcase context should never break normal app navigation.
      debugPrint('Unable to start tutorial tour: $error');
    }
  }

  static Future<void> showHowToUse(
    BuildContext context, {
    required TutorialPage page,
    VoidCallback? onStartTour,
  }) async {
    if (!context.mounted) return;

    final info = _contentFor(page);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppColors.border),
          ),
          title: Row(
            children: [
              const Icon(Icons.help_outline_rounded, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(info.title, style: AppTextStyles.cardTitle),
              ),
            ],
          ),
          content: Text(
            info.body,
            style: AppTextStyles.bodySecondary.copyWith(height: 1.45),
          ),
          actions: [
            if (onStartTour != null)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    Future<void>.delayed(
                      const Duration(milliseconds: 250),
                      onStartTour,
                    );
                  });
                },
                icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                label: const Text('Start Tour'),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Close',
                style: AppTextStyles.button.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static Showcase showcase({
    required GlobalKey key,
    required String title,
    required String description,
    required Widget child,
    ShapeBorder targetShapeBorder = const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
    ),
  }) {
    return Showcase(
      key: key,
      title: title,
      description: description,
      tooltipBackgroundColor: AppColors.card,
      textColor: AppColors.textPrimary,
      titleTextStyle: AppTextStyles.cardTitle,
      descTextStyle: AppTextStyles.bodySecondary.copyWith(height: 1.35),
      overlayOpacity: 0.72,
      targetPadding: const EdgeInsets.all(6),
      tooltipBorderRadius: BorderRadius.circular(14),
      targetShapeBorder: targetShapeBorder,
      child: child,
    );
  }

  static _TutorialContent _contentFor(TutorialPage page) {
    switch (page) {
      case TutorialPage.homeTab:
        return const _TutorialContent(
          title: 'Home Tab',
          body:
              'Welcome to STALA. This is the main starting page of the application. From here, you can begin the sheet music processing workflow, access import options, view recent projects, and navigate to other parts of the app.',
        );
      case TutorialPage.homePage:
        return const _TutorialContent(
          title: 'Home Page',
          body:
              'Use this page to start the STALA workflow. You can capture a sheet music image using the camera, select an image from the gallery, or open a recent saved project. For best results, use clear and well-lit sheet music images.',
        );
      case TutorialPage.importPage:
        return const _TutorialContent(
          title: 'Import Page',
          body:
              'Use this page to import or open existing STALA files, saved projects, or supported local files. Imported files can be used to continue previous work or access generated outputs. Some import or cloud-related features may be unavailable if they are not yet implemented.',
        );
      case TutorialPage.cropPage:
        return const _TutorialContent(
          title: 'Crop Page',
          body:
              'Use this page to align the sheet music area before processing. Drag the corners or edges until the full music sheet is inside the frame. Make sure the staff lines are visible, clear, and not heavily tilted.',
        );
      case TutorialPage.processingPage:
        return const _TutorialContent(
          title: 'Processing Page',
          body:
              'This page analyzes the selected sheet music. STALA detects musical symbols, identifies staff lines, maps notes, and generates pitch-based guitar tablature. Please wait until processing is complete.',
        );
      case TutorialPage.resultPage:
        return const _TutorialContent(
          title: 'Result Page',
          body:
              'This page displays the generated guitar tablature. You can preview playback, switch tablature modes, inspect generated events, and save or export the result.',
        );
    }
  }
}

class _TutorialContent {
  final String title;
  final String body;

  const _TutorialContent({required this.title, required this.body});
}
