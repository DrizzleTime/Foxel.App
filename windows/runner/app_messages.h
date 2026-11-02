#ifndef RUNNER_APP_MESSAGES_H_
#define RUNNER_APP_MESSAGES_H_

#include <windows.h>

// 主窗口标题。同时用于窗口创建与第二实例 FindWindow 查找，保证只在一处定义。
constexpr const wchar_t* kWindowTitle = L"Foxel";

// 托盘图标回调消息：lParam 为鼠标消息（WM_RBUTTONUP 等）。
constexpr UINT kTrayCallbackMessage = WM_APP + 101;

// 第二个实例请求已有实例显示主窗口（单实例唤起）。
constexpr UINT kShowWindowMessage = WM_APP + 102;

#endif  // RUNNER_APP_MESSAGES_H_
