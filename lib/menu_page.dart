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
      //
    }
  }
}

/// Defines the available bottom navigation tabs.
enum PanelTab { search, camera, home, settings }

/// Main screen for Panel 01.
///
/// Structure:
/// 1. Header  -> logo/title + profile/cloud/local icon area
/// 2. Mid     -> sliding content area based on selected navbar tab
/// 3. Footer  -> bottom navigation bar + animated camera button
class MainPanel01Page extends StatefulWidget {
  const MainPanel01Page({super.key});

  @override
  State<MainPanel01Page> createState() => _MainPanel01PageState();
}

class _MainPanel01PageState extends State<MainPanel01Page>
    with SingleTickerProviderStateMixin {
  /// The currently selected tab.
  ///
  /// Camera behaves differently from the other tabs, so the displayed
  /// content in the mid section is controlled only by search/home/settings.
  PanelTab _selectedTab = PanelTab.home;

  late final AnimationController _cameraButtonController;
  late final Animation<double> _cameraFloatAnimation;

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
    });
  }

  /// Opens the camera section.
  Future<void> _openCameraPanel() async {
    final shouldRefreshHome = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const CameraPanelPage()));

    if (!mounted) return;

    if (shouldRefreshHome == true) {
      setState(() {
        _selectedTab = PanelTab.home;
      });
    }
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

              // =========================
              // HEADER SECTION
              // =========================
              const _PanelHeader(),

              const SizedBox(height: 18),

              // =========================
              // MID SECTION
              // =========================
              // Expanded so the content area grows and leaves the footer at bottom.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _PanelMidContent(selectedTab: _selectedTab),
                ),
              ),

              const SizedBox(height: 12),

              // =========================
              // FOOTER SECTION
              // =========================
              _PanelFooter(
                selectedTab: _selectedTab,
                cameraFloatAnimation: _cameraFloatAnimation,
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

/// Top header section.
///
/// Left side:
/// - logo placeholder
/// - title placeholder
/// - subtitle text
///
/// Right side:
/// - profile / sync / saving icon placeholder
class _PanelHeader extends StatelessWidget {
  const _PanelHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Image.asset(
              'assets/images/stala_logo_icon.png',
              width: 16,
              height: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
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
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.card,
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: const Icon(
              Icons.person_outline,
              color: AppColors.textSecondary,
              size: 18,
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

/// Middle content area.
///
/// Uses [AnimatedSwitcher] + [SlideTransition] to imitate a card layout sliding
/// effect whenever the navbar changes the active content.
class _PanelMidContent extends StatelessWidget {
  final PanelTab selectedTab;

  const _PanelMidContent({required this.selectedTab});

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
        return const _ImportTabView(key: ValueKey('import-tab'));
      case PanelTab.home:
        return const _HomeTabView(key: ValueKey('home-tab'));
      case PanelTab.settings:
        return const _SettingsTabView(key: ValueKey('settings-tab'));
      case PanelTab.camera:
        return const SizedBox.shrink();
    }
  }
}

/// ============================================================
/// MID SECTION CONTENT
/// ============================================================
/// This file contains:
/// - Home tab content
/// - Search tab content
/// - Settings tab content
///
/// Notes:
/// - The placeholder list in Home is TEMPORARY only.
/// - Once the save/load section of the application is functional,
///   replace `_temporaryPlaceholderItems` with real saved file data.
/// ============================================================

/// ------------------------------------------------------------
/// HOME TAB CONTENT
/// ------------------------------------------------------------
/// Displays recently accessed or recently added files.
///
/// Current temporary behavior:
/// - Uses 10 placeholder entries
/// - Shows only 5 initially
/// - "View All" expands the full list
///
/// Future behavior:
/// - Replace placeholder list with actual saved transposed music sheets
class _HomeTabView extends StatefulWidget {
  const _HomeTabView({super.key});

  @override
  State<_HomeTabView> createState() => _HomeTabViewState();
}

class _HomeTabViewState extends State<_HomeTabView> {
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

    if (!mounted) return;

    setState(() {
      _items = items;
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
  final Set<String> _selectedItemKeys = <String>{};

  List<SavedItemData> get _visibleItems {
    return _showAll ? _items : _items.take(4).toList();
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

                await RecentItemsRepository.renameItem(item, updatedTitle);

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
      _isSelectionMode = !_isSelectionMode;
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
      }
    });
  }

  void _selectAllVisible() {
    setState(() {
      _isSelectionMode = true;
      _selectedItemKeys
        ..clear()
        ..addAll(_visibleItems.map(_itemKey));
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
          builder: (_) =>
              ResultPage(session: session, generatedTabs: generatedTabs),
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
        _SectionHeader(
          title: 'Recent',
          actionText: _isSelectionMode
              ? 'Cancel'
              : _showAll
              ? 'Show Less'
              : 'View All',
          onActionTap: () {
            if (_isSelectionMode) {
              _toggleSelectionMode();
              return;
            }

            setState(() {
              _showAll = !_showAll;
            });
          },
        ),
        const SizedBox(height: 14),
        if (!_isLoading && _items.isNotEmpty) ...[
          _HomeBulkActionBar(
            isSelectionMode: _isSelectionMode,
            selectedCount: _selectedItemKeys.length,
            onSelect: _toggleSelectionMode,
            onSelectAll: _selectAllVisible,
            onDelete: _handleBulkDelete,
            onExport: _handleBulkExport,
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
            isSelectionMode ? '$selectedCount selected' : 'Bulk actions',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: isSelectionMode ? onSelectAll : onSelect,
            icon: Icon(
              isSelectionMode
                  ? Icons.select_all_rounded
                  : Icons.checklist_rounded,
              size: 18,
            ),
            label: Text(isSelectionMode ? 'All' : 'Select'),
          ),
          IconButton(
            tooltip: 'Export selected',
            onPressed: hasSelection ? onExport : null,
            icon: const Icon(Icons.archive_outlined),
            color: AppColors.accent,
          ),
          IconButton(
            tooltip: 'Delete selected',
            onPressed: hasSelection ? onDelete : null,
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppColors.warning,
          ),
        ],
      ),
    );
  }
}

/// Card widget for each saved file item in Home tab.
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 90,
              alignment: Alignment.center,
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
                  : Text(
                      data.fileType.replaceAll('.', '').toUpperCase(),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.sectionTitle.copyWith(
                        fontSize: 24,
                        letterSpacing: 1,
                        color: AppColors.accent,
                      ),
                    ),
            ),
            const SizedBox(width: 16),
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
                                text: 'Title: ',
                                style: AppTextStyles.body.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
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
                  Text(
                    'Date created: ${data.createdAt}',
                    style: AppTextStyles.body,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Modified: ${data.subtitle}',
                    style: AppTextStyles.bodySecondary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

class _ImportTabView extends StatefulWidget {
  const _ImportTabView({super.key});

  @override
  State<_ImportTabView> createState() => _ImportTabViewState();
}

class _ImportTabViewState extends State<_ImportTabView> {
  final StorageAccessService _storageAccessService =
      const StorageAccessService();

  StorageAccessInfo _storageInfo = const StorageAccessInfo(granted: false);
  List<SavedItemData> _items = [];
  bool _isLoading = true;

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
      _items = items;
      _isLoading = false;
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
      _storageInfo = info;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          info.granted
              ? 'Storage folder connected.'
              : 'No folder selected. STALA will keep using app storage.',
        ),
      ),
    );
  }

  Future<void> _openSavedItem(SavedItemData item) async {
    try {
      final session = await RecentItemsRepository.loadSessionFromItem(item);

      final generatedTabs = const GenerationService().generateAll(
        results: session.tablatureResults,
      );

      if (!mounted) return;

      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ResultPage(session: session, generatedTabs: generatedTabs),
        ),
      );
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
          actionText: 'Refresh',
          onActionTap: _loadImportData,
        ),
        const SizedBox(height: 14),
        _StorageLocationCard(
          storageInfo: _storageInfo,
          onChooseFolder: _chooseStorageFolder,
        ),
        const SizedBox(height: 10),
        Expanded(
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
      ],
    );
  }
}

class _StorageLocationCard extends StatelessWidget {
  final StorageAccessInfo storageInfo;
  final VoidCallback onChooseFolder;

  const _StorageLocationCard({
    required this.storageInfo,
    required this.onChooseFolder,
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
                  connected ? 'STALA Storage Connected' : 'App Storage',
                  style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  connected
                      ? (storageInfo.displayName ?? 'Selected folder')
                      : 'Choose a folder to make exports visible outside the app.',
                  style: AppTextStyles.bodySecondary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onChooseFolder,
            child: Text(
              connected ? 'Change' : 'Choose',
              style: AppTextStyles.caption.copyWith(color: AppColors.accent),
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

/// ------------------------------------------------------------
/// SETTINGS TAB CONTENT
/// ------------------------------------------------------------
/// Accordion / dropdown behavior:
/// - Only one panel can stay open at a time
/// - Opening one closes the others
class _SettingsTabView extends StatefulWidget {
  const _SettingsTabView({super.key});

  @override
  State<_SettingsTabView> createState() => _SettingsTabViewState();
}

class _SettingsTabViewState extends State<_SettingsTabView>
    with WidgetsBindingObserver {
  _SettingsPanel? _openPanel;

  bool _autoSaveEnabled = true;
  bool _autoSaveToCloud = false;
  String _selectedSaveFormat = 'stala';

  /// -------------------------------------
  /// PERMISSION STATES
  /// -------------------------------------
  bool _cameraPermission = false;

  /// Uses gallery/media image permission.
  /// Variable name kept as `_storagePermission` so UI labels still match.
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

  /// Refresh permission states after returning from settings.
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

  /// Load current permission states from the device.
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

  /// Gallery / photo access permission.
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

  /// Open app settings when user tries to turn OFF a permission.
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

  /// Accessibility is not a standard runtime permission.
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

  /// This load the debug settings
  Future<void> _loadDebugSettings() async {
    final enabled = await _debugSettingsRepository.isDebugPageEnabled();

    if (!mounted) return;

    setState(() {
      _debugPageEnabled = enabled;
      _showDebugControl = enabled;
    });
  }

  Future<void> _toggleDebugPage(bool value) async {
    // 1. Save setting (persistent)
    await _debugSettingsRepository.setDebugPageEnabled(value);

    if (!mounted) return;

    // 2. Update UI state
    setState(() {
      _debugPageEnabled = value;
      _showDebugControl = true;
    });

    // 3. Restart app (apply change globally)
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
    final autoSaveToCloud = await _appSettingsRepository.getAutoSaveToCloud();
    final saveFormat = await _appSettingsRepository.getSaveFormat();

    if (!mounted) return;

    setState(() {
      _autoSaveEnabled = autoSaveEnabled;
      _autoSaveToCloud = autoSaveToCloud;
      _selectedSaveFormat = saveFormat;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('settings-content'),
      physics: const BouncingScrollPhysics(),
      children: [
        const _SectionHeader(title: 'Settings', actionText: 'Manage'),
        const SizedBox(height: 14),

        /// Controls
        _ExpandableSettingsCard(
          title: 'Controls',
          subtitle: 'Adjust save behavior and content output settings.',
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
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      'Saved content format',
                      style: AppTextStyles.body,
                    ),
                  ),
                  Opacity(
                    opacity: _autoSaveEnabled ? 1.0 : 0.5,
                    child: IgnorePointer(
                      ignoring: !_autoSaveEnabled,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedSaveFormat,
                          dropdownColor: AppColors.backgroundSecondary,
                          underline: const SizedBox(),
                          iconEnabledColor: AppColors.textPrimary,
                          style: AppTextStyles.body,
                          items: const [
                            DropdownMenuItem(value: 'zip', child: Text('zip')),
                            DropdownMenuItem(
                              value: 'stala',
                              child: Text('stala'),
                            ),
                          ],
                          onChanged: (value) async {
                            if (value == null) return;

                            await _appSettingsRepository.setSaveFormat(value);

                            if (!mounted) return;

                            setState(() {
                              _selectedSaveFormat = value;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _autoSaveToCloud,
                onChanged: _autoSaveEnabled
                    ? (value) async {
                        await _appSettingsRepository.setAutoSaveToCloud(value);

                        if (!mounted) return;

                        setState(() {
                          _autoSaveToCloud = value;
                        });
                      }
                    : null, // disables switch
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.accent,
                title: Text(
                  'Enable Auto-save to Cloud',
                  style: AppTextStyles.body,
                ),
              ),

              // DEBUG SWITCH (CORRECT POSITION)
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

        /// Permissions
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
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Accessibility Access', style: AppTextStyles.body),
                subtitle: Text(
                  _accessibilityEnabled
                      ? 'Accessibility service is enabled.'
                      : 'Open device settings to manually enable accessibility support.',
                  style: AppTextStyles.bodySecondary,
                ),
                trailing: TextButton(
                  onPressed: _openAccessibilityPrompt,
                  child: Text(
                    _accessibilityEnabled ? 'Enabled' : 'Grant',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        /// Information
        _ExpandableSettingsCard(
          title: 'Information',
          subtitle: 'Read the application version, description, and about us.',
          icon: Icons.info_outline,
          isExpanded: _openPanel == _SettingsPanel.information,
          onTap: () => _togglePanel(_SettingsPanel.information),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoDetailRow(label: 'Version', value: 'stala-version-1'),
              SizedBox(height: 10),
              _InfoDetailRow(
                label: 'Description',
                value:
                    'A musical application for a GrandStaff (Piano) to Tablature (Guitar) translation.',
              ),
              SizedBox(height: 10),
              GestureDetector(
                onTap: _handleAboutTap,
                child: const _InfoDetailRow(
                  label: 'About Us',
                  value:
                      'A team of college students developing STALA as a music translation support application.',
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

/// ------------------------------------------------------------
/// SHARED SECTION HEADER
/// ------------------------------------------------------------
/// Only define this ONCE.
/// Your old code had duplicate `_SectionHeader` declarations.
class _SectionHeader extends StatelessWidget {
  final String title;
  final String actionText;
  final VoidCallback? onActionTap;

  const _SectionHeader({
    required this.title,
    required this.actionText,
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
        GestureDetector(
          onTap: onActionTap,
          child: Text(
            actionText,
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

/// ------------------------------------------------------------
/// EXPANDABLE SETTINGS CARD
/// ------------------------------------------------------------
/// Used by Settings tab for Controls / Permissions / Information
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

/// ------------------------------------------------------------
/// INFORMATION DETAIL ROW
/// ------------------------------------------------------------
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

/// Bottom navigation/footer section.
///
/// Includes:
/// - Search button
/// - Center floating camera button
/// - Home button
/// - Settings button
class _PanelFooter extends StatelessWidget {
  final PanelTab selectedTab;
  final Animation<double> cameraFloatAnimation;
  final ValueChanged<PanelTab> onTabSelected;

  const _PanelFooter({
    required this.selectedTab,
    required this.cameraFloatAnimation,
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
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavItem(
                      icon: Icons.drive_folder_upload_outlined,
                      label: 'Import',
                      isSelected: selectedTab == PanelTab.search,
                      onTap: () => onTabSelected(PanelTab.search),
                    ),
                    const SizedBox(width: 60),
                    _NavItem(
                      icon: Icons.home,
                      label: 'Home',
                      isSelected: selectedTab == PanelTab.home,
                      onTap: () => onTabSelected(PanelTab.home),
                    ),
                    _NavItem(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      isSelected: selectedTab == PanelTab.settings,
                      onTap: () => onTabSelected(PanelTab.settings),
                    ),
                  ],
                ),
              ),
            ),

            /// Animated special camera button.
            AnimatedBuilder(
              animation: cameraFloatAnimation,
              builder: (context, child) {
                return Positioned(
                  top: cameraFloatAnimation.value,
                  left: MediaQuery.of(context).size.width * 0.29,
                  child: child!,
                );
              },
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
                      border: Border.all(color: Colors.white.withOpacity(0.18)),
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
          ],
        ),
      ),
    );
  }
}

/// Small reusable nav item widget.
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
