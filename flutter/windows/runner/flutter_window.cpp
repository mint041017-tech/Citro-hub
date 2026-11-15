#include "flutter_window.h"

#include <optional>

#include "danmaku_overlay.h"
#include "flutter/generated_plugin_registrant.h"

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

  // 一起看弹幕悬浮窗：观众聊天滚动在主持人屏幕上（主窗口最小化后仍在）。
  // 全部方法吞异常返回 —— 弹幕是锦上添花，任何失败都不能影响主程序。
  danmaku_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.chimu.crew/danmaku",
          &flutter::StandardMethodCodec::GetInstance());
  danmaku_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        try {
          if (call.method_name() == "canShow") {
            result->Success(flutter::EncodableValue(danmaku_overlay::CanShow()));
          } else if (call.method_name() == "show") {
            int top = 72;
            if (const auto* args =
                    std::get_if<flutter::EncodableMap>(call.arguments())) {
              auto it = args->find(flutter::EncodableValue("top"));
              if (it != args->end()) {
                if (const auto* v = std::get_if<int32_t>(&it->second)) {
                  top = *v;
                } else if (const auto* d = std::get_if<double>(&it->second)) {
                  top = (int)*d;
                }
              }
            }
            result->Success(flutter::EncodableValue(danmaku_overlay::Show(top)));
          } else if (call.method_name() == "hide") {
            danmaku_overlay::Hide();
            result->Success(flutter::EncodableValue(true));
          } else if (call.method_name() == "push") {
            std::string name, text;
            if (const auto* args =
                    std::get_if<flutter::EncodableMap>(call.arguments())) {
              auto get = [&args](const char* key) -> std::string {
                auto it = args->find(flutter::EncodableValue(key));
                if (it == args->end()) return "";
                if (const auto* s = std::get_if<std::string>(&it->second)) {
                  return *s;
                }
                return "";
              };
              name = get("name");
              text = get("text");
            }
            danmaku_overlay::Push(name, text);
            result->Success(flutter::EncodableValue(true));
          } else if (call.method_name() == "clear") {
            danmaku_overlay::Clear();
            result->Success(flutter::EncodableValue(true));
          } else if (call.method_name() == "openPermissionSettings") {
            // Windows 无权限门槛，占位与 Android channel 对齐。
            result->Success(flutter::EncodableValue(true));
          } else {
            result->NotImplemented();
          }
        } catch (...) {
          try {
            result->Success(flutter::EncodableValue(false));
          } catch (...) {
          }
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
