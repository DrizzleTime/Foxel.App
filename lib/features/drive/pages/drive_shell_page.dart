import 'package:flutter/material.dart';
import 'dart:ui';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/features/drive/pages/account_settings_page.dart';
import 'package:foxel/features/drive/pages/file_browser_page.dart';
import 'package:foxel/features/drive/pages/home_page.dart';

class DriveShellPage extends StatefulWidget {
  const DriveShellPage({
    super.key,
    required this.api,
    required this.username,
    required this.email,
    required this.avatarUrl,
    required this.baseUrl,
    required this.onOpenSettings,
    required this.onLogout,
  });

  final FoxelApi api;
  final String username;
  final String email;
  final String avatarUrl;
  final String baseUrl;
  final VoidCallback onOpenSettings;
  final VoidCallback onLogout;

  @override
  State<DriveShellPage> createState() => _DriveShellPageState();
}

class _DriveShellPageState extends State<DriveShellPage> {
  int _currentIndex = 0;
  int _previousIndex = 0;
  final Set<int> _visitedIndexes = {0};
  final List<Widget?> _tabs = List<Widget?>.filled(3, null);

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
        oldWidget.baseUrl != widget.baseUrl) {
      for (var index = 0; index < _tabs.length; index++) {
        _tabs[index] = null;
      }
      _visitedIndexes
        ..clear()
        ..add(_currentIndex);
      _tabs[_currentIndex] = _buildTab(_currentIndex);
    }
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
        onOpenFiles: () => _selectIndex(1),
        onOpenSettings: () => _selectIndex(2),
      ),
      1 => FileBrowserPage(
        api: widget.api,
        username: widget.username,
        onOpenSettings: () => _selectIndex(2),
        onLogout: widget.onLogout,
      ),
      _ => AccountSettingsPage(
        username: widget.username,
        email: widget.email,
        avatarUrl: widget.avatarUrl,
        baseUrl: widget.baseUrl,
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
            bottom: 12,
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
        for (var index = 0; index < 3; index++)
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
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _NavItem(
      label: '文件',
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder_rounded,
    ),
    _NavItem(
      label: '设置',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF102A43).withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
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
    final activeColor = Theme.of(context).colorScheme.primary;
    final inactiveColor = const Color(0xFF536170);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        height: 56,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFDDE9FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: selected ? 46 : 40,
              height: selected ? 28 : 24,
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(
                        colors: [Color(0xFF2D6BFF), Color(0xFF6DB7FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: selected ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: selected ? 1 : 0),
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return Transform.scale(
                    scale: 0.9 + value * 0.1,
                    child: Icon(
                      selected ? item.selectedIcon : item.icon,
                      size: 20,
                      color: selected ? Colors.white : inactiveColor,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? activeColor : inactiveColor,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                height: 1,
                fontSize: 11,
              ),
            ),
          ],
        ),
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
