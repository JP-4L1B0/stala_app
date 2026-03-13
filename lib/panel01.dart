import 'package:flutter/material.dart';

/// Entry point of the sample Flutter UI.
///
/// This file recreates the provided "Snap Vault" main panel design
/// and keeps the code well-documented so each section is easy to follow.
void main() {
  runApp(const StalaApp());
}

/// Root application widget.
class StalaApp extends StatelessWidget {
  const StalaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'STALA - Panel 01',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFF071326),
      ),
      home: const MainPanel01Page(),
    );
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
      _openPanel02Placeholder();
      return;
    }

    setState(() {
      _selectedTab = tab;
    });
  }

  /// Temporary navigation target for Panel 02.
  ///
  /// Replace this later with your real camera/upload/scan panel page.
  void _openPanel02Placeholder() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const Panel02PlaceholderPage(),
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
              color: const Color(0xFFFF8A2B),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.camera_alt_outlined,
              size: 16,
              color: Colors.white,
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

/// HOME TAB CONTENT
///
/// Refactored based on the new reference image.
///
/// Structure per item:
/// - Large left title: Saved #
/// - Right details column:
///   - Title
///   - Date created
///   - Modified
class _HomeTabView extends StatelessWidget {
  const _HomeTabView({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      const SavedItemData(
        indexLabel: 'Saved #1',
        fileTitle: 'Unnamed_01',
        dateCreated: 'dd/mm/yyyy',
        modifiedText: '## (min or h) ago',
      ),
      const SavedItemData(
        indexLabel: 'Saved #2',
        fileTitle: 'Session_Archive',
        dateCreated: 'dd/mm/yyyy',
        modifiedText: '## (min or h) ago',
      ),
      const SavedItemData(
        indexLabel: 'Saved #3',
        fileTitle: 'Exported_Tab_01',
        dateCreated: 'dd/mm/yyyy',
        modifiedText: '## (min or h) ago',
      ),
      const SavedItemData(
        indexLabel: 'Saved #4',
        fileTitle: 'Draft_Output',
        dateCreated: 'dd/mm/yyyy',
        modifiedText: '## (min or h) ago',
      ),
    ];

    return Column(
      key: const ValueKey('home-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title: 'Recent',
          actionText: 'View All',
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) => SavedListCard(data: items[index]),
          ),
        ),
      ],
    );
  }
}

/// Data model for the refactored home list cards.
class SavedItemData {
  final String indexLabel;
  final String fileTitle;
  final String dateCreated;
  final String modifiedText;

  const SavedItemData({
    required this.indexLabel,
    required this.fileTitle,
    required this.dateCreated,
    required this.modifiedText,
  });
}

/// Card widget based on the new user-provided structure image.
class SavedListCard extends StatelessWidget {
  final SavedItemData data;

  const SavedListCard({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF566487),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              data.indexLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w400,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
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
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const TextSpan(text: '   -Edit-', style: TextStyle(fontStyle: FontStyle.italic)),
                    ],
                  ),
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
          subtitle: 'Open synced albums, documents, and online backups.',
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

/// SETTINGS TAB CONTENT
///
/// Required by your specification:
/// "Controls, Permission, and infos".
class _SettingsTabView extends StatelessWidget {
  const _SettingsTabView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('settings-content'),
      physics: const BouncingScrollPhysics(),
      children: const [
        _SectionHeader(
          title: 'Settings',
          actionText: 'Manage',
        ),
        SizedBox(height: 14),
        _InfoCard(
          title: 'Controls',
          subtitle: 'Customize gestures, transitions, and app behavior.',
          icon: Icons.tune_outlined,
        ),
        SizedBox(height: 10),
        _InfoCard(
          title: 'Permissions',
          subtitle: 'Review camera, storage, and notification access.',
          icon: Icons.lock_open_outlined,
        ),
        SizedBox(height: 10),
        _InfoCard(
          title: 'Information',
          subtitle: 'Read app version details, support notes, and FAQs.',
          icon: Icons.info_outline,
        ),
      ],
    );
  }
}

/// Shared section title row used in the mid content.
class _SectionHeader extends StatelessWidget {
  final String title;
  final String actionText;

  const _SectionHeader({
    required this.title,
    required this.actionText,
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
            color: const Color(0xFFFF8A2B),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const Spacer(),
        Text(
          actionText,
          style: const TextStyle(
            color: Color(0xFFFFB264),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Reusable informational card for Search and Settings tabs.
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

// -----------------------------------------------------------------------------
// PANEL 02 PLACEHOLDER
// -----------------------------------------------------------------------------

/// Temporary placeholder page for the special camera navigation.
///
/// Replace this file later with your actual Panel 02 implementation.
class Panel02PlaceholderPage extends StatelessWidget {
  const Panel02PlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071326),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B162B),
        foregroundColor: Colors.white,
        title: const Text('Panel 02 Placeholder'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This is a placeholder for Panel 02.\n\nThe camera button from Panel 01 should navigate here.\nReplace this page with your actual second panel later.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
