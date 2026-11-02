#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "app_messages.h"
#include "app_paths.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

// 第二实例的唯一职责：把已有实例的主窗口唤到前台，然后自己退出。
// 第一实例可能还停在启动阶段（窗口尚未创建），此时 FindWindow 只会拿到
// nullptr；若立刻退出就表现为"双击图标毫无反应"。因此在一个短窗口内重试，
// 拿到窗口就唤起并返回 true。
bool ActivateExistingInstance() {
  constexpr int kMaxAttempts = 30;           // 30 × 100ms ≈ 最多等 3 秒
  constexpr DWORD kRetryIntervalMs = 100;
  for (int attempt = 0; attempt < kMaxAttempts; ++attempt) {
    HWND existing = ::FindWindowW(nullptr, kWindowTitle);
    if (existing != nullptr) {
      DWORD owner_pid = 0;
      ::GetWindowThreadProcessId(existing, &owner_pid);
      // 允许目标进程抢前台，否则它的 SetForegroundWindow 会被系统驳回。
      ::AllowSetForegroundWindow(owner_pid);
      ::PostMessageW(existing, kShowWindowMessage, 0, 0);
      return true;
    }
    ::Sleep(kRetryIntervalMs);
  }
  return false;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // 单实例：便携版数据（userdata/prefs.json）是程序目录级共享的，
  // 多开会互相覆盖写入，因此必须只允许一个进程。
  // 第二个实例只负责把已有实例的主窗口唤到前台，然后立即退出。
  // 命名放在 Local\ 下：多用户 / 远程桌面各自独立。
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, L"Local\\Foxel.App.SingleInstance");
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateExistingInstance();
    ::CloseHandle(instance_mutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  // 跨登录会话互斥：上面的 mutex 在 Local\ 命名空间，只对当前会话有效，
  // 而 userdata/prefs.json 是程序目录级共享的。两个会话（本地 + 远程桌面、
  // 快速用户切换）同时运行时会各自缓存一份数据并整体覆盖写盘，
  // 后写的一方把另一方的账户 / token 整段抹掉（last-writer-wins）。
  // 这里用文件句柄独占（dwShareMode = 0）把并发写降到零：第二个会话直接退出。
  // 锁在进程存活期间持有，崩溃时由系统回收，不会留下死锁。
  HANDLE session_lock = nullptr;
  const std::wstring data_dir = UserDataDirectory();
  if (!data_dir.empty()) {
    const std::wstring lock_path = data_dir + L"\\.session-lock";
    session_lock = ::CreateFileW(lock_path.c_str(), GENERIC_READ | GENERIC_WRITE,
                                 0, nullptr, OPEN_ALWAYS,
                                 FILE_ATTRIBUTE_HIDDEN, nullptr);
    if (session_lock == INVALID_HANDLE_VALUE) {
      // 先取错误码再清句柄：中间任何一次 API 调用都会覆盖 LastError。
      const DWORD lock_error = ::GetLastError();
      session_lock = nullptr;
      // 只有「被占用」才代表另一个会话在跑。目录只读等错误必须放行 ——
      // 那种环境本来也写不了 prefs.json，不能因为建不起锁文件就让程序起不来。
      if (lock_error == ERROR_SHARING_VIOLATION) {
        ::MessageBoxW(
            nullptr,
            L"Foxel 已在另一个 Windows 会话中运行。\n\n"
            L"便携版数据目录（程序目录下的 userdata）不支持多个会话同时写入，"
            L"请先关闭另一个窗口后再启动。",
            kWindowTitle, MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
        if (instance_mutex != nullptr) {
          ::CloseHandle(instance_mutex);
        }
        ::CoUninitialize();
        return EXIT_SUCCESS;
      }
    }
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  // 顺序无关，但都必须在进程退出前显式释放，别依赖 CRT 的隐式清理。
  if (session_lock != nullptr) {
    ::CloseHandle(session_lock);
  }
  if (instance_mutex != nullptr) {
    ::CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}
