#ifndef RUNNER_APP_PATHS_H_
#define RUNNER_APP_PATHS_H_

#include <windows.h>

#include <string>

// 便携版用户数据目录：<exe 所在目录>\userdata，不存在时创建（已存在会失败，忽略）。
//
// 返回空串表示拿不到 exe 路径。调用方必须按"默认行为"处理，
// 不能因为路径异常就阻断启动 —— 便携版的核心承诺是双击就能用。
//
// 放在头文件里 inline：只有 main.cpp 与 flutter_window.cpp 两处使用，
// 为它单开一个 .cpp 就得改 CMakeLists 的源文件列表，不划算。
inline std::wstring UserDataDirectory() {
  wchar_t exe_path[MAX_PATH] = {};
  const DWORD length =
      ::GetModuleFileNameW(nullptr, exe_path, static_cast<DWORD>(MAX_PATH));
  if (length == 0 || length >= static_cast<DWORD>(MAX_PATH)) {
    return std::wstring();
  }

  std::wstring directory(exe_path, length);
  const size_t separator = directory.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return std::wstring();
  }
  directory.erase(separator);
  directory += L"\\userdata";
  ::CreateDirectoryW(directory.c_str(), nullptr);  // 已存在时会失败，忽略
  return directory;
}

#endif  // RUNNER_APP_PATHS_H_
