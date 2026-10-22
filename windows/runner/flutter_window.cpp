#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>

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
  core_job_ = CreateJobObjectW(nullptr, nullptr);
  if (core_job_) {
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(core_job_, JobObjectExtendedLimitInformation,
                                 &limits, sizeof(limits))) {
      CloseHandle(core_job_);
      core_job_ = nullptr;
    }
  }
  lifecycle_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "sme11_vpn/lifecycle",
      &flutter::StandardMethodCodec::GetInstance());
  lifecycle_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "attachProcess") {
      result->NotImplemented();
      return;
    }
    DWORD pid = 0;
    if (call.arguments()) {
      if (const auto* pid32 = std::get_if<int32_t>(call.arguments())) {
        pid = static_cast<DWORD>(*pid32);
      } else if (const auto* pid64 = std::get_if<int64_t>(call.arguments())) {
        pid = static_cast<DWORD>(*pid64);
      }
    }
    HANDLE process = pid ? OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE,
                                      FALSE, pid) : nullptr;
    bool attached = process && core_job_ && AssignProcessToJobObject(core_job_, process);
    if (process) CloseHandle(process);
    result->Success(flutter::EncodableValue(attached));
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  lifecycle_channel_ = nullptr;
  if (core_job_) {
    CloseHandle(core_job_);
    core_job_ = nullptr;
  }
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
