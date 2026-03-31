#include "flutter_window.h"

#include <commdlg.h>
#include <cstdint>
#include <cwchar>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <optional>
#include <vector>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

std::wstring Utf16FromUtf8(const std::string& utf8_string) {
  if (utf8_string.empty()) {
    return std::wstring();
  }

  int input_length = static_cast<int>(utf8_string.size());
  int target_length = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.c_str(), input_length,
      nullptr, 0);
  if (target_length == 0) {
    return std::wstring();
  }

  std::wstring utf16_string(target_length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.c_str(),
                        input_length,
                        utf16_string.data(), target_length);
  return utf16_string;
}

std::optional<std::wstring> ShowOpenFileDialog(HWND owner) {
  wchar_t file_path[MAX_PATH] = L"";
  const wchar_t filter[] =
      L"Data Files (*.dat)\0*.dat\0All Files (*.*)\0*.*\0";
  OPENFILENAMEW open_file_name = {0};
  open_file_name.lStructSize = sizeof(open_file_name);
  open_file_name.hwndOwner = owner;
  open_file_name.lpstrFilter = filter;
  open_file_name.lpstrFile = file_path;
  open_file_name.nMaxFile = MAX_PATH;
  open_file_name.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_EXPLORER;
  open_file_name.nFilterIndex = 1;
  if (::GetOpenFileNameW(&open_file_name)) {
    return std::wstring(file_path);
  }
  return std::nullopt;
}

std::optional<std::wstring> ShowSaveFileDialog(HWND owner,
                                               const std::wstring& filename) {
  wchar_t file_path[MAX_PATH] = L"";
  wcsncpy_s(file_path, filename.c_str(), _TRUNCATE);
  const wchar_t filter[] =
      L"Data Files (*.dat)\0*.dat\0All Files (*.*)\0*.*\0";
  OPENFILENAMEW save_file_name = {0};
  save_file_name.lStructSize = sizeof(save_file_name);
  save_file_name.hwndOwner = owner;
  save_file_name.lpstrFilter = filter;
  save_file_name.lpstrFile = file_path;
  save_file_name.nMaxFile = MAX_PATH;
  save_file_name.Flags = OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST | OFN_EXPLORER;
  save_file_name.nFilterIndex = 1;
  if (::GetSaveFileNameW(&save_file_name)) {
    return std::wstring(file_path);
  }
  return std::nullopt;
}

std::vector<uint8_t> ReadFileBytes(const std::wstring& path) {
  std::ifstream file(path, std::ios::binary);
  if (!file.is_open()) {
    return {};
  }
  return std::vector<uint8_t>(std::istreambuf_iterator<char>(file),
                              std::istreambuf_iterator<char>());
}

bool WriteFileBytes(const std::wstring& path, const std::vector<uint8_t>& bytes) {
  std::ofstream file(path, std::ios::binary | std::ios::trunc);
  if (!file.is_open()) {
    return false;
  }
  file.write(reinterpret_cast<const char*>(bytes.data()),
             static_cast<std::streamsize>(bytes.size()));
  return file.good();
}

std::string FileNameFromPath(const std::wstring& path) {
  return Utf8FromUtf16(std::filesystem::path(path).filename().c_str());
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
  RegisterNativeFileChannel();
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

void FlutterWindow::RegisterNativeFileChannel() {
  native_file_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "selene.native_file_access/channel",
          &flutter::StandardMethodCodec::GetInstance());

  native_file_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "pickImportFile") {
          const std::optional<std::wstring> selected_path =
              ShowOpenFileDialog(GetHandle());
          if (!selected_path.has_value()) {
            result->Success();
            return;
          }

          const std::vector<uint8_t> bytes = ReadFileBytes(*selected_path);
          flutter::EncodableMap payload;
          payload[flutter::EncodableValue("name")] =
              flutter::EncodableValue(FileNameFromPath(*selected_path));
          payload[flutter::EncodableValue("bytes")] =
              flutter::EncodableValue(bytes);
          result->Success(flutter::EncodableValue(payload));
          return;
        }

        if (call.method_name() == "saveExportFile") {
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments == nullptr) {
            result->Error("INVALID_ARGS", "Missing save arguments.");
            return;
          }

          std::string suggested_name = "selene-backup.dat";
          std::vector<uint8_t> bytes;

          const auto suggested_name_it =
              arguments->find(flutter::EncodableValue("suggestedName"));
          if (suggested_name_it != arguments->end()) {
            if (const auto* value =
                    std::get_if<std::string>(&suggested_name_it->second)) {
              suggested_name = *value;
            }
          }

          const auto bytes_it =
              arguments->find(flutter::EncodableValue("bytes"));
          if (bytes_it != arguments->end()) {
            if (const auto* value =
                    std::get_if<std::vector<uint8_t>>(&bytes_it->second)) {
              bytes = *value;
            }
          }

          if (bytes.empty()) {
            result->Error("MISSING_BYTES", "Missing export file bytes.");
            return;
          }

          const std::optional<std::wstring> save_path = ShowSaveFileDialog(
              GetHandle(), Utf16FromUtf8(suggested_name));
          if (!save_path.has_value()) {
            result->Success();
            return;
          }

          if (!WriteFileBytes(*save_path, bytes)) {
            result->Error("WRITE_FAILED", "Failed to write export file.");
            return;
          }

          flutter::EncodableMap payload;
          payload[flutter::EncodableValue("path")] =
              flutter::EncodableValue(Utf8FromUtf16(save_path->c_str()));
          result->Success(flutter::EncodableValue(payload));
          return;
        }

        result->NotImplemented();
      });
}

void FlutterWindow::OnDestroy() {
  native_file_channel_.reset();
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
