import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 全局设计令牌。
///
/// 账户相关界面（设置页 / 账户管理页 / 账户表单 / 账户条目 / 底部导航）
/// 统一从这里取色值、圆角、间距、字号与字重，保证渲染结果与设计稿一致。
class AppColors {
  const AppColors._();

  /// 主色（当前账户、主按钮、可点文字）。
  static const primary = Color(0xFF4C6FFF);

  /// 主色浅底（选中背景、图标底、提示卡）。
  static const primarySoft = Color(0xFFEAF0FF);

  /// 页面背景。
  static const background = Color(0xFFF4F7FA);

  /// 卡片 / 弹层底色。
  static const surface = Color(0xFFFFFFFF);

  /// 分割线与卡片描边。
  static const border = Color(0xFFE7ECF2);

  /// 一级文字（标题、正文）。
  static const ink = Color(0xFF16202C);

  /// 二级文字（副标题、说明）。
  static const ink2 = Color(0xFF5C6B7A);

  /// 三级文字（时间、提示、占位）。
  static const ink3 = Color(0xFF93A0AF);

  static const ok = Color(0xFF12B886);
  static const warn = Color(0xFFF59E0B);
  static const danger = Color(0xFFE5484D);

  /// 账户主题色候选（与 Account.palette 保持一致）。
  static const accountPalette = <Color>[
    Color(0xFF4C6FFF),
    Color(0xFF6E56CF),
    Color(0xFF12B886),
    Color(0xFFF59E0B),
    Color(0xFFE5484D),
    Color(0xFF0EA5E9),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
  ];
}

/// 圆角规范。
class AppRadii {
  const AppRadii._();

  /// 分组卡片 / 大卡。
  static const double card = 20;

  /// 列表瓦片、按钮。
  static const double tile = 16;

  /// 输入字段。
  static const double field = 14;

  /// 头像：标准 / 小 / 大。
  static const double avatar = 15;
  static const double avatarSmall = 13;
  static const double avatarLarge = 20;

  /// 底部浮动导航。
  static const double nav = 22;

  /// 导航选中段。
  static const double navSegment = 15;

  /// 胶囊标签。
  static const double pill = 99;
}

/// 间距规范。
class AppSpacing {
  const AppSpacing._();

  static const double page = 16;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 14;
  static const double xl = 16;
  static const double card = 16;
  static const double navBottom = 126;
}

/// 字体规范。
///
/// 桌面端（Windows / macOS / Linux）统一使用 Arial：Flutter 默认的 Roboto
/// 在桌面上没有中文字形，汉字会落到宋体一类的衬线兜底字体上，小字号发虚。
/// 中文优先取与 Arial 比例最接近的 UI 黑体：微软雅黑 / 苹方 / Noto Sans CJK。
/// 移动端不做干预（iOS 用苹方、Android 用系统无衬线体）。
class AppFonts {
  const AppFonts._();

  /// 桌面端拉丁字体。
  static const String desktopFamily = 'Arial';

  /// Arial 缺失时的中文与兜底顺序，按平台可用性排列。
  static const List<String> desktopFallback = <String>[
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'PingFang SC',
    'Hiragino Sans GB',
    'Noto Sans CJK SC',
    'Noto Sans SC',
    'WenQuanYi Micro Hei',
    'sans-serif',
  ];

  /// 是否启用桌面字体栈。
  static bool get useDesktopFont {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// 把字体栈叠到一个具体样式上。
  ///
  /// `DefaultTextStyle` 是「替换」而不是「合并」语义：主题里凡是显式给了
  /// TextStyle 的位置（AppBar 标题、对话框、SnackBar、ListTile、输入框、
  /// 按钮、底部导航），样式里不带 family 就会掉回引擎默认的 Roboto，
  /// 汉字随之变成宋体 —— 这正是「有的地方字体没改过来」的原因。
  static TextStyle apply(TextStyle style) {
    if (!useDesktopFont) {
      return style;
    }
    return style.copyWith(
      fontFamily: desktopFamily,
      fontFamilyFallback: desktopFallback,
    );
  }
}

/// 字号与字重规范。
class AppText {
  const AppText._();

  /// 页面大标题（21 / w800）。
  static const pageTitle = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    letterSpacing: -0.3,
  );

  /// 页面副标题（12 / w600）。
  static const pageSubtitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.ink3,
  );

  /// 分组小标题（12 / w800，字间距 0.6）。
  static const sectionLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    color: AppColors.ink3,
    letterSpacing: 0.6,
  );

  /// 列表主标题（14.5 / w700）。
  static const itemTitle = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  /// 列表副标题（12 / w600）。
  static const itemSubtitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.ink3,
  );

  /// 更弱的补充信息（11.5 / w600）。
  static const itemHint = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    color: AppColors.ink3,
  );

  /// 胶囊标签文字（11 / w800，颜色由容器决定）。
  static const pill = TextStyle(fontSize: 11, fontWeight: FontWeight.w800);

  /// 按钮文字（14.5 / w800）。
  static const button = TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800);

  /// 空态标题（17 / w800）。
  static const emptyTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
  );

  /// 空态说明（12.5 / w600，行高 1.7）。
  static const emptyBody = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    color: AppColors.ink3,
    height: 1.7,
  );

  /// 表单字段标签（12 / w800）。
  static const fieldLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    color: AppColors.ink2,
  );

  /// 错误提示（12.5 / w600）。
  static const error = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    color: AppColors.danger,
  );
}

/// 卡片通用装饰。
class AppDecorations {
  const AppDecorations._();

  /// 分组卡片：白底 + 20 圆角 + 1px 描边。
  static BoxDecoration group() {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.card),
      border: Border.all(color: AppColors.border),
    );
  }

  /// 当前账户卡：白底 + 20 圆角 + 账户色描边。
  static BoxDecoration currentAccount(Color color) {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.card),
      border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
    );
  }

  /// 提示卡（虚线/浅底）。
  static BoxDecoration hint() {
    return BoxDecoration(
      color: const Color(0xFFFAFCFF),
      borderRadius: BorderRadius.circular(AppRadii.tile),
      border: Border.all(color: AppColors.border),
    );
  }

  /// 胶囊标签。
  static BoxDecoration pill(Color color) {
    return BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadii.pill),
    );
  }
}
