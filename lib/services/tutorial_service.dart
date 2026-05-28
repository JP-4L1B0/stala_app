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
  static const Duration _tourStartDelay = Duration(milliseconds: 250);

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

  static Future<bool> showHomeTabGuide(
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

  static Future<bool> showHomeGuide(
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

  static Future<bool> showImportGuide(
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

  static Future<bool> showCropGuide(
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

  static Future<bool> showProcessingGuide(
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

  static Future<bool> showResultGuide(
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
    TutorialPage? page,
  }) async {
    if (!context.mounted || await hasSeenTour(pageKey)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(delay);
      if (!context.mounted) return;

      if (page != null) {
        await showHowToUse(
          context,
          page: page,
          onStartTour: () =>
              startTour(context, keys: keys, pageKey: pageKey, markSeen: true),
        );
        if (context.mounted) await markTourSeen(pageKey);
        return;
      }

      await startTour(context, keys: keys, pageKey: pageKey, markSeen: true);
    });
  }

  static Future<bool> startTour(
    BuildContext context, {
    required List<GlobalKey> keys,
    required String pageKey,
    bool markSeen = false,
  }) async {
    if (!context.mounted) return false;

    final tourKeys = await _prepareTourKeys(context, keys);
    if (tourKeys.isEmpty) {
      if (context.mounted) {
        _showTourUnavailableMessage(context);
      }
      return false;
    }

    try {
      ShowcaseView.get().startShowCase(
        tourKeys,
        delay: const Duration(milliseconds: 80),
      );
      if (markSeen) await markTourSeen(pageKey);
      return true;
    } catch (error) {
      // A page can opt into help text before every target is wired. Missing
      // showcase context should never break normal app navigation.
      debugPrint('Unable to start tutorial tour: $error');
      if (context.mounted) {
        _showTourUnavailableMessage(context);
      }
      return false;
    }
  }

  static Future<List<GlobalKey>> _prepareTourKeys(
    BuildContext context,
    List<GlobalKey> keys,
  ) async {
    if (keys.isEmpty || !context.mounted) return const [];
    await Future<void>.delayed(_tourStartDelay);
    if (!context.mounted) return const [];
    return keys;
  }

  static void _showTourUnavailableMessage(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'The tour could not start on this screen. Please try again.',
            style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
          ),
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  static Future<void> showHowToUse(
    BuildContext context, {
    required TutorialPage page,
    VoidCallback? onStartTour,
  }) async {
    if (!context.mounted) return;

    final info = _contentFor(page);

    final shouldStartTour = await showDialog<bool>(
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
              Expanded(child: Text(info.title, style: AppTextStyles.cardTitle)),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              info.body,
              style: AppTextStyles.bodySecondary.copyWith(height: 1.45),
            ),
          ),
          actions: [
            if (onStartTour != null)
              TextButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                label: const Text('Start Tour'),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
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

    if (shouldStartTour == true && context.mounted && onStartTour != null) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!context.mounted) return;
      onStartTour();
    }
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
      tooltipActions: _tooltipActions,
      tooltipActionConfig: const TooltipActionConfig(
        alignment: MainAxisAlignment.spaceBetween,
        actionGap: 8,
        mainAxisSize: MainAxisSize.max,
      ),
      targetShapeBorder: targetShapeBorder,
      child: child,
    );
  }

  static List<TooltipActionButton> get _tooltipActions => [
    TooltipActionButton(
      type: TooltipDefaultActionType.skip,
      name: 'Skip',
      backgroundColor: AppColors.surface,
      textStyle: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
      border: Border.all(color: AppColors.border),
    ),
    TooltipActionButton(
      type: TooltipDefaultActionType.previous,
      name: 'Previous',
      backgroundColor: AppColors.surface,
      textStyle: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
      leadIcon: const ActionButtonIcon(
        icon: Icon(
          Icons.chevron_left_rounded,
          color: AppColors.textSecondary,
          size: 16,
        ),
      ),
      border: Border.all(color: AppColors.border),
    ),
    TooltipActionButton(
      type: TooltipDefaultActionType.next,
      name: 'Next',
      backgroundColor: AppColors.accent,
      textStyle: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
      tailIcon: const ActionButtonIcon(
        icon: Icon(
          Icons.chevron_right_rounded,
          color: AppColors.textPrimary,
          size: 16,
        ),
      ),
    ),
  ];

  static _TutorialContent _contentFor(TutorialPage page) {
    switch (page) {
      case TutorialPage.homeTab:
        return const _TutorialContent(
          title: 'Welcome to STALA',
          body:
              'STALA helps turn a photo of sheet music into guitar tablature. To begin, use the camera button for a new sheet, or open Import if you want to continue from a saved file.\n\nFor better results, take a clear photo with good lighting. Keep the whole sheet in view, avoid shadows or glare, and crop around the music before processing.\n\nTap Start Tour and I will point out the main parts of this screen one by one.',
        );
      case TutorialPage.homePage:
        return const _TutorialContent(
          title: 'Start a Project',
          body:
              'This is where you start new work. You can capture sheet music, choose an image, or reopen something you saved earlier.\n\nTry to use a flat, well-lit image where the staff lines and notes are easy to see. If the photo is blurry, tilted, or cuts off part of the music, the tablature may be less accurate.\n\nTap Start Tour and I will show what each main area does.',
        );
      case TutorialPage.importPage:
        return const _TutorialContent(
          title: 'Import and Continue',
          body:
              'Use this page when you want to open previous work or bring in a saved STALA file.\n\nMake sure the selected folder is the one where your files are stored. If something is missing, check that it is in that folder and that the file type is supported.\n\nTap Start Tour and I will show you where to choose a folder, import a file, and find saved items.',
        );
      case TutorialPage.cropPage:
        return const _TutorialContent(
          title: 'Prepare the Sheet',
          body:
              'Before STALA reads the sheet, line up the crop so the music is inside the frame. You can drag the corners or edges to adjust it, or tap Reset to return the frame to its starting position.\n\nKeep the staff lines, clefs, notes, and barlines visible. If the photo is too dark, blurry, tilted, or covered by glare, it is better to retake it.\n\nTap Start Tour and I will show you the crop frame, handles, Reset button, and Continue button.',
        );
      case TutorialPage.processingPage:
        return const _TutorialContent(
          title: 'Reading the Music',
          body:
              'STALA is reading the cropped sheet and turning it into tablature. This can take a moment, especially for busy pages.\n\nPlease wait until it finishes. If it cannot read the sheet, try again with a clearer photo or adjust the crop so the music is easier to see.\n\nTap Start Tour and I will show you what the progress areas mean.',
        );
      case TutorialPage.resultPage:
        return const _TutorialContent(
          title: 'Review the Tablature',
          body:
              'This page shows the tablature STALA created from your sheet. You can review it, play it back, check the fretboard view, change modes if available, and export your result.\n\nPlease review the tablature before saving or sharing. Photo quality and complex notation can affect the result, so playback and the fretboard view can help you spot anything unusual.\n\nTap Start Tour and I will walk you through the result tools.',
        );
    }
  }
}

class _TutorialContent {
  final String title;
  final String body;

  const _TutorialContent({required this.title, required this.body});
}
