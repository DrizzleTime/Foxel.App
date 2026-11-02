import 'package:flutter/material.dart';

import 'package:foxel/core/theme/design_tokens.dart';

import 'app_root.dart';

export 'app_root.dart';

/// 全局主题：所有页面（文件 / 任务 / 设置 / 账户）的按钮、输入框、
/// AppBar、对话框统一按设计稿规范渲染，避免各页各自硬编码样式。
class FoxelDriveApp extends StatelessWidget {
  const FoxelDriveApp({super.key});

  static ThemeData buildTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      surface: AppColors.surface,
      error: AppColors.danger,
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.tile),
    );
    const buttonPadding = EdgeInsets.symmetric(
      horizontal: AppSpacing.card,
      vertical: AppSpacing.lg,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // 桌面端统一 Arial + 中文近似黑体，移动端沿用系统字体。
      fontFamily: AppFonts.useDesktopFont ? AppFonts.desktopFamily : null,
      fontFamilyFallback: AppFonts.useDesktopFont
          ? AppFonts.desktopFallback
          : null,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.ink, size: 22),
        titleTextStyle: AppFonts.apply(
          AppText.pageTitle.copyWith(fontSize: 17),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          textStyle: AppFonts.apply(AppText.button),
          padding: buttonPadding,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          textStyle: AppFonts.apply(AppText.button),
          padding: buttonPadding,
          side: const BorderSide(color: AppColors.border),
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: AppFonts.apply(
            const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.field),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        hintStyle: AppFonts.apply(AppText.itemSubtitle),
        labelStyle: AppFonts.apply(AppText.fieldLabel),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: AppFonts.apply(
          const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        contentTextStyle: AppFonts.apply(
          const TextStyle(fontSize: 13, color: AppColors.ink2, height: 1.6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: AppFonts.apply(
          const TextStyle(
            fontSize: 12.8,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
        ),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: AppFonts.apply(AppText.itemTitle),
        subtitleTextStyle: AppFonts.apply(AppText.itemSubtitle),
        iconColor: AppColors.ink2,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      // 用默认水波纹：InkSparkle 会在按压处生成带光晕的光斑，
      // 在扁平卡片与浮动导航上表现为「异常阴影」。
      splashColor: AppColors.primary.withValues(alpha: 0.10),
      highlightColor: AppColors.primary.withValues(alpha: 0.06),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Foxel',
      theme: buildTheme(),
      // 主题只覆盖到 Material 体系内的文本；这里再兜一层，
      // 让不在 Material 下的 Text 也拿到桌面字体栈。
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        if (!AppFonts.useDesktopFont) {
          return content;
        }
        return DefaultTextStyle.merge(
          style: const TextStyle(
            fontFamily: AppFonts.desktopFamily,
            fontFamilyFallback: AppFonts.desktopFallback,
          ),
          child: content,
        );
      },
      home: const AppRoot(),
    );
  }
}
