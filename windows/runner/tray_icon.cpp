#include "tray_icon.h"

#include <windows.h>
// shellapi.h 提供 Shell_NotifyIcon / NOTIFYICONDATAW，必须在 windows.h 之后。
#include <shellapi.h>

#include <utility>

#include "resource.h"

namespace {

// 应用只注册一个托盘图标，id 固定即可。
constexpr UINT kIconId = 1;

// 菜单命令 id。与菜单项一一对应：只有这两项。
constexpr UINT kCommandShowWindow = 1001;
constexpr UINT kCommandExit = 1002;

// 复用 exe 内嵌的应用图标（Runner.rc 里的 IDI_APP_ICON），不额外带资源文件。
// 用 LR_SHARED 加载共享图标，生命周期由系统管理，不调用 DestroyIcon。
HICON LoadAppIcon() {
  HINSTANCE instance = ::GetModuleHandleW(nullptr);
  // 按托盘实际尺寸取图，避免 150% / 200% 缩放下图标被拉伸模糊。
  const int size = ::GetSystemMetrics(SM_CXSMICON);
  HICON icon = static_cast<HICON>(::LoadImageW(
      instance, MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON, size, size,
      LR_DEFAULTCOLOR | LR_SHARED));
  if (icon == nullptr) {
    icon = ::LoadIconW(instance, MAKEINTRESOURCEW(IDI_APP_ICON));
  }
  return icon;
}

void CopyWide(wchar_t* destination, int capacity, const std::wstring& source) {
  if (capacity <= 0) {
    return;
  }
  ::lstrcpynW(destination, source.c_str(), capacity);
}

}  // namespace

TrayIcon::~TrayIcon() {
  Dispose();
}

void TrayIcon::SetHandlers(Handler on_show, Handler on_exit) {
  on_show_ = std::move(on_show);
  on_exit_ = std::move(on_exit);
}

bool TrayIcon::Create(HWND owner,
                      UINT callback_message,
                      const std::wstring& tooltip) {
  Dispose();

  owner_ = owner;
  callback_message_ = callback_message;
  tooltip_ = tooltip;
  icon_ = LoadAppIcon();
  // 资源管理器重启后会向所有顶层窗口广播 TaskbarCreated，据此重挂图标。
  taskbar_created_message_ = ::RegisterWindowMessageW(L"TaskbarCreated");

  return AddIcon();
}

void TrayIcon::FillData(NOTIFYICONDATAW* data) const {
  *data = NOTIFYICONDATAW{};
  data->cbSize = static_cast<DWORD>(sizeof(NOTIFYICONDATAW));
  data->hWnd = owner_;
  data->uID = kIconId;
  data->uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data->uCallbackMessage = callback_message_;
  data->hIcon = icon_;
  CopyWide(data->szTip, static_cast<int>(ARRAYSIZE(data->szTip)), tooltip_);
}

bool TrayIcon::AddIcon() {
  if (owner_ == nullptr || icon_ == nullptr) {
    return false;
  }

  NOTIFYICONDATAW data;
  FillData(&data);
  // 不切到 NOTIFYICON_VERSION_4：默认版本下 lParam 直接是鼠标消息，
  // 右键判断更简单，本功能也不需要新版回报的坐标。
  added_ = ::Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
  return added_;
}

void TrayIcon::Dispose() {
  if (added_ && owner_ != nullptr) {
    NOTIFYICONDATAW data;
    FillData(&data);
    // 先摘图标：顺序反了会在任务栏留下幽灵图标。
    ::Shell_NotifyIconW(NIM_DELETE, &data);
  }

  added_ = false;
  // 图标句柄来自 LR_SHARED，不能 DestroyIcon，这里只丢引用。
  icon_ = nullptr;
  owner_ = nullptr;
  callback_message_ = 0;
}

void TrayIcon::HandleCallback(WPARAM wparam, LPARAM lparam) {
  (void)wparam;
  // 默认版本下 lParam 的低位就是鼠标消息（WM_RBUTTONUP 等）。
  const UINT event = static_cast<UINT>(LOWORD(lparam));
  switch (event) {
    case WM_LBUTTONDBLCLK:
      // 左键双击 = 菜单「显示主窗口」，复用同一出口。
      // 单击不响应（WM_LBUTTONUP 不处理），避免误触把窗口叫出来。
      InvokeShow();
      break;
    case WM_RBUTTONUP:
    case WM_CONTEXTMENU:
      ShowContextMenu();
      break;
    default:
      break;
  }
}

void TrayIcon::InvokeShow() {
  if (on_show_) {
    on_show_();
  }
}

void TrayIcon::InvokeExit() {
  if (on_exit_) {
    on_exit_();
  }
}

void TrayIcon::ShowContextMenu() {
  if (owner_ == nullptr) {
    return;
  }

  // 弹出前先把拥有者置为前台，否则点击菜单外部时菜单不会消失。
  ::SetForegroundWindow(owner_);

  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }

  // 需求：菜单只有这两项，不加分隔线、图标、子菜单。
  ::AppendMenuW(menu, MF_STRING, static_cast<UINT_PTR>(kCommandShowWindow),
                L"显示主窗口");
  ::AppendMenuW(menu, MF_STRING, static_cast<UINT_PTR>(kCommandExit), L"退出");

  POINT cursor{};
  ::GetCursorPos(&cursor);
  const UINT flags = TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY;
  const UINT command = static_cast<UINT>(::TrackPopupMenuEx(
      menu, flags, cursor.x, cursor.y, owner_, nullptr));

  ::DestroyMenu(menu);
  // 清掉菜单残留的消息，避免紧接着的点击被吞。
  ::PostMessageW(owner_, WM_NULL, 0, 0);

  if (command == kCommandShowWindow) {
    InvokeShow();
  } else if (command == kCommandExit) {
    InvokeExit();
  }
}

void TrayIcon::ReAdd() {
  if (owner_ == nullptr || icon_ == nullptr) {
    return;
  }

  NOTIFYICONDATAW data;
  FillData(&data);
  if (!::Shell_NotifyIconW(NIM_ADD, &data)) {
    // 图标仍在册（例如只是主题切换），退化为原地更新。
    ::Shell_NotifyIconW(NIM_MODIFY, &data);
  }
  added_ = true;
}

bool TrayIcon::IsTaskbarCreatedMessage(UINT message) const {
  return taskbar_created_message_ != 0 && message == taskbar_created_message_;
}
