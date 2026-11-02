#ifndef RUNNER_TRAY_ICON_H_
#define RUNNER_TRAY_ICON_H_

#include <windows.h>
// NOTIFYICONDATAW 定义在 shellapi.h。
#include <shellapi.h>

#include <functional>
#include <string>

// 任务栏通知区域图标。
//
// 需求约束：
//   * 右键菜单只有「显示主窗口」和「退出」两项，不加分隔线 / 图标 / 子菜单；
//   * 左键双击托盘图标 = 菜单「显示主窗口」，两者共用同一回调，行为必须一致；
//   * 退出时必须先摘图标再销毁窗口，否则任务栏会残留"幽灵图标"。
class TrayIcon {
 public:
  using Handler = std::function<void()>;

  TrayIcon() = default;
  ~TrayIcon();

  TrayIcon(const TrayIcon&) = delete;
  TrayIcon& operator=(const TrayIcon&) = delete;

  // 绑定两个菜单项的动作。
  void SetHandlers(Handler on_show, Handler on_exit);

  // 挂载图标。|owner| 接收回调消息，|callback_message| 为自定义消息 id。
  bool Create(HWND owner, UINT callback_message, const std::wstring& tooltip);

  // 摘除图标并释放状态（可重复调用）。
  void Dispose();

  // 回调消息入口（lParam 为鼠标消息）。
  void HandleCallback(WPARAM wparam, LPARAM lparam);

  // 资源管理器重启后重新挂载图标。
  void ReAdd();

  // 判断是否为「任务栏已重建」的广播消息。
  bool IsTaskbarCreatedMessage(UINT message) const;

 private:
  void FillData(NOTIFYICONDATAW* data) const;
  bool AddIcon();
  void ShowContextMenu();
  // 唯一的"显示主窗口"出口：右键菜单项与左键双击都走这里，
  // 保证两种触发方式的执行路径完全相同。
  void InvokeShow();
  void InvokeExit();

  HWND owner_ = nullptr;
  UINT callback_message_ = 0;
  UINT taskbar_created_message_ = 0;
  HICON icon_ = nullptr;
  bool added_ = false;
  std::wstring tooltip_;
  Handler on_show_;
  Handler on_exit_;
};

#endif  // RUNNER_TRAY_ICON_H_
