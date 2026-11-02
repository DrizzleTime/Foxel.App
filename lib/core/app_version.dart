/// 应用版本。
///
/// **发版清单**：修改本文件后，同步更新
/// - `pubspec.yaml` 的 `version`（形如 `1.0.3+4`，build 号递增）
/// - `README.md` 顶部的「当前版本」与「版本发布记录」
/// - `windows/runner/Runner.rc` 的兜底版本号（正常由 Flutter 注入）
/// - `linux/CMakeLists.txt` 的 `PROJECT_VERSION`
library;

/// 展示用的版本号（界面「关于 Foxel」）。
const String appVersion = '1.0.11';

/// 带构建号的完整版本。
const String appVersionName = 'v1.0.11';
