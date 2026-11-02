import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/models/account.dart';
import 'package:foxel/core/theme/design_tokens.dart';
import 'package:foxel/features/drive/controllers/transfer_task_controller.dart';
import 'package:foxel/features/drive/pages/file_browser_page.dart';
import 'package:foxel/features/drive/pages/transfer_tasks_page.dart';
import 'package:foxel/features/settings/pages/settings_page.dart';

class DriveShellPage extends StatefulWidget {
  const DriveShellPage({
    super.key,
    required this.api,
    required this.account,
    required this.accountCount,
    required this.taskController,
    required this.onOpenAccountCenter,
    required this.onAddAccount,
    required this.onClearLocalData,
  });

  final FoxelApi api;

  /// 当前账户（同时决定界面主题色）。
  final Account account;
  final int accountCount;
  final TransferTaskController taskController;

  /// 打开「账户管理」页（独立二级页）。
  final VoidCallback onOpenAccountCenter;
  final VoidCallback onAddAccount;
  final ValueChanged<Account> onClearLocalData;

  @override
  State<DriveShellPage> createState() => DriveShellPageState();
}

class DriveShellPageState extends State<DriveShellPage> {
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
        oldWidget.account.id != widget.account.id ||
        oldWidget.taskController != widget.taskController) {
      for (var index = 0; index < _tabs.length; index++) {
        _tabs[index] = null;
      }
      _visitedIndexes
        ..clear()
        ..add(_currentIndex);
      _tabs[_currentIndex] = _buildTab(_currentIndex);
    }
  }

  /// 供外部（如切换账户后）切换底部导航页签。
  void selectTab(int index) => _selectIndex(index);

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
      // 以账户 ID 作为 key：切换账户时强制重建页面 State，
      // 否则会复用旧 State 继续显示上一个账户的目录与列表数据。
      0 => FileBrowserPage(
        key: ValueKey<String>('files-${widget.account.id}'),
        api: widget.api,
        taskController: widget.taskController,
        account: widget.account,
        onOpenTasks: () => _selectIndex(1),
        onOpenAccountCenter: widget.onOpenAccountCenter,
      ),
      1 => TransferTasksPage(
        key: ValueKey<String>('tasks-${widget.account.id}'),
        controller: widget.taskController,
        api: widget.api,
      ),
      _ => SettingsPage(
        key: ValueKey<String>('settings-${widget.account.id}'),
        account: widget.account,
        accountCount: widget.accountCount,
        onOpenAccountCenter: widget.onOpenAccountCenter,
        onAddAccount: widget.onAddAccount,
        onClearLocalData: widget.onClearLocalData,
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
            bottom: 0,
            child: SafeArea(
              top: false,
              // 12px 既是安全区最小间距，也为下方阴影（offset 6 + 模糊 7）留出空间，
              // 避免阴影被屏幕底边/系统导航条裁切后形成「重叠阴影」。
              minimum: const EdgeInsets.only(bottom: 12),
              child: _FloatingBottomNav(
                currentIndex: _currentIndex,
                onSelected: _selectIndex,
                activeColor: Color(widget.account.colorValue),
              ),
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
    required this.activeColor,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final Color activeColor;

  static const _items = [
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

  /// 导航条高度：内边距 6 + 内容 62。
  static const double navHeight = 74;

  /// 内容区内边距。
  static const double _inset = 6;

  /// 相邻两个选项之间的间隔（选中胶囊左右各留一半）。
  static const double _segmentGap = 14;

  @override
  Widget build(BuildContext context) {
    // SafeArea 由外层负责，这里只画胶囊本体，避免底部安全区被算进胶囊高度
    // 而在下方留出一段透明空洞（阴影落进去就会和系统导航区叠在一起）。
    return SizedBox(
      height: navHeight,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.nav),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A8B97AA),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(_inset),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final segmentWidth = constraints.maxWidth / _items.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    left: segmentWidth * currentIndex + _segmentGap / 2,
                    top: 0,
                    width: segmentWidth - _segmentGap,
                    height: constraints.maxHeight,
                    child: _SelectedNavSegment(color: activeColor),
                  ),
                  Row(
                    children: [
                      for (var index = 0; index < _items.length; index++)
                        Expanded(
                          child: _FloatingNavButton(
                            item: _items[index],
                            selected: index == currentIndex,
                            activeColor: activeColor,
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
      ),
    );
  }
}

class _FloatingNavButton extends StatelessWidget {
  const _FloatingNavButton({
    required this.item,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const inactiveColor = AppColors.ink3;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          // 与选中胶囊圆角一致；按压反馈完全交给胶囊动画，
          // 禁用 splash/highlight，避免在胶囊外沿出现比胶囊更大的高亮块。
          borderRadius: BorderRadius.circular(AppRadii.navSegment),
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
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
                  // AnimatedDefaultTextStyle 会替换外层样式，必须显式带上字体栈，
                  // 否则导航标签会掉回引擎默认字体（汉字变宋体）。
                  style: AppFonts.apply(
                    TextStyle(
                      color: selected ? activeColor : inactiveColor,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 10.5,
                      letterSpacing: 0,
                      height: 1,
                    ),
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
  const _SelectedNavSegment({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.navSegment),
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
