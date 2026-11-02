import 'package:flutter/material.dart';

import 'package:foxel/core/models/account.dart';
import 'package:foxel/core/theme/design_tokens.dart';

/// 账户头像：优先使用服务器头像，缺失时用账户主题色 + 首字母。
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.account,
    this.size = 44,
    this.radius = AppRadii.avatar,
    this.fontSize,
  });

  final Account account;

  /// 边长：设计稿规范为 60 / 44 / 40 / 38 / 28。
  final double size;
  final double radius;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final color = Color(account.colorValue);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        account.initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: fontSize ?? size * 0.42,
        ),
      ),
    );

    if (account.avatarUrl.isEmpty) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        account.avatarUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
