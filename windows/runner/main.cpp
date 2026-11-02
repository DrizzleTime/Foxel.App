#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "app_messages.h"
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
  if (instance_mutex != nullptr) {
    ::CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}
