import 'package:flutter/material.dart';

/// 内容宽度收敛：桌面 / 平板（宽屏）下把页面内容限制在 [maxWidth] 并居中，
/// 移动端宽度不足时保持全宽，保证与设计稿一致的版式比例。
class ContentFrame extends StatelessWidget {
  const ContentFrame({
    super.key,
    required this.child,
    this.maxWidth = 720,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= maxWidth) {
          return child;
        }
        return Center(
          child: SizedBox(width: maxWidth, child: child),
        );
      },
    );
  }
}
