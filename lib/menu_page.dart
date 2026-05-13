import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

import 'camera_panel.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_text_styles.dart';
import 'data/recent_items_repository.dart';
import 'data/debug_settings_repository.dart';
import 'models/saved_item_data.dart';
import 'result_page.dart';
import 'services/generation_service.dart';
import 'services/save_export_service.dart';
import 'services/storage_access_service.dart';
import 'services/tutorial_service.dart';
import 'app_restart_widget.dart';
import 'data/app_settings_repository.dart';

class AccessibilityServiceHelper {
  static const MethodChannel _channel = MethodChannel(
    'stala_app/accessibility',
  );

  static Future<bool> isAccessibilityEnabled() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'isAccessibilityEnabled',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {
      // Ignore missing platform support; callers already update from state.
    }
  }
}

/// Defines the available bottom navigation tabs.
enum PanelTab { search, camera, home, settings }

/// Main menu screen that hosts the header, tab content, and bottom navigation.
class MainPanel01Page extends StatefulWidget {
  const MainPanel01Page({super.key});

  @override
  State<MainPanel01Page> createState() => _MainPanel01PageState();
}

class _MainPanel01PageState extends State<MainPanel01Page>
    with SingleTickerProviderStateMixin {
  final StorageAccessService _storageAccessService =
      const StorageAccessService();

  /// Currently visible content tab; the camera tab opens a separate route.
  PanelTab _selectedTab = PanelTab.home;
  int _homeRefreshNonce = 0;

  late final AnimationController _cameraButtonController;
  late final Animation<double> _cameraFloatAnimation;
  final GlobalKey _headerTourKey = GlobalKey();
  final GlobalKey _helpTourKey = GlobalKey();
  final GlobalKey _importNavTourKey = GlobalKey();
  final GlobalKey _cameraNavTourKey = GlobalKey();
  final GlobalKey _homeNavTourKey = GlobalKey();
  final GlobalKey _homeRecentTourKey = GlobalKey();
  final GlobalKey _homeBulkTourKey = GlobalKey();
  final GlobalKey _importStorageTourKey = GlobalKey();
  final GlobalKey _importActionTourKey = GlobalKey();
  final GlobalKey _importListTourKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    _cameraButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _cameraFloatAnimation = Tween<double>(begin: -2, end: 4).animate(
      CurvedAnimation(parent: _cameraButtonController, curve: Curves.easeInOut),
    );

    TutorialService.autoStartTour(
      context,
      pageKey: TutorialService.homeTabKey,
      keys: _homeTabTourKeys,
    );
  }

  @override
  void dispose() {
    _cameraButtonController.dispose();
    super.dispose();
  }

  /// Handles taps from the bottom navigation.
  void _onTabSelected(PanelTab tab) {
    if (tab == PanelTab.camera) {
      _openCameraPanel();
      return;
    }

    setState(() {
      _selectedTab = tab;
      if (tab == PanelTab.home) {
        _homeRefreshNonce++;
      }
    });

    if (tab == PanelTab.search) {
      TutorialService.autoStartTour(
        context,
        pageKey: TutorialService.importPageKey,
        keys: _importPageTourKeys,
      );
    } else if (tab == PanelTab.home) {
      TutorialService.autoStartTour(
        context,
        pageKey: TutorialService.homePageKey,
        keys: _homePageTourKeys,
      );
    }
  }

  /// Opens the camera route and returns to Home when a saved result changed.
  Future<void> _openCameraPanel() async {
    final hasStoragePath = await _ensureStoragePathSelected();
    if (!hasStoragePath || !mounted) return;

    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const CameraPanelPage()));

    if (!mounted) return;

    setState(() {
      _selectedTab = PanelTab.home;
      _homeRefreshNonce++;
    });
  }

  Future<bool> _ensureStoragePathSelected() async {
    final current = await _storageAccessService.getStorageFolder();
    if (current.granted) return true;

    if (!mounted) return false;

    final shouldPick = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Choose Save Folder', style: AppTextStyles.cardTitle),
          content: Text(
            'Choose where STALA should save and import your .stala, .zip, PNG, and PDF files before using the camera.',
            style: AppTextStyles.bodySecondary,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: AppTextStyles.button.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.textPrimary,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text('Pick Folder', style: AppTextStyles.button),
            ),
          ],
        );
      },
    );

    if (shouldPick != true) return false;

    final selected = await _storageAccessService.pickStorageFolder();
    return selected.granted;
  }

  List<GlobalKey> get _homeTabTourKeys => [
    _headerTourKey,
    _cameraNavTourKey,
    _importNavTourKey,
    _homeRecentTourKey,
    _homeNavTourKey,
    _helpTourKey,
  ];

  List<GlobalKey> get _homePageTourKeys => [
    _headerTourKey,
    _cameraNavTourKey,
    _homeRecentTourKey,
    _homeBulkTourKey,
    _helpTourKey,
  ];

  List<GlobalKey> get _importPageTourKeys => [
    _importStorageTourKey,
    _importActionTourKey,
    _importListTourKey,
    _helpTourKey,
  ];

  void _showCurrentHelp() {
    final isImport = _selectedTab == PanelTab.search;
    TutorialService.showHowToUse(
      context,
      page: isImport ? TutorialPage.importPage : TutorialPage.homeTab,
      onStartTour: () {
        if (!mounted) return;
        if (isImport) {
          TutorialService.showImportGuide(context, _importPageTourKeys);
        } else {
          TutorialService.showHomeTabGuide(context, _homeTabTourKeys);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              const SizedBox(height: 8),

              _PanelHeader(
                headerTourKey: _headerTourKey,
                helpTourKey: _helpTourKey,
                isSettingsSelected: _selectedTab == PanelTab.settings,
                onSettingsTap: () => _onTabSelected(PanelTab.settings),
                onHelpTap: _showCurrentHelp,
              ),

              const SizedBox(height: 18),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _PanelMidContent(
                    selectedTab: _selectedTab,
                    homeRefreshNonce: _homeRefreshNonce,
                    homeRecentTourKey: _homeRecentTourKey,
                    homeBulkTourKey: _homeBulkTourKey,
                    importStorageTourKey: _importStorageTourKey,
                    importActionTourKey: _importActionTourKey,
                    importListTourKey: _importListTourKey,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              _PanelFooter(
                selectedTab: _selectedTab,
                cameraFloatAnimation: _cameraFloatAnimation,
                importNavTourKey: _importNavTourKey,
                cameraNavTourKey: _cameraNavTourKey,
                homeNavTourKey: _homeNavTourKey,
                onTabSelected: _onTabSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// HEADER
// -----------------------------------------------------------------------------

/// Top brand header with the STALA mark and Settings entry point.
class _PanelHeader extends StatelessWidget {
  final GlobalKey headerTourKey;
  final GlobalKey helpTourKey;
  final bool isSettingsSelected;
  final VoidCallback onSettingsTap;
  final VoidCallback onHelpTap;

  const _PanelHeader({
    required this.headerTourKey,
    required this.helpTourKey,
    required this.isSettingsSelected,
    required this.onSettingsTap,
    required this.onHelpTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: TutorialService.showcase(
              key: headerTourKey,
              title: 'STALA Workspace',
              description:
                  'This header shows the current STALA workspace while you move between Home, Import, and Settings.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'STALA',
                    style: AppTextStyles.cardTitle.copyWith(letterSpacing: 0.2),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Read Notes. Play Strings',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          TutorialService.showcase(
            key: helpTourKey,
            title: 'Help and Tutorial',
            description:
                'Open this anytime to read page help or replay the guided tour.',
            targetShapeBorder: const CircleBorder(),
            child: InkWell(
              onTap: onHelpTap,
              borderRadius: BorderRadius.circular(17),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.card,
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: const Icon(
                  Icons.help_outline_rounded,
                  color: AppColors.accent,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onSettingsTap,
            borderRadius: BorderRadius.circular(17),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSettingsSelected
                    ? AppColors.accent.withOpacity(0.16)
                    : AppColors.card,
                border: Border.all(
                  color: isSettingsSelected
                      ? AppColors.accent.withOpacity(0.55)
                      : Colors.white.withOpacity(0.08),
                ),
              ),
              child: Icon(
                Icons.settings_outlined,
                color: isSettingsSelected
                    ? AppColors.accent
                    : AppColors.textSecondary,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// MID SECTION
// -----------------------------------------------------------------------------

/// Animated tab host for Import, Home, and Settings content.
class _PanelMidContent extends StatelessWidget {
  final PanelTab selectedTab;
  final int homeRefreshNonce;
  final GlobalKey homeRecentTourKey;
  final GlobalKey homeBulkTourKey;
  final GlobalKey importStorageTourKey;
  final GlobalKey importActionTourKey;
  final GlobalKey importListTourKey;

  const _PanelMidContent({
    required this.selectedTab,
    required this.homeRefreshNonce,
    required this.homeRecentTourKey,
    required this.homeBulkTourKey,
    required this.importStorageTourKey,
    required this.importActionTourKey,
    required this.importListTourKey,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0.15, 0),
          end: Offset.zero,
        ).animate(animation);

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offsetAnimation, child: child),
        );
      },
      child: _buildSelectedContent(),
    );
  }

  Widget _buildSelectedContent() {
    switch (selectedTab) {
      case PanelTab.search:
        return _ImportTabView(
          key: const ValueKey('import-tab'),
          storageTourKey: importStorageTourKey,
          importActionTourKey: importActionTourKey,
          listTourKey: importListTourKey,
        );
      case PanelTab.home:
        return _HomeTabView(
          key: ValueKey('home-tab-$homeRefreshNonce'),
          recentTourKey: homeRecentTourKey,
          bulkTourKey: homeBulkTourKey,
        );
      case PanelTab.settings:
        return const _SettingsTabView(key: ValueKey('settings-tab'));
      case PanelTab.camera:
        return const SizedBox.shrink();
    }
  }
}

/// Home tab listing saved STALA items with refresh, open, rename, pin, delete,
/// selection, and bulk export actions.
class _HomeTabView extends StatefulWidget {
  final GlobalKey recentTourKey;
  final GlobalKey bulkTourKey;

  const _HomeTabView({
    super.key,
    required this.recentTourKey,
    required this.bulkTourKey,
  });

  @override
  State<_HomeTabView> createState() => _HomeTabViewState();
}

class _HomeTabViewState extends State<_HomeTabView> {
  final AppSettingsRepository _appSettingsRepository =
      const AppSettingsRepository();

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
    });

    final items = await RecentItemsRepository.getRecentItems();
    final recentFileLimit = await _appSettingsRepository.getRecentFileLimit();

    if (!mounted) return;

    setState(() {
      _items = items;
      _recentFileLimit = recentFileLimit;
      _isLoading = false;
      _selectedItemKeys.removeWhere(
        (key) => !_items.any((item) => _itemKey(item) == key),
      );
      if (_selectedItemKeys.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  bool _showAll = false;

  List<SavedItemData> _items = [];
  bool _isLoading = true;
  bool _isSelectionMode = false;
  int _recentFileLimit = AppSettingsRepository.minimumRecentFileLimit;
  final Set<String> _selectedItemKeys = <String>{};

  List<SavedItemData> get _visibleItems {
    return _showAll ? _items : _items.take(_recentFileLimit).toList();
  }

  void _handleRename(int index) {
    final item = _visibleItems[index];

    final controller = TextEditingController(text: item.title);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Rename File', style: AppTextStyles.cardTitle),
          content: TextField(
            controller: controller,
            style: AppTextStyles.body,
            decoration: InputDecoration(
              hintText: 'Enter new title',
              hintStyle: AppTextStyles.bodySecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: AppTextStyles.button.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.textPrimary,
              ),
              onPressed: () async {
                final updatedTitle = controller.text.trim();

                if (updatedTitle.isEmpty) return;

                try {
                  await RecentItemsRepository.renameItem(item, updatedTitle);
                } on DuplicateFileNameException catch (error) {
                  if (!context.mounted) return;

                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error.toString())));
                  return;
                }

                if (!mounted) return;

                Navigator.pop(context);

                await _loadItems();
              },
              child: Text('Save', style: AppTextStyles.button),
            ),
          ],
        );
      },
    );
  }

  String _itemKey(SavedItemData item) {
    return item.storageUri ?? item.filePath;
  }

  List<SavedItemData> get _selectedItems {
    return _items
        .where((item) => _selectedItemKeys.contains(_itemKey(item)))
        .toList();
  }

  void _toggleSelectionMode() {
    setState(() {
      final shouldEnterSelectionMode = !_isSelectionMode;
      _isSelectionMode = shouldEnterSelectionMode;
      _showAll = shouldEnterSelectionMode;
      _selectedItemKeys.clear();
    });
  }

  void _toggleItemSelection(SavedItemData item) {
    final key = _itemKey(item);

    setState(() {
      if (_selectedItemKeys.contains(key)) {
        _selectedItemKeys.remove(key);
      } else {
        _selectedItemKeys.add(key);
      }

      if (_selectedItemKeys.isEmpty) {
        _isSelectionMode = false;
        _showAll = false;
      }
    });
  }

  void _selectAllVisible() {
    setState(() {
      final visibleKeys = _visibleItems.map(_itemKey).toSet();
      final hasSelectedAllVisible =
          visibleKeys.isNotEmpty &&
          visibleKeys.every(_selectedItemKeys.contains);

      if (hasSelectedAllVisible) {
        _selectedItemKeys.clear();
        _isSelectionMode = false;
        _showAll = false;
        return;
      }

      _showAll = true;
      final selectableItems = _items;
      final selectableKeys = selectableItems.map(_itemKey).toSet();

      _isSelectionMode = true;
      _selectedItemKeys
        ..clear()
        ..addAll(selectableKeys);
    });
  }

  Future<void> _openSavedItem(SavedItemData item) async {
    try {
      final session = await RecentItemsRepository.loadSessionFromItem(item);

      final generatedTabs = const GenerationService().generateAll(
        results: session.tablatureResults,
      );

      if (!mounted) return;

      final didSave = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ResultPage(
            session: session,
            generatedTabs: generatedTabs,
            sourceItem: item,
          ),
        ),
      );

      if (didSave == true) {
        await _loadItems();
      }
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open saved item: $error')),
      );
    }
  }

  Future<void> _handleDelete(SavedItemData item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Delete File', style: AppTextStyles.cardTitle),
          content: Text(
            'Delete "${item.title}" from saved items?',
            style: AppTextStyles.bodySecondary,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: AppTextStyles.button),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.textPrimary,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await RecentItemsRepository.deleteItem(item);

    if (!mounted) return;

    setState(() {
      _items.removeWhere((saved) => _itemKey(saved) == _itemKey(item));
    });
  }

  Future<void> _handleBulkDelete() async {
    final selectedItems = _selectedItems;
    if (selectedItems.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Delete Files', style: AppTextStyles.cardTitle),
          content: Text(
            'Delete ${selectedItems.length} selected STALA file(s)?',
            style: AppTextStyles.bodySecondary,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: AppTextStyles.button),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.textPrimary,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete', style: AppTextStyles.button),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    for (final item in selectedItems) {
      await RecentItemsRepository.deleteItem(item);
    }

    if (!mounted) return;

    setState(() {
      _selectedItemKeys.clear();
      _isSelectionMode = false;
    });

    await _loadItems();
  }

  Future<void> _handleBulkExport() async {
    final selectedItems = _selectedItems;
    if (selectedItems.isEmpty) return;

    try {
      await const SaveExportService().saveBulkStalaZip(items: selectedItems);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${selectedItems.length} STALA file(s) as ZIP.',
          ),
        ),
      );

      setState(() {
        _selectedItemKeys.clear();
        _isSelectionMode = false;
      });
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Bulk export failed: $error')));
    }
  }

  Future<void> _handlePin(SavedItemData item) async {
    final updated = await RecentItemsRepository.togglePinned(_items, item);

    if (!mounted) return;

    setState(() {
      _items = updated;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('home-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TutorialService.showcase(
          key: widget.recentTourKey,
          title: 'Recent Projects',
          description:
              'Open previous STALA results here when saved projects are available.',
          child: _SectionHeader(
            title: 'Recent',
            actionIcon: _isSelectionMode
                ? null
                : (_showAll
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded),
            actionTooltip: _isSelectionMode
                ? null
                : (_showAll ? 'Show less' : 'View all'),
            onActionTap: () {
              if (_isSelectionMode) {
                return;
              }

              setState(() {
                _showAll = !_showAll;
              });
            },
          ),
        ),
        const SizedBox(height: 14),
        if (!_isLoading && _items.isNotEmpty) ...[
          TutorialService.showcase(
            key: widget.bulkTourKey,
            title: 'Project Actions',
            description:
                'Select saved projects to export or delete multiple items at once.',
            child: _HomeBulkActionBar(
              isSelectionMode: _isSelectionMode,
              selectedCount: _selectedItemKeys.length,
              onSelect: _toggleSelectionMode,
              onSelectAll: _selectAllVisible,
              onDelete: _handleBulkDelete,
              onExport: _handleBulkExport,
            ),
          ),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadItems,
            child: _isLoading
                ? ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: 4,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, __) => const _SavedItemSkeletonCard(),
                  )
                : _visibleItems.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text(
                          'No saved items yet.',
                          style: AppTextStyles.bodySecondary,
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _visibleItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return SavedListCard(
                        data: _visibleItems[index],
                        onEdit: () => _handleRename(index),
                        onDelete: () => _handleDelete(_visibleItems[index]),
                        onPin: () => _handlePin(_visibleItems[index]),
                        isSelectionMode: _isSelectionMode,
                        isSelected: _selectedItemKeys.contains(
                          _itemKey(_visibleItems[index]),
                        ),
                        onTap: () {
                          if (_isSelectionMode) {
                            _toggleItemSelection(_visibleItems[index]);
                          } else {
                            _openSavedItem(_visibleItems[index]);
                          }
                        },
                        onLongPress: () {
                          setState(() {
                            _isSelectionMode = true;
                            _showAll = true;
                            _selectedItemKeys.add(
                              _itemKey(_visibleItems[index]),
                            );
                          });
                        },
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// Selection toolbar for Home tab bulk export and delete actions.
class _HomeBulkActionBar extends StatelessWidget {
  final bool isSelectionMode;
  final int selectedCount;
  final VoidCallback onSelect;
  final VoidCallback onSelectAll;
  final VoidCallback onDelete;
  final VoidCallback onExport;

  const _HomeBulkActionBar({
    required this.isSelectionMode,
    required this.selectedCount,
    required this.onSelect,
    required this.onSelectAll,
    required this.onDelete,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedCount > 0;
    final disabledColor = AppColors.textMuted.withOpacity(0.55);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text(
            '$selectedCount selected',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: isSelectionMode ? 'Select all' : 'Select items',
            onPressed: isSelectionMode ? onSelectAll : onSelect,
            icon: Icon(
              isSelectionMode
                  ? Icons.select_all_rounded
                  : Icons.checklist_rounded,
              size: 18,
            ),
            color: AppColors.accent,
          ),
          IconButton(
            tooltip: 'Export selected',
            onPressed: hasSelection ? onExport : null,
            icon: const Icon(Icons.archive_outlined),
            color: AppColors.accent,
            disabledColor: disabledColor,
          ),
          IconButton(
            tooltip: 'Delete selected',
            onPressed: hasSelection ? onDelete : null,
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppColors.accent,
            disabledColor: disabledColor,
          ),
        ],
      ),
    );
  }
}

/// Saved item row used by both recent files and import results.
class SavedListCard extends StatelessWidget {
  final SavedItemData data;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelectionMode;
  final bool isSelected;

  const SavedListCard({
    super.key,
    required this.data,
    required this.onEdit,
    required this.onDelete,
    required this.onPin,
    this.onTap,
    this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: isSelectionMode
                  ? Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.textSecondary,
                      size: 30,
                    )
                  : Padding(
                      padding: const EdgeInsets.all(10),
                      child: Image.asset(
                        'assets/images/stala_logo_icon.png',
                        fit: BoxFit.contain,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: AppTextStyles.body.copyWith(height: 1.4),
                            children: [
                              TextSpan(
                                text: data.title,
                                style: AppTextStyles.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (data.isPinned) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.push_pin_rounded,
                          size: 14,
                          color: AppColors.accent,
                        ),
                      ],
                      if (!isSelectionMode)
                        PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_vert_rounded,
                            color: AppColors.textSecondary,
                          ),
                          color: AppColors.card,
                          onSelected: (value) {
                            if (value == 'pin') onPin();
                            if (value == 'edit') onEdit();
                            if (value == 'delete') onDelete();
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'pin',
                              child: Text(
                                data.isPinned ? 'Unpin' : 'Pin',
                                style: AppTextStyles.body,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Rename', style: AppTextStyles.body),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete', style: AppTextStyles.body),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          data.fileType.replaceAll('.', '').toUpperCase(),
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Created ${_formatCreatedAt(data.createdAt)}',
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCreatedAt(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;

    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '${parsed.year}-$month-$day';
  }
}

/// Loading placeholder shown while recent files are being read.
class _SavedItemSkeletonCard extends StatelessWidget {
  const _SavedItemSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 90,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonLine(widthFactor: 0.75),
                const SizedBox(height: 12),
                _SkeletonLine(widthFactor: 0.55),
                const SizedBox(height: 12),
                _SkeletonLine(widthFactor: 0.40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Single placeholder line used by saved item skeleton rows.
class _SkeletonLine extends StatelessWidget {
  final double widthFactor;

  const _SkeletonLine({required this.widthFactor});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

/// Import tab for browsing saved STALA files from the selected storage folder.
class _ImportTabView extends StatefulWidget {
  final GlobalKey storageTourKey;
  final GlobalKey importActionTourKey;
  final GlobalKey listTourKey;

  const _ImportTabView({
    super.key,
    required this.storageTourKey,
    required this.importActionTourKey,
    required this.listTourKey,
  });

  @override
  State<_ImportTabView> createState() => _ImportTabViewState();
}

class _ImportTabViewState extends State<_ImportTabView> {
  final StorageAccessService _storageAccessService =
      const StorageAccessService();

  StorageAccessInfo _storageInfo = const StorageAccessInfo(granted: false);
  String _defaultStoragePath = '';
  List<SavedItemData> _items = [];
  bool _isLoading = true;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _loadImportData();
  }

  Future<void> _loadImportData() async {
    setState(() {
      _isLoading = true;
    });

    final storageInfo = await _storageAccessService.getStorageFolder();
    final items = await RecentItemsRepository.getRecentItems();

    if (!mounted) return;

    setState(() {
      _storageInfo = storageInfo;
      _defaultStoragePath = storageInfo.displayName ?? '';
      _items = items;
      _isLoading = false;
    });
  }

  Future<void> _handleImportDocument() async {
    final storageInfo = await _storageAccessService.getStorageFolder();
    if (!storageInfo.granted) {
      final didPick = await _promptImportStoragePath();
      if (!didPick) return;
    }

    setState(() {
      _isImporting = true;
    });

    try {
      final document = await _storageAccessService.pickImportDocument();
      if (document == null) return;

      final name = document.fileName.toLowerCase();
      final ImportArchiveResult result;

      if (name.endsWith('.zip')) {
        result = await RecentItemsRepository.importZipBytes(
          bytes: document.bytes,
        );
      } else if (name.endsWith('.stala')) {
        result = await RecentItemsRepository.importStalaBytes(
          bytes: document.bytes,
          fileName: document.fileName,
        );
      } else {
        throw const FormatException('Choose a .stala or .zip file.');
      }

      await _loadImportData();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    } on DuplicateFileNameException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } on StoragePathRequiredException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $error')));
    } finally {
      if (!mounted) return;

      setState(() {
        _isImporting = false;
      });
    }
  }

  Future<bool> _promptImportStoragePath() async {
    final shouldPick = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Choose Import Folder', style: AppTextStyles.cardTitle),
          content: Text(
            'Choose the folder STALA will use to save imported and exported files.',
            style: AppTextStyles.bodySecondary,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: AppTextStyles.button.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.textPrimary,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text('Pick Folder', style: AppTextStyles.button),
            ),
          ],
        );
      },
    );

    if (shouldPick != true) return false;

    final info = await _storageAccessService.pickStorageFolder();
    if (!mounted) return false;

    setState(() {
      _storageInfo = info;
      _defaultStoragePath = info.displayName ?? '';
    });

    return info.granted;
  }

  Future<void> _openSavedItem(SavedItemData item) async {
    try {
      final session = await RecentItemsRepository.loadSessionFromItem(item);

      final generatedTabs = const GenerationService().generateAll(
        results: session.tablatureResults,
      );

      if (!mounted) return;

      final shouldRefresh = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ResultPage(
            session: session,
            generatedTabs: generatedTabs,
            sourceItem: item,
          ),
        ),
      );

      if (shouldRefresh == true) {
        await _loadImportData();
      }
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to import file: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('import-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Import',
          actionIcon: Icons.refresh_rounded,
          actionTooltip: 'Refresh',
          onActionTap: _loadImportData,
        ),
        const SizedBox(height: 14),
        TutorialService.showcase(
          key: widget.storageTourKey,
          title: 'Import Folder',
          description:
              'STALA uses this selected folder for imported files, saved projects, and exports.',
          child: _StorageLocationCard(
            storageInfo: _storageInfo,
            defaultStoragePath: _defaultStoragePath,
            isImporting: _isImporting,
            importActionTourKey: widget.importActionTourKey,
            onImport: _handleImportDocument,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: TutorialService.showcase(
            key: widget.listTourKey,
            title: 'Imported Files',
            description:
                'Available imported or saved STALA files appear here so you can reopen previous work.',
            child: RefreshIndicator(
              onRefresh: _loadImportData,
              child: _isLoading
                  ? ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: 4,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, __) => const _SavedItemSkeletonCard(),
                    )
                  : _items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 110),
                        Center(
                          child: Text(
                            'No local STALA files found.',
                            style: AppTextStyles.bodySecondary,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _items[index];

                        return _ImportFileTile(
                          data: item,
                          onTap: () => _openSavedItem(item),
                        );
                      },
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StorageLocationCard extends StatelessWidget {
  final StorageAccessInfo storageInfo;
  final String defaultStoragePath;
  final bool isImporting;
  final GlobalKey importActionTourKey;
  final VoidCallback onImport;

  const _StorageLocationCard({
    required this.storageInfo,
    required this.defaultStoragePath,
    required this.isImporting,
    required this.importActionTourKey,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final connected = storageInfo.granted;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              connected
                  ? Icons.folder_shared_outlined
                  : Icons.folder_open_outlined,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? 'Selected STALA Folder' : 'Storage Required',
                  style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  connected
                      ? (defaultStoragePath.isNotEmpty
                            ? defaultStoragePath
                            : 'Selected folder')
                      : 'Pick where STALA should save and import files.',
                  style: AppTextStyles.bodySecondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (connected) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Imports, saves, and exports use this folder.',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          TutorialService.showcase(
            key: importActionTourKey,
            title: 'Import Local File',
            description:
                'Select a .stala or supported archive from device storage.',
            child: TextButton(
              onPressed: isImporting ? null : onImport,
              child: isImporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Import',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.accent,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportFileTile extends StatelessWidget {
  final SavedItemData data;
  final VoidCallback onTap;

  const _ImportFileTile({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'ST',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.filePath,
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.file_open_outlined,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings tab with mutually exclusive panels for controls, permissions, and
/// app information.
class _SettingsTabView extends StatefulWidget {
  const _SettingsTabView({super.key});

  @override
  State<_SettingsTabView> createState() => _SettingsTabViewState();
}

class _SettingsTabViewState extends State<_SettingsTabView>
    with WidgetsBindingObserver {
  _SettingsPanel? _openPanel;

  bool _autoSaveEnabled = true;
  String _selectedSaveFormat = 'stala';
  int _recentFileLimit = AppSettingsRepository.minimumRecentFileLimit;
  String _tablatureExportOrientation = 'portrait';

  bool _cameraPermission = false;

  /// Tracks Android photo/gallery permission for source-image selection.
  bool _storagePermission = false;

  bool _notificationPermission = false;
  bool _accessibilityEnabled = false;
  StorageAccessInfo _storageAccessInfo = const StorageAccessInfo(
    granted: false,
  );

  int _aboutTapCount = 0;
  bool _showDebugControl = false;
  bool _debugPageEnabled = false;

  final DebugSettingsRepository _debugSettingsRepository =
      const DebugSettingsRepository();
  final StorageAccessService _storageAccessService =
      const StorageAccessService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPermissionStates();
    _loadDebugSettings();
    _loadAppSettings();
    _loadStorageAccessInfo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Refreshes permissions and storage folder state after returning to the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPermissionStates();
      _loadStorageAccessInfo();
    }
  }

  void _togglePanel(_SettingsPanel panel) {
    setState(() {
      _openPanel = _openPanel == panel ? null : panel;
    });
  }

  /// Reads current runtime permission states from the device.
  Future<void> _loadPermissionStates() async {
    final cameraStatus = await Permission.camera.status;
    final photosStatus = await Permission.photos.status;
    final notificationStatus = await Permission.notification.status;
    final accessibilityStatus =
        await AccessibilityServiceHelper.isAccessibilityEnabled();

    if (!mounted) return;

    setState(() {
      _cameraPermission = cameraStatus.isGranted;
      _storagePermission = photosStatus.isGranted;
      _notificationPermission = notificationStatus.isGranted;
      _accessibilityEnabled = accessibilityStatus;
    });
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();

    if (!mounted) return;

    setState(() {
      _cameraPermission = status.isGranted;
    });

    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  /// Requests gallery/photo access for image import.
  Future<void> _requestStoragePermission() async {
    final status = await Permission.photos.request();

    if (!mounted) return;

    setState(() {
      _storagePermission = status.isGranted;
    });

    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  Future<void> _loadStorageAccessInfo() async {
    final info = await _storageAccessService.getStorageFolder();

    if (!mounted) return;

    setState(() {
      _storageAccessInfo = info;
    });
  }

  Future<void> _chooseStorageFolder() async {
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(
            'Allow STALA File Access',
            style: AppTextStyles.cardTitle,
          ),
          content: Text(
            'Choose a folder STALA can use to save, import, export, rename, and delete .stala and .zip files.',
            style: AppTextStyles.bodySecondary,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: AppTextStyles.button),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.textPrimary,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text('Choose Folder', style: AppTextStyles.button),
            ),
          ],
        );
      },
    );

    if (shouldContinue != true) return;

    final info = await _storageAccessService.pickStorageFolder();

    if (!mounted) return;

    setState(() {
      _storageAccessInfo = info;
    });
  }

  Future<void> _resetStorageFolder() async {
    await _storageAccessService.clearStorageFolder();

    if (!mounted) return;

    setState(() {
      _storageAccessInfo = const StorageAccessInfo(granted: false);
    });
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.request();

    if (!mounted) return;

    setState(() {
      _notificationPermission = status.isGranted;
    });

    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  /// Opens app settings because runtime permissions cannot be revoked in-app.
  Future<void> _openPermissionSettings({required String permissionName}) async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(
            '$permissionName Permission',
            style: AppTextStyles.cardTitle,
          ),
          content: Text(
            '$permissionName permission cannot usually be disabled directly from inside the app. '
            'You will be redirected to App Settings to change it manually.',
            style: AppTextStyles.bodySecondary,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: AppTextStyles.button.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.textPrimary,
              ),
              onPressed: () async {
                Navigator.pop(context);
                await openAppSettings();
              },
              child: Text('Open Settings', style: AppTextStyles.button),
            ),
          ],
        );
      },
    );
  }

  /// Opens device accessibility settings for the STALA helper service.
  Future<void> _openAccessibilityPrompt() async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Enable Accessibility', style: AppTextStyles.cardTitle),
          content: Text(
            'Accessibility access cannot be granted from a normal permission popup. '
            'You will be redirected to device settings where you can enable it manually.',
            style: AppTextStyles.bodySecondary,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: AppTextStyles.button.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.textPrimary,
              ),
              onPressed: () async {
                Navigator.pop(context);
                await AccessibilityServiceHelper.openAccessibilitySettings();
                await Future.delayed(const Duration(milliseconds: 500));

                if (!mounted) return;
                final enabled =
                    await AccessibilityServiceHelper.isAccessibilityEnabled();

                if (!mounted) return;
                setState(() {
                  _accessibilityEnabled = enabled;
                });
              },
              child: Text('Open Settings', style: AppTextStyles.button),
            ),
          ],
        );
      },
    );
  }

  /// Loads the persisted developer debug-page toggle.
  Future<void> _loadDebugSettings() async {
    final enabled = await _debugSettingsRepository.isDebugPageEnabled();

    if (!mounted) return;

    setState(() {
      _debugPageEnabled = enabled;
      _showDebugControl = enabled;
    });
  }

  Future<void> _toggleDebugPage(bool value) async {
    await _debugSettingsRepository.setDebugPageEnabled(value);

    if (!mounted) return;

    setState(() {
      _debugPageEnabled = value;
      _showDebugControl = true;
    });

    RestartWidget.restartApp(context);
  }

  void _handleAboutTap() {
    _aboutTapCount++;

    if (_aboutTapCount >= 7) {
      setState(() {
        _showDebugControl = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Developer debug option unlocked.')),
      );
    }
  }

  Future<void> _loadAppSettings() async {
    final autoSaveEnabled = await _appSettingsRepository.getAutoSaveEnabled();
    final saveFormat = await _appSettingsRepository.getSaveFormat();
    final recentFileLimit = await _appSettingsRepository.getRecentFileLimit();
    final tablatureExportOrientation = await _appSettingsRepository
        .getTablatureExportOrientation();

    if (saveFormat != 'stala') {
      await _appSettingsRepository.setSaveFormat('stala');
    }

    if (!mounted) return;

    setState(() {
      _autoSaveEnabled = autoSaveEnabled;
      _selectedSaveFormat = 'stala';
      _recentFileLimit = recentFileLimit;
      _tablatureExportOrientation = tablatureExportOrientation;
    });
  }

  Future<void> _setRecentFileLimit(int value) async {
    final normalizedValue = value < AppSettingsRepository.minimumRecentFileLimit
        ? AppSettingsRepository.minimumRecentFileLimit
        : value;

    await _appSettingsRepository.setRecentFileLimit(normalizedValue);

    if (!mounted) return;

    setState(() {
      _recentFileLimit = normalizedValue;
    });
  }

  Future<void> _setTablatureExportOrientation(String value) async {
    await _appSettingsRepository.setTablatureExportOrientation(value);

    if (!mounted) return;

    setState(() {
      _tablatureExportOrientation = value == 'landscape'
          ? 'landscape'
          : 'portrait';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('settings-content'),
      physics: const BouncingScrollPhysics(),
      children: [
        const _SectionHeader(title: 'Settings'),
        const SizedBox(height: 14),

        // Controls panel.
        _ExpandableSettingsCard(
          title: 'Controls',
          subtitle: 'Adjust how STALA saves completed translations.',
          icon: Icons.tune_outlined,
          isExpanded: _openPanel == _SettingsPanel.controls,
          onTap: () => _togglePanel(_SettingsPanel.controls),
          child: Column(
            children: [
              SwitchListTile(
                value: _autoSaveEnabled,
                onChanged: (value) async {
                  await _appSettingsRepository.setAutoSaveEnabled(value);

                  if (!mounted) return;

                  setState(() {
                    _autoSaveEnabled = value;
                  });
                },
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.accent,
                title: Text('Enable Auto-save', style: AppTextStyles.body),
                subtitle: Text(
                  'Automatically keep each finished translation in your STALA library.',
                  style: AppTextStyles.bodySecondary,
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.description_outlined,
                  color: AppColors.accent,
                ),
                title: Text('Save format', style: AppTextStyles.body),
                subtitle: Text(
                  'STALA format only (.stala). ZIP and cloud save controls can be added when those workflows are ready.',
                  style: AppTextStyles.bodySecondary,
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    _selectedSaveFormat.toUpperCase(),
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.history_rounded,
                  color: AppColors.accent,
                ),
                title: Text('Recent file limit', style: AppTextStyles.body),
                subtitle: Text(
                  'Choose how many recent items Home shows before View all.',
                  style: AppTextStyles.bodySecondary,
                ),
                trailing: _RecentLimitStepper(
                  value: _recentFileLimit,
                  minimumValue: AppSettingsRepository.minimumRecentFileLimit,
                  onDecrease: () => _setRecentFileLimit(_recentFileLimit - 1),
                  onIncrease: () => _setRecentFileLimit(_recentFileLimit + 1),
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.screen_rotation_alt_outlined,
                  color: AppColors.accent,
                ),
                title: Text(
                  'Tablature export orientation',
                  style: AppTextStyles.body,
                ),
                subtitle: Text(
                  'Choose the layout used when exporting tablature PNG and PDF files.',
                  style: AppTextStyles.bodySecondary,
                ),
                trailing: _OrientationSegmentedControl(
                  value: _tablatureExportOrientation,
                  onChanged: _setTablatureExportOrientation,
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.replay_circle_filled_outlined,
                  color: AppColors.accent,
                ),
                title: Text('Reset tutorials', style: AppTextStyles.body),
                subtitle: Text(
                  'Show first-visit page tours again on supported screens.',
                  style: AppTextStyles.bodySecondary,
                ),
                trailing: TextButton(
                  onPressed: () async {
                    await TutorialService.resetTutorials();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Tutorials reset.')),
                    );
                  },
                  child: Text(
                    'Reset',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
              // Hidden developer option unlocked from the About row.
              if (_showDebugControl) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _debugPageEnabled,
                  onChanged: _toggleDebugPage,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.accent,
                  title: Text('Enable Debug Page', style: AppTextStyles.body),
                  subtitle: Text(
                    _debugPageEnabled
                        ? 'Debug page will appear before the Result page.'
                        : 'Processing will go directly to the Result page.',
                    style: AppTextStyles.bodySecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Permissions panel.
        _ExpandableSettingsCard(
          title: 'Permissions',
          subtitle: 'Review and control app access permissions.',
          icon: Icons.lock_open_outlined,
          isExpanded: _openPanel == _SettingsPanel.permissions,
          onTap: () => _togglePanel(_SettingsPanel.permissions),
          child: Column(
            children: [
              SwitchListTile(
                value: _cameraPermission,
                onChanged: (value) async {
                  if (value) {
                    await _requestCameraPermission();
                  } else {
                    await _openPermissionSettings(permissionName: 'Camera');
                  }
                },
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.accent,
                title: Text(
                  'Camera Access Permission',
                  style: AppTextStyles.body,
                ),
                subtitle: Text(
                  'Required for capturing music sheet images.',
                  style: AppTextStyles.bodySecondary,
                ),
              ),
              SwitchListTile(
                value: _storagePermission,
                onChanged: (value) async {
                  if (value) {
                    await _requestStoragePermission();
                  } else {
                    await _openPermissionSettings(
                      permissionName: 'Gallery / Photos',
                    );
                  }
                },
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.accent,
                title: Text(
                  'Gallery / Photos Permission',
                  style: AppTextStyles.body,
                ),
                subtitle: Text(
                  'Required for choosing source images from the gallery.',
                  style: AppTextStyles.bodySecondary,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _storageAccessInfo.granted
                      ? Icons.folder_shared_outlined
                      : Icons.folder_open_outlined,
                  color: AppColors.accent,
                ),
                title: Text('STALA Storage Folder', style: AppTextStyles.body),
                subtitle: Text(
                  _storageAccessInfo.granted
                      ? (_storageAccessInfo.displayName ?? 'Selected folder')
                      : 'Choose a folder for visible .stala, .zip, and PNG exports.',
                  style: AppTextStyles.bodySecondary,
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    if (_storageAccessInfo.granted)
                      TextButton(
                        onPressed: _resetStorageFolder,
                        child: Text(
                          'Reset',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    TextButton(
                      onPressed: _chooseStorageFolder,
                      child: Text(
                        _storageAccessInfo.granted ? 'Change' : 'Choose',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                value: _notificationPermission,
                onChanged: (value) async {
                  if (value) {
                    await _requestNotificationPermission();
                  } else {
                    await _openPermissionSettings(
                      permissionName: 'Notification',
                    );
                  }
                },
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.accent,
                title: Text(
                  'Notification Permission',
                  style: AppTextStyles.body,
                ),
                subtitle: Text(
                  'Required for save status and reminder notifications.',
                  style: AppTextStyles.bodySecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Information panel.
        _ExpandableSettingsCard(
          title: 'Information',
          subtitle: 'Read the app version and project background.',
          icon: Icons.info_outline,
          isExpanded: _openPanel == _SettingsPanel.information,
          onTap: () => _togglePanel(_SettingsPanel.information),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoDetailRow(label: 'Version', value: 'STALA v2.0.0'),
              SizedBox(height: 10),
              _InfoDetailRow(
                label: 'Description',
                value:
                    'STALA helps translate piano grand staff notation into guitar tablature so musicians can review, save, and reopen playable guitar-focused results.',
              ),
              SizedBox(height: 10),
              GestureDetector(
                onTap: _handleAboutTap,
                child: const _InfoDetailRow(
                  label: 'About Us',
                  value:
                      'STALA is developed by a student team building practical tools for music learners and guitar players who need a clearer path from sheet music to tablature.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  final AppSettingsRepository _appSettingsRepository =
      const AppSettingsRepository();
}

enum _SettingsPanel { controls, permissions, information }

/// Shared title row with an optional trailing text action.
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionText;
  final IconData? actionIcon;
  final String? actionTooltip;
  final VoidCallback? onActionTap;

  const _SectionHeader({
    required this.title,
    this.actionText,
    this.actionIcon,
    this.actionTooltip,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: AppTextStyles.sectionTitle.copyWith(fontSize: 22)),
        const SizedBox(width: 10),
        Container(
          width: 18,
          height: 3,
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const Spacer(),
        if (actionIcon != null)
          IconButton(
            tooltip: actionTooltip,
            onPressed: onActionTap,
            icon: Icon(actionIcon, size: 20),
            color: AppColors.accent,
            disabledColor: AppColors.textMuted.withOpacity(0.55),
            visualDensity: VisualDensity.compact,
          )
        else if (actionText != null && actionText!.isNotEmpty)
          GestureDetector(
            onTap: onActionTap,
            child: Text(
              actionText!,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

class _RecentLimitStepper extends StatelessWidget {
  final int value;
  final int minimumValue;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _RecentLimitStepper({
    required this.value,
    required this.minimumValue,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    final canDecrease = value > minimumValue;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Decrease recent limit',
            onPressed: canDecrease ? onDecrease : null,
            icon: const Icon(Icons.remove_rounded, size: 18),
            color: AppColors.accent,
            disabledColor: AppColors.textMuted.withOpacity(0.55),
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Increase recent limit',
            onPressed: onIncrease,
            icon: const Icon(Icons.add_rounded, size: 18),
            color: AppColors.accent,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _OrientationSegmentedControl extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _OrientationSegmentedControl({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _OrientationButton(
            icon: Icons.stay_current_portrait_rounded,
            tooltip: 'Portrait',
            isSelected: value != 'landscape',
            onTap: () => onChanged('portrait'),
          ),
          _OrientationButton(
            icon: Icons.stay_current_landscape_rounded,
            tooltip: 'Landscape',
            isSelected: value == 'landscape',
            onTap: () => onChanged('landscape'),
          ),
        ],
      ),
    );
  }
}

class _OrientationButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  const _OrientationButton({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 34,
          height: 32,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Accordion card used by Settings panels.
class _ExpandableSettingsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isExpanded;
  final VoidCallback onTap;
  final Widget child;

  const _ExpandableSettingsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isExpanded,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppColors.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: AppTextStyles.bodySecondary.copyWith(
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: child,
            ),
          ],
        ],
      ),
    );
  }
}

/// Label-value row used in the Information settings panel.
class _InfoDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: AppTextStyles.body.copyWith(height: 1.5),
        children: [
          TextSpan(
            text: '$label: ',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: value,
            style: AppTextStyles.bodySecondary.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// FOOTER
// -----------------------------------------------------------------------------

/// Bottom navigation with an animated camera action.
class _PanelFooter extends StatelessWidget {
  final PanelTab selectedTab;
  final Animation<double> cameraFloatAnimation;
  final GlobalKey importNavTourKey;
  final GlobalKey cameraNavTourKey;
  final GlobalKey homeNavTourKey;
  final ValueChanged<PanelTab> onTabSelected;

  const _PanelFooter({
    required this.selectedTab,
    required this.cameraFloatAnimation,
    required this.importNavTourKey,
    required this.cameraNavTourKey,
    required this.homeNavTourKey,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: SizedBox(
        height: 82,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 68,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  border: Border.all(color: Colors.white.withOpacity(0.04)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: TutorialService.showcase(
                          key: importNavTourKey,
                          title: 'Import Tab',
                          description:
                              'Open existing STALA files, saved projects, or supported local files.',
                          child: _NavItem(
                            icon: Icons.drive_folder_upload_outlined,
                            label: 'Import',
                            isSelected: selectedTab == PanelTab.search,
                            onTap: () => onTabSelected(PanelTab.search),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 86),
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: TutorialService.showcase(
                          key: homeNavTourKey,
                          title: 'Home Tab',
                          description:
                              'Return to the main starting area and recent projects.',
                          child: _NavItem(
                            icon: Icons.home,
                            label: 'Home',
                            isSelected: selectedTab == PanelTab.home,
                            onTap: () => onTabSelected(PanelTab.home),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Animated camera action floating over the navigation bar.
            AnimatedBuilder(
              animation: cameraFloatAnimation,
              builder: (context, child) {
                return Positioned(
                  top: cameraFloatAnimation.value,
                  left: 0,
                  right: 0,
                  child: Center(child: child!),
                );
              },
              child: TutorialService.showcase(
                key: cameraNavTourKey,
                title: 'Camera Workflow',
                description:
                    'Capture a new sheet music image and begin the STALA processing workflow.',
                targetShapeBorder: const CircleBorder(),
                child: GestureDetector(
                  onTap: () => onTabSelected(PanelTab.camera),
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFA36A), Color(0xFFFF6F4E)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accentSoft.withOpacity(0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.18),
                        ),
                      ),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        color: AppColors.textPrimary,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable bottom navigation item.
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = AppColors.accent;
    final inactiveColor = AppColors.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? activeColor : inactiveColor,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: isSelected ? activeColor : inactiveColor,
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
