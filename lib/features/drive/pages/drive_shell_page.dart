import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/models/license_info.dart';
import 'package:foxel/features/drive/controllers/transfer_task_controller.dart';
import 'package:foxel/features/drive/pages/account_settings_page.dart';
import 'package:foxel/features/drive/pages/file_browser_page.dart';
import 'package:foxel/features/drive/pages/home_page.dart';
import 'package:foxel/features/drive/pages/transfer_tasks_page.dart';

class DriveShellPage extends StatefulWidget {
  const DriveShellPage({
    super.key,
    required this.api,
    required this.username,
    required this.email,
    required this.avatarUrl,
    required this.baseUrl,
    required this.licenseInfo,
    required this.onVerifyLicense,
    required this.onOpenSettings,
    required this.onLogout,
  });

  final FoxelApi api;
  final String username;
  final String email;
  final String avatarUrl;
  final String baseUrl;
  final LicenseInfo? licenseInfo;
  final Future<LicenseInfo> Function(String licenseKey) onVerifyLicense;
  final VoidCallback onOpenSettings;
  final VoidCallback onLogout;

  @override
  State<DriveShellPage> createState() => _DriveShellPageState();
}

class _DriveShellPageState extends State<DriveShellPage> {
  int _currentIndex = 0;
  int _previousIndex = 0;
  final Set<int> _visitedIndexes = {0};
  final List<Widget?> _tabs = List<Widget?>.filled(4, null);
  final TransferTaskController _taskController = TransferTaskController();

  @override
  void initState() {
    super.initState();
    _tabs[0] = _buildTab(0);
  }

  @override
  void didUpdateWidget(covariant DriveShellPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        oldWidget.username != widget.username ||
        oldWidget.email != widget.email ||
        oldWidget.avatarUrl != widget.avatarUrl ||
        oldWidget.baseUrl != widget.baseUrl ||
        oldWidget.licenseInfo != widget.licenseInfo) {
      for (var index = 0; index < _tabs.length; index++) {
        _tabs[index] = null;
      }
      _visitedIndexes
        ..clear()
        ..add(_currentIndex);
      _tabs[_currentIndex] = _buildTab(_currentIndex);
    }
  }

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  void _selectIndex(int index) {
    if (index == _currentIndex) {
      return;
    }
    setState(() {
      _previousIndex = _currentIndex;
      _currentIndex = index;
      _visitedIndexes.add(index);
      _tabs[index] ??= _buildTab(index);
    });
  }

  Widget _buildTab(int index) {
    return switch (index) {
      0 => HomePage(
        api: widget.api,
        username: widget.username,
        avatarUrl: widget.avatarUrl,
        isPro: widget.licenseInfo?.isPro ?? false,
        onOpenFiles: () => _selectIndex(1),
        taskController: _taskController,
        onOpenTasks: () => _selectIndex(2),
        onOpenSettings: () => _selectIndex(3),
      ),
      1 => FileBrowserPage(
        api: widget.api,
        canPlayVideo: widget.licenseInfo?.isPro ?? false,
        taskController: _taskController,
        onOpenTasks: () => _selectIndex(2),
      ),
      2 => TransferTasksPage(controller: _taskController),
      _ => AccountSettingsPage(
        username: widget.username,
        email: widget.email,
        avatarUrl: widget.avatarUrl,
        baseUrl: widget.baseUrl,
        licenseInfo: widget.licenseInfo,
        onVerifyLicense: widget.onVerifyLicense,
        onSwitchServer: widget.onOpenSettings,
        onLogout: widget.onLogout,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          _LazyTabStage(
            currentIndex: _currentIndex,
            previousIndex: _previousIndex,
            visitedIndexes: _visitedIndexes,
            tabs: _tabs,
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 8,
            child: _FloatingBottomNav(
              currentIndex: _currentIndex,
              onSelected: _selectIndex,
            ),
          ),
        ],
      ),
    );
  }
}

class _LazyTabStage extends StatelessWidget {
  const _LazyTabStage({
    required this.currentIndex,
    required this.previousIndex,
    required this.visitedIndexes,
    required this.tabs,
  });

  final int currentIndex;
  final int previousIndex;
  final Set<int> visitedIndexes;
  final List<Widget?> tabs;

  @override
  Widget build(BuildContext context) {
    final direction = currentIndex >= previousIndex ? 1.0 : -1.0;
    return Stack(
      children: [
        for (var index = 0; index < tabs.length; index++)
          if (visitedIndexes.contains(index))
            _TabSlot(
              key: ValueKey('tab-$index'),
              active: index == currentIndex,
              direction: direction,
              child: tabs[index]!,
            ),
      ],
    );
  }
}

class _TabSlot extends StatelessWidget {
  const _TabSlot({
    super.key,
    required this.active,
    required this.direction,
    required this.child,
  });

  final bool active;
  final double direction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !active,
      child: TickerMode(
        enabled: active,
        child: AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          child: AnimatedSlide(
            offset: active ? Offset.zero : Offset(-0.025 * direction, 0),
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            child: Offstage(offstage: !active, child: child),
          ),
        ),
      ),
    );
  }
}

class _FloatingBottomNav extends StatelessWidget {
  const _FloatingBottomNav({
    required this.currentIndex,
    required this.onSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const _items = [
    _NavItem(
      label: '首页',
      icon: CupertinoIcons.house,
      selectedIcon: CupertinoIcons.house_fill,
    ),
    _NavItem(
      label: '文件',
      icon: CupertinoIcons.folder,
      selectedIcon: CupertinoIcons.folder_fill,
    ),
    _NavItem(
      label: '任务',
      icon: CupertinoIcons.tray,
      selectedIcon: CupertinoIcons.tray_fill,
    ),
    _NavItem(
      label: '设置',
      icon: CupertinoIcons.gear_alt,
      selectedIcon: CupertinoIcons.gear_alt_fill,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 74,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Stack(
            children: [
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFF4F6F8).withValues(alpha: 0.76),
                        const Color(0xFFD7DDE4).withValues(alpha: 0.50),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.62),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B97AA).withValues(alpha: 0.12),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.24),
                        blurRadius: 1,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                top: 6,
                child: IgnorePointer(
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.56),
                          Colors.white.withValues(alpha: 0.04),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const segmentGap = 14.0;
                    final segmentWidth = constraints.maxWidth / _items.length;
                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          left: segmentWidth * currentIndex + segmentGap / 2,
                          top: 2,
                          width: segmentWidth - segmentGap,
                          height: constraints.maxHeight - 4,
                          child: const _SelectedNavSegment(),
                        ),
                        Row(
                          children: [
                            for (var index = 0; index < _items.length; index++)
                              Expanded(
                                child: _FloatingNavButton(
                                  item: _items[index],
                                  selected: index == currentIndex,
                                  onTap: () => onSelected(index),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingNavButton extends StatelessWidget {
  const _FloatingNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF3366F5);
    const inactiveColor = Color(0xFF818791);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: SizedBox.expand(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: selected ? 1 : 0.96,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    selected ? item.selectedIcon : item.icon,
                    size: 20,
                    color: selected ? activeColor : inactiveColor,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: selected ? activeColor : inactiveColor,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 10,
                    letterSpacing: 0,
                    height: 1,
                  ),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedNavSegment extends StatelessWidget {
  const _SelectedNavSegment();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.66),
                    const Color(0xFFE4E8EE).withValues(alpha: 0.42),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.52)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFACB7C8).withValues(alpha: 0.14),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            top: 3,
            child: IgnorePointer(
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.70),
                      Colors.white.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
