#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "tray_icon.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
//
// 桌面上以"窗口 + 托盘常驻"形态运行：启动即显示主窗口并挂上托盘图标，
// 关闭窗口只隐藏、进程与 Flutter 引擎继续运行，
// 唯一真正的退出路径是托盘菜单的「退出」。
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // 显示主窗口（托盘菜单「显示主窗口」/ 第二实例唤起）。
  void ShowMainWindow();
  // 收进托盘：只隐藏，不销毁窗口，位置与状态全部保留。
  void HideMainWindow();
  // 真正退出：先摘托盘图标，再销毁窗口触发消息循环结束。
  void QuitApp();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // 托盘图标。
  TrayIcon tray_;

  // 是否已进入真正的退出流程：置位后 WM_CLOSE 不再被改写为隐藏。
  bool quitting_ = false;

  // 托盘图标是否挂载成功。
  // 挂载失败时程序没有任何「显示/退出」入口，因此 WM_CLOSE 必须退化为真退出，
  // 否则窗口一关就只剩一个点不到的进程，只能靠任务管理器结束。
  bool tray_available_ = true;

  // token 加解密通道（DPAPI，绑定当前 Windows 用户）。
  // Dart 侧 `foxel/secret` 通道的对应实现，见 RegisterSecretChannel。
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      secret_channel_;

  // 注册 foxel/secret 方法通道；引擎不可用时什么也不做。
  void RegisterSecretChannel();
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
