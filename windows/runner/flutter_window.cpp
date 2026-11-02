#include "flutter_window.h"

#include <windows.h>
// DPAPI：必须在 windows.h 之后包含。
#include <dpapi.h>

#include <optional>
#include <string>

#include <flutter/standard_method_codec.h>

#include "app_messages.h"
#include "app_paths.h"
#include "flutter/generated_plugin_registrant.h"

namespace {

// 用当前 Windows 用户的 DPAPI 密钥加密一段 UTF-8 文本，输出 base64。
//
// 目的：token 落到 userdata/prefs.json 时不再是明文 —— 拷走整个程序目录、
// 或者把目录同步到网盘，别人拿到也解不开（密文绑定当前用户账户）。
// 代价：换机器 / 换 Windows 用户后需要重新登录，这是安全换来的。
bool ProtectText(const std::string& plain, std::string* encoded) {
  DATA_BLOB input{};
  input.pbData = reinterpret_cast<BYTE*>(const_cast<char*>(plain.data()));
  input.cbData = static_cast<DWORD>(plain.size());

  DATA_BLOB output{};
  if (!::CryptProtectData(&input, L"Foxel account token", nullptr, nullptr,
                          nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output)) {
    return false;
  }

  DWORD size = 0;
  BOOL ok = ::CryptBinaryToStringA(
      output.pbData, output.cbData,
      CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, nullptr, &size);
  std::string base64;
  if (ok && size > 0) {
    base64.assign(size, '\0');
    ok = ::CryptBinaryToStringA(output.pbData, output.cbData,
                               CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF,
                               base64.data(), &size);
    if (ok) {
      // 返回的长度包含结尾 '\0'，去掉它才能还原成原始 base64。
      base64.resize(size > 0 ? size - 1 : 0);
    }
  }
  ::LocalFree(output.pbData);

  if (!ok) {
    return false;
  }
  *encoded = std::move(base64);
  return true;
}

// ProtectText 的逆操作。解不开（换用户 / 换机器 / 数据被改）时返回 false。
bool UnprotectText(const std::string& encoded, std::string* plain) {
  DWORD size = 0;
  if (!::CryptStringToBinaryA(encoded.c_str(), 0, CRYPT_STRING_BASE64, nullptr,
                              &size, nullptr, nullptr) ||
      size == 0) {
    return false;
  }

  std::string binary(size, '\0');
  if (!::CryptStringToBinaryA(
          encoded.c_str(), 0, CRYPT_STRING_BASE64,
          reinterpret_cast<BYTE*>(binary.data()), &size, nullptr, nullptr)) {
    return false;
  }
  binary.resize(size);

  DATA_BLOB input{};
  input.pbData = reinterpret_cast<BYTE*>(binary.data());
  input.cbData = static_cast<DWORD>(binary.size());

  DATA_BLOB output{};
  if (!::CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr,
                            CRYPTPROTECT_UI_FORBIDDEN, &output)) {
    return false;
  }

  std::string text(reinterpret_cast<const char*>(output.pbData),
                   static_cast<size_t>(output.cbData));
  ::LocalFree(output.pbData);
  *plain = std::move(text);
  return true;
}


// 设置页「启动时最小化到托盘」：标记文件存在即开启，内容不参与判定。
// 文件名与 Dart 端 DesktopWindowStore 共用，改一处必须同步另一处。
bool ShouldStartMinimized() {
  const std::wstring directory = UserDataDirectory();
  if (directory.empty()) {
    return false;
  }
  const std::wstring marker = directory + L"\\.start-minimized";
  return ::GetFileAttributesW(marker.c_str()) != INVALID_FILE_ATTRIBUTES;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // token 加密通道：Dart 侧 AccountStore 通过它做 DPAPI 加解密。
  RegisterSecretChannel();

  tray_.SetHandlers([this]() { ShowMainWindow(); }, [this]() { QuitApp(); });
  if (!tray_.Create(GetHandle(), kTrayCallbackMessage, kWindowTitle)) {
    // 托盘挂载失败也要显示窗口，否则用户面对的是一个没有托盘入口的进程。
    // 同时记下「没有托盘」：此后 WM_CLOSE 必须真退出，不能只隐藏。
    tray_available_ = false;
    ShowMainWindow();
    return true;
  }

  // 启动形态由设置页「启动时最小化到托盘」决定（每次启动重新读取）：
  //   关闭（默认）→ 显示主窗口 + 托盘常驻，两者并存
  //   开启        → 只挂托盘图标，主窗口等托盘菜单 / 双击 / 第二实例唤起
  // 两条路径都保留托盘常驻；关闭窗口只收进托盘（见 MessageHandler 的 WM_CLOSE）。
  const bool start_minimized = ShouldStartMinimized();

  if (!start_minimized) {
    // 必须等首帧渲染完成再 Show，否则会先闪出一帧空白窗口 —— 这是模板默认
    // 做法（engine()->SetNextFrameCallback + Show），此处沿用，显示走统一出口。
    flutter_controller_->engine()->SetNextFrameCallback([this]() {
      // 回调由引擎在帧调度后触发，此时窗口可能已进入退出流程。
      if (quitting_ || GetHandle() == nullptr) {
        return;
      }
      ShowMainWindow();
    });
  }
  // 引擎空闲时不会主动出帧：显示路径靠这次 ForceRedraw 触发上面的回调，
  // 隐藏路径靠它先把首帧画好，从托盘恢复时不必再等引擎出帧。
  flutter_controller_->ForceRedraw();

  // 首次运行托盘气泡已移除：它依赖 exe 目录可写（标记文件），放到 Program Files
  // 这类只读位置就永久失效；而窗口每次启动都显示、托盘图标随时可见，
  // 这条提示不值得再留一条会静默失效的代码路径。行为说明见 README。

  return true;
}

void FlutterWindow::OnDestroy() {
  // 兜底：无论从哪条路径销毁窗口，都先把托盘图标摘掉。
  tray_.Dispose();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::ShowMainWindow() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }

  // 托盘恢复时窗口可能处于隐藏或最小化状态，两种都要处理。
  ::ShowWindow(hwnd, ::IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
  ::SetForegroundWindow(hwnd);
  if (flutter_controller_) {
    flutter_controller_->ForceRedraw();
  }
  // 不擦背景（FALSE），避免出现一帧白底。
  ::InvalidateRect(hwnd, nullptr, FALSE);
}

void FlutterWindow::HideMainWindow() {
  HWND hwnd = GetHandle();
  if (hwnd != nullptr) {
    ::ShowWindow(hwnd, SW_HIDE);
  }
}

void FlutterWindow::QuitApp() {
  if (quitting_) {
    return;
  }
  quitting_ = true;

  // 顺序关键：先摘托盘图标，再销毁窗口，否则任务栏残留幽灵图标。
  tray_.Dispose();

  HWND hwnd = GetHandle();
  if (hwnd != nullptr) {
    // WM_DESTROY → PostQuitMessage(0)，消息循环结束后进程退出。
    ::DestroyWindow(hwnd);
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // 托盘回调与第二实例唤起属于 runner 自己的消息，先于引擎处理。
  if (message == kTrayCallbackMessage) {
    tray_.HandleCallback(wparam, lparam);
    return 0;
  }
  if (message == kShowWindowMessage) {
    ShowMainWindow();
    return 0;
  }
  // 资源管理器重启后重新挂载图标，否则图标会永久消失。
  if (tray_.IsTaskbarCreatedMessage(message)) {
    tray_.ReAdd();
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_CLOSE:
      // 关闭主界面只收进托盘：隐藏而非销毁，进程与 Flutter 引擎继续运行。
      // 唯一的真退出路径是托盘菜单「退出」（见 QuitApp）。
      if (!quitting_) {
        if (!tray_available_) {
          // 没有托盘图标 = 没有「显示」和「退出」的入口，关闭窗口必须是真退出，
          // 否则用户只会看到一个消失的窗口和一个杀不掉的进程。
          QuitApp();
          return 0;
        }
        HideMainWindow();
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::RegisterSecretChannel() {
  if (!flutter_controller_ || !flutter_controller_->engine()) {
    return;
  }

  secret_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "foxel/secret",
          &flutter::StandardMethodCodec::GetInstance());

  // 只暴露两个动作：protect（明文 → enc:v1:<base64>）与 unprotect（还原）。
  // 失败一律走 Error，Dart 侧会把加密失败降级为明文，不影响登录可用性。
  secret_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        const auto* argument = std::get_if<std::string>(call.arguments());
        if (argument == nullptr) {
          result->Error("bad_argument", "expects a string payload");
          return;
        }

        if (call.method_name() == "protect") {
          std::string encoded;
          if (!ProtectText(*argument, &encoded)) {
            result->Error("protect_failed", "CryptProtectData failed");
            return;
          }
          result->Success(flutter::EncodableValue(encoded));
          return;
        }

        if (call.method_name() == "unprotect") {
          std::string plain;
          if (!UnprotectText(*argument, &plain)) {
            result->Error("unprotect_failed", "CryptUnprotectData failed");
            return;
          }
          result->Success(flutter::EncodableValue(plain));
          return;
        }

        result->NotImplemented();
      });
}
