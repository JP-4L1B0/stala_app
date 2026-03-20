import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'camera_panel.dart';

class AccessibilityServiceHelper {
  static const MethodChannel _channel =
  MethodChannel('stala_app/accessibility');

  static Future<bool> isAccessibilityEnabled() async {
    try {
      final bool? result =
      await _channel.invokeMethod<bool>('isAccessibilityEnabled');
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
enum PanelTab {
  search,
  camera,
  home,
  settings,
}

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

    /// Subtle up-and-down floating animation for the camera button.
    _cameraButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _cameraFloatAnimation = Tween<double>(begin: -2, end: 4).animate(
      CurvedAnimation(
        parent: _cameraButtonController,
        curve: Curves.easeInOut,
      ),
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

  /// Opens Panel 02, which now contains the live camera workflow.
  void _openCameraPanel() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CameraPanelPage(),
      ),
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
                Color(0xFF0B162B),
                Color(0xFF081222),
                Color(0xFF05101D),
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
              color: const Color(0xFF1C2940),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Image.asset(
              'assets/images/stala_logo_icon.png',
              width: 16,
              height: 16,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STALA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Your memories, secured',
                  style: TextStyle(
                    color: Color(0xFFA0AFC4),
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
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
              color: const Color(0xFF1C2940),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
              ),
            ),
            child: const Icon(
              Icons.person_outline,
              color: Color(0xFFB8C4D6),
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
          child: SlideTransition(
            position: offsetAnimation,
            child: child,
          ),
        );
      },
      child: _buildSelectedContent(),
    );
  }

  Widget _buildSelectedContent() {
    switch (selectedTab) {
      case PanelTab.search:
        return const _SearchTabView(key: ValueKey('search-tab'));
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
  bool _showAll = false;

  /// TEMPORARY PLACEHOLDER DATA
  ///
  /// Remove this once the actual save system is ready.
  late final List<SavedItemData> _temporaryPlaceholderItems = List.generate(
    10,
        (index) => SavedItemData(
      fileTitle: 'Unnamed_${(index + 1).toString().padLeft(2, '0')}',
      dateCreated: _generatePlaceholderDate(index),
      modifiedText: _generateModifiedText(index),
    ),
  );

  List<SavedItemData> get _visibleItems {
    return _showAll
        ? _temporaryPlaceholderItems
        : _temporaryPlaceholderItems.take(4).toList();
  }

  static String _generatePlaceholderDate(int index) {
    final now = DateTime.now().subtract(Duration(days: index));
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year.toString();
    return '$day/$month/$year';
  }

  static String _generateModifiedText(int index) {
    if (index < 5) {
      return '${(index + 1) * 7} min ago';
    }
    return '${index - 3} h ago';
  }

  void _handleRename(int index) {
    final controller = TextEditingController(
      text: _temporaryPlaceholderItems[index].fileTitle,
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename File'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Enter new title',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final updatedTitle = controller.text.trim();

                if (updatedTitle.isNotEmpty) {
                  setState(() {
                    _temporaryPlaceholderItems[index] =
                        _temporaryPlaceholderItems[index].copyWith(
                          fileTitle: updatedTitle,
                        );
                  });
                }

                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('home-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Recent',
          actionText: _showAll ? 'Show Less' : 'View All',
          onActionTap: () {
            setState(() {
              _showAll = !_showAll;
            });
          },
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            itemCount: _visibleItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              return SavedListCard(
                data: _visibleItems[index],
                onEdit: () => _handleRename(index),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Data model for saved/transposed sheet items.
/// Future-ready for local or cloud-based real saved data.
class SavedItemData {
  final String fileTitle;
  final String dateCreated;
  final String modifiedText;

  const SavedItemData({
    required this.fileTitle,
    required this.dateCreated,
    required this.modifiedText,
  });

  SavedItemData copyWith({
    String? fileTitle,
    String? dateCreated,
    String? modifiedText,
  }) {
    return SavedItemData(
      fileTitle: fileTitle ?? this.fileTitle,
      dateCreated: dateCreated ?? this.dateCreated,
      modifiedText: modifiedText ?? this.modifiedText,
    );
  }
}

/// Card widget for each saved file item in Home tab.
class SavedListCard extends StatelessWidget {
  final SavedItemData data;
  final VoidCallback onEdit;

  const SavedListCard({
    super.key,
    required this.data,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF566487),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// Large left icon/text
          Container(
            width: 90,
            alignment: Alignment.center,
            child: const Text(
              'Saved',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 16),

          /// Right details column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.4,
                          ),
                          children: [
                            const TextSpan(text: 'Title: '),
                            TextSpan(
                              text: data.fileTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onEdit,
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Edit',
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Date created: ${data.dateCreated}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Modified: ${data.modifiedText}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.35,
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

/// ------------------------------------------------------------
/// SEARCH TAB CONTENT
/// ------------------------------------------------------------
class _SearchTabView extends StatelessWidget {
  const _SearchTabView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('search-content'),
      physics: const BouncingScrollPhysics(),
      children: const [
        _SectionHeader(
          title: 'Local and Online',
          actionText: 'Browse',
        ),
        SizedBox(height: 14),
        _InfoCard(
          title: 'Local Storage',
          subtitle: 'Browse files stored directly on this device.',
          icon: Icons.phone_android_outlined,
        ),
        SizedBox(height: 10),
        _InfoCard(
          title: 'Cloud Backup',
          subtitle: 'Open synced documents and online backups.',
          icon: Icons.cloud_outlined,
        ),
        SizedBox(height: 10),
        _InfoCard(
          title: 'Shared Vaults',
          subtitle: 'Access folders shared between local and cloud sources.',
          icon: Icons.folder_shared_outlined,
        ),
      ],
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPermissionStates();
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
  Future<void> _openPermissionSettings({
    required String permissionName,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('$permissionName Permission'),
          content: Text(
            '$permissionName permission cannot usually be disabled directly from inside the app. '
                'You will be redirected to App Settings to change it manually.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  /// Accessibility is not a standard runtime permission.
  Future<void> _openAccessibilityPrompt() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enable Accessibility'),
          content: const Text(
            'Accessibility access cannot be granted from a normal permission popup. '
                'You will be redirected to device settings where you can enable it manually.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
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
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('settings-content'),
      physics: const BouncingScrollPhysics(),
      children: [
        const _SectionHeader(
          title: 'Settings',
          actionText: 'Manage',
        ),
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
                onChanged: (value) {
                  setState(() {
                    _autoSaveEnabled = value;
                  });
                },
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Enable Auto-save',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Text(
                      'Saved content format',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF20304A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedSaveFormat,
                      dropdownColor: const Color(0xFF20304A),
                      underline: const SizedBox(),
                      iconEnabledColor: Colors.white,
                      style: const TextStyle(color: Colors.white),
                      items: const [
                        DropdownMenuItem(
                          value: 'zip',
                          child: Text('zip'),
                        ),
                        DropdownMenuItem(
                          value: 'stala',
                          child: Text('stala'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedSaveFormat = value;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _autoSaveToCloud,
                onChanged: (value) {
                  setState(() {
                    _autoSaveToCloud = value;
                  });
                },
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Enable Auto-save to Cloud',
                  style: TextStyle(color: Colors.white),
                ),
              ),
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
                    await _openPermissionSettings(
                      permissionName: 'Camera',
                    );
                  }
                },
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Camera Access Permission',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Required for capturing music sheet images.',
                  style: TextStyle(color: Color(0xFFA9B6C8)),
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
                title: const Text(
                  'Storage Access Permission',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Required for gallery photo access and local output access.',
                  style: TextStyle(color: Color(0xFFA9B6C8)),
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
                title: const Text(
                  'Notification Permission',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Required for save status and reminder notifications.',
                  style: TextStyle(color: Color(0xFFA9B6C8)),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Accessibility Access',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _accessibilityEnabled
                      ? 'Accessibility service is enabled.'
                      : 'Open device settings to manually enable accessibility support.',
                  style: const TextStyle(color: Color(0xFFA9B6C8)),
                ),
                trailing: TextButton(
                  onPressed: _openAccessibilityPrompt,
                  child: Text(_accessibilityEnabled ? 'Enabled' : 'Grant'),
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
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// CHANGE APP VERSION HERE
              /// Example:
              /// const String appVersion = 'stala-version-1';
              _InfoDetailRow(
                label: 'Version',
                value: 'stala-version-1',
              ),
              SizedBox(height: 10),
              _InfoDetailRow(
                label: 'Description',
                value:
                'A musical application for a GrandStaff (Piano) to Tablature (Guitar) translation.',
              ),
              SizedBox(height: 10),
              _InfoDetailRow(
                label: 'About Us',
                value:
                'A team of college students developing STALA as a music translation support application.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _SettingsPanel {
  controls,
  permissions,
  information,
}

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
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 18,
          height: 3,
          decoration: BoxDecoration(
            color: const Color(0xFF20304A),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onActionTap,
          child: Text(
            actionText,
            style: const TextStyle(
              color: Color(0xFFFFB264),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// ------------------------------------------------------------
/// SHARED INFO CARD
/// ------------------------------------------------------------
/// Used in Search tab cards.
class _InfoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _InfoCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16243B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF20304A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFFFF8A2B)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFA9B6C8),
                    fontSize: 12,
                    height: 1.4,
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
        color: const Color(0xFF16243B),
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
                    color: const Color(0xFF20304A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: const Color(0xFFFF8A2B)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFFA9B6C8),
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
                    color: Colors.white70,
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
                color: const Color(0xFF20304A),
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

  const _InfoDetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          height: 1.5,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: value),
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
                  color: const Color(0xFF091425),
                  border: Border.all(color: Colors.white.withOpacity(0.04)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavItem(
                      icon: Icons.search,
                      label: 'Search',
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
                  left: MediaQuery.of(context).size.width * 0.29, // Horizontal position of floating camera button (adjust X-axis here)
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
                        color: const Color(0xFFFF7E57).withOpacity(0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFF8F69),
                      border: Border.all(color: Colors.white.withOpacity(0.18)),
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.white,
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
    final activeColor = const Color(0xFFFF9A69);
    final inactiveColor = const Color(0xFFB4C0D0);

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
              style: TextStyle(
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

