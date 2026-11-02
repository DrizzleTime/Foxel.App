import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 账户 token 的落盘保护。
///
/// Windows 上由 runner 注册了 `foxel/secret` 通道，底层是 DPAPI：
/// 密文绑定当前 Windows 用户，拷走 `userdata/prefs.json`（整目录备份、
/// 网盘同步、发给别人排查问题）都解不开。代价是换机器 / 换系统用户后
/// 需要重新登录一次 —— 这个交换对「私人云盘」是划算的。
///
/// 其他平台没有原生实现，保持明文（与旧版本一致），不为一个 Windows 便携版
/// 的问题给移动端增加原生依赖。
class TokenProtector {
  const TokenProtector._();

  /// 密文前缀：带它才走解密，不带就当旧版明文直接使用。
  static const String cipherPrefix = 'enc:v1:';

  static const MethodChannel _channel = MethodChannel('foxel/secret');

  /// 引擎侧通道是否可用。一旦发现没注册（MissingPluginException）就置位，
  /// 后续不再反复试探，避免每次读账户都抛一次异常。
  static bool _channelAvailable = true;

  /// 当前平台是否具备加密能力（目前只有 Windows runner 实现了通道）。
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// 加密；任何失败都返回原文，保证「加密坏了也不耽误登录」。
  static Future<String> protect(String token) async {
    if (token.isEmpty || !isSupported || !_channelAvailable) {
      return token;
    }
    if (token.startsWith(cipherPrefix)) {
      // 已经是密文（重复调用），不要二次加密。
      return token;
    }
    try {
      final encoded = await _channel.invokeMethod<String>('protect', token);
      if (encoded == null || encoded.isEmpty) {
        return token;
      }
      return '$cipherPrefix$encoded';
    } on MissingPluginException {
      _channelAvailable = false;
      return token;
    } catch (error) {
      debugPrint('[Foxel] token 加密失败，本次按明文保存：$error');
      return token;
    }
  }

  /// 解密。
  ///
  /// 返回 null 表示「这段密文本机解不开」（换了 Windows 用户、换了机器、
  /// 或者数据被改过），调用方应当把它当成凭证失效处理，提示重新登录。
  static Future<String?> unprotect(String stored) async {
    if (stored.isEmpty) {
      return '';
    }
    if (!stored.startsWith(cipherPrefix)) {
      // 旧版本写下的明文，直接可用；下次 upsert 时会被自动加密。
      return stored;
    }
    if (!isSupported) {
      return null;
    }
    try {
      return await _channel.invokeMethod<String>(
        'unprotect',
        stored.substring(cipherPrefix.length),
      );
    } on MissingPluginException {
      _channelAvailable = false;
      return null;
    } catch (error) {
      debugPrint('[Foxel] token 解密失败：$error');
      return null;
    }
  }
}
