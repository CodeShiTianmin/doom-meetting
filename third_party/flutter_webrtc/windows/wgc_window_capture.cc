#include "wgc_window_capture.h"

#include <windows.h>

#include <d3d11.h>
#include <dxgi.h>
#include <inspectable.h>

#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Metadata.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Graphics.h>

#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>

#include <algorithm>
#include <condition_variable>
#include <future>
#include <mutex>
#include <thread>

namespace flutter_webrtc_plugin {

namespace {

using winrt::Windows::Foundation::Metadata::ApiInformation;
using winrt::Windows::Graphics::SizeInt32;
using winrt::Windows::Graphics::Capture::Direct3D11CaptureFrame;
using winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool;
using winrt::Windows::Graphics::Capture::GraphicsCaptureItem;
using winrt::Windows::Graphics::Capture::GraphicsCaptureSession;
using winrt::Windows::Graphics::DirectX::DirectXPixelFormat;
using winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;
using winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DSurface;

constexpr DirectXPixelFormat kPixelFormat =
    DirectXPixelFormat::B8G8R8A8UIntNormalized;
constexpr int32_t kFramePoolBuffers = 2;

class WgcWindowCaptureImpl : public WgcWindowCapture {
 public:
  WgcWindowCaptureImpl(HWND hwnd,
                       FrameCallback callback,
                       void* user_data)
      : hwnd_(hwnd), callback_(callback), user_data_(user_data) {}

  ~WgcWindowCaptureImpl() override { Stop(); }

  bool Start() {
    std::promise<bool> ready;
    std::future<bool> ready_future = ready.get_future();
    worker_ = std::thread([this, &ready]() { WorkerMain(std::move(ready)); });
    bool ok = ready_future.get();
    if (!ok && worker_.joinable()) {
      worker_.join();
    }
    return ok;
  }

  void Stop() override {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      running_ = false;
      stop_requested_ = true;
    }
    stop_cv_.notify_all();
    if (worker_.joinable()) {
      worker_.join();
    }
  }

 private:
  void WorkerMain(std::promise<bool> ready) {
    bool apartment_initialised = false;
    try {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
      apartment_initialised = true;
    } catch (...) {
      // Thread already belongs to an apartment; keep going with it.
    }

    bool ok = false;
    try {
      ok = Setup();
    } catch (...) {
      ok = false;
    }
    if (!ok) {
      Teardown();
    }
    ready.set_value(ok);
    if (ok) {
      std::unique_lock<std::mutex> lock(mutex_);
      stop_cv_.wait(lock, [this]() { return stop_requested_; });
      lock.unlock();
      Teardown();
    }
    if (apartment_initialised) {
      winrt::uninit_apartment();
    }
  }

  bool CreateDevice() {
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    HRESULT hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
                                   flags, nullptr, 0, D3D11_SDK_VERSION,
                                   d3d_device_.put(), nullptr,
                                   d3d_context_.put());
    if (FAILED(hr)) {
      d3d_device_ = nullptr;
      d3d_context_ = nullptr;
      hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, flags,
                             nullptr, 0, D3D11_SDK_VERSION, d3d_device_.put(),
                             nullptr, d3d_context_.put());
    }
    if (FAILED(hr) || !d3d_device_ || !d3d_context_) {
      return false;
    }
    winrt::com_ptr<IDXGIDevice> dxgi_device = d3d_device_.as<IDXGIDevice>();
    winrt::com_ptr<::IInspectable> inspectable;
    hr = CreateDirect3D11DeviceFromDXGIDevice(dxgi_device.get(),
                                              inspectable.put());
    if (FAILED(hr) || !inspectable) {
      return false;
    }
    device_ = inspectable.as<IDirect3DDevice>();
    return device_ != nullptr;
  }

  bool Setup() {
    if (!GraphicsCaptureSession::IsSupported()) {
      return false;
    }
    if (!hwnd_ || !IsWindow(hwnd_)) {
      return false;
    }
    if (!CreateDevice()) {
      return false;
    }

    auto interop = winrt::get_activation_factory<GraphicsCaptureItem,
                                                 IGraphicsCaptureItemInterop>();
    GraphicsCaptureItem item{nullptr};
    HRESULT hr = interop->CreateForWindow(
        hwnd_, winrt::guid_of<GraphicsCaptureItem>(), winrt::put_abi(item));
    if (FAILED(hr) || !item) {
      return false;
    }
    item_ = item;

    SizeInt32 size = item_.Size();
    if (size.Width <= 0 || size.Height <= 0) {
      return false;
    }
    pool_size_ = size;
    frame_pool_ = Direct3D11CaptureFramePool::CreateFreeThreaded(
        device_, kPixelFormat, kFramePoolBuffers, size);
    session_ = frame_pool_.CreateCaptureSession(item_);

    frame_arrived_ = frame_pool_.FrameArrived(
        winrt::auto_revoke,
        [this](Direct3D11CaptureFramePool const& sender,
               winrt::Windows::Foundation::IInspectable const&) {
          OnFrameArrived(sender);
        });

    try {
      if (ApiInformation::IsPropertyPresent(
              L"Windows.Graphics.Capture.GraphicsCaptureSession",
              L"IsCursorCaptureEnabled")) {
        session_.IsCursorCaptureEnabled(false);
      }
    } catch (...) {
    }
    try {
      if (ApiInformation::IsPropertyPresent(
              L"Windows.Graphics.Capture.GraphicsCaptureSession",
              L"IsBorderRequired")) {
        session_.IsBorderRequired(false);
      }
    } catch (...) {
      // Border removal needs an explicit capture-access grant on some
      // builds; the highlight border is cosmetic so ignore failures.
    }

    {
      std::lock_guard<std::mutex> lock(mutex_);
      running_ = true;
    }
    session_.StartCapture();
    return true;
  }

  void Teardown() {
    try {
      frame_arrived_.revoke();
      if (session_) {
        session_.Close();
      }
      if (frame_pool_) {
        frame_pool_.Close();
      }
    } catch (...) {
    }
    session_ = nullptr;
    frame_pool_ = nullptr;
    item_ = nullptr;
    staging_ = nullptr;
    device_ = nullptr;
    d3d_context_ = nullptr;
    d3d_device_ = nullptr;
  }

  bool EnsureStaging(const D3D11_TEXTURE2D_DESC& source_desc) {
    if (staging_) {
      D3D11_TEXTURE2D_DESC desc;
      staging_->GetDesc(&desc);
      if (desc.Width == source_desc.Width &&
          desc.Height == source_desc.Height &&
          desc.Format == source_desc.Format) {
        return true;
      }
      staging_ = nullptr;
    }
    D3D11_TEXTURE2D_DESC desc = source_desc;
    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    desc.MiscFlags = 0;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.SampleDesc.Count = 1;
    desc.SampleDesc.Quality = 0;
    HRESULT hr =
        d3d_device_->CreateTexture2D(&desc, nullptr, staging_.put());
    return SUCCEEDED(hr) && staging_;
  }

  void OnFrameArrived(Direct3D11CaptureFramePool const& sender) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!running_) {
      return;
    }
    try {
      ProcessFrameLocked(sender);
    } catch (...) {
      // A failing frame must not take down the WinRT callback thread; the
      // next FrameArrived simply retries.
    }
  }

  // Requires mutex_.
  void ProcessFrameLocked(Direct3D11CaptureFramePool const& sender) {
    Direct3D11CaptureFrame frame = sender.TryGetNextFrame();
    if (!frame) {
      return;
    }
    SizeInt32 content_size = frame.ContentSize();
    IDirect3DSurface surface = frame.Surface();
    if (!surface) {
      return;
    }

    auto access =
        surface.as<::Windows::Graphics::DirectX::Direct3D11::
                       IDirect3DDxgiInterfaceAccess>();
    winrt::com_ptr<ID3D11Texture2D> texture;
    HRESULT hr = access->GetInterface(winrt::guid_of<ID3D11Texture2D>(),
                                      texture.put_void());
    if (FAILED(hr) || !texture) {
      return;
    }

    D3D11_TEXTURE2D_DESC desc;
    texture->GetDesc(&desc);

    int width = std::min<int>(content_size.Width, static_cast<int>(desc.Width));
    int height =
        std::min<int>(content_size.Height, static_cast<int>(desc.Height));

    if (content_size.Width > 0 && content_size.Height > 0 &&
        (content_size.Width != pool_size_.Width ||
         content_size.Height != pool_size_.Height)) {
      // Window was resized: recreate the pool so following frames use the
      // new dimensions. The current frame is still delivered (cropped).
      pool_size_ = content_size;
      try {
        frame_pool_.Recreate(device_, kPixelFormat, kFramePoolBuffers,
                             content_size);
      } catch (...) {
      }
    }

    if (width <= 0 || height <= 0) {
      return;
    }
    if (!EnsureStaging(desc)) {
      return;
    }

    d3d_context_->CopyResource(staging_.get(), texture.get());
    D3D11_MAPPED_SUBRESOURCE mapped = {};
    hr = d3d_context_->Map(staging_.get(), 0, D3D11_MAP_READ, 0, &mapped);
    if (FAILED(hr)) {
      return;
    }
    if (callback_) {
      callback_(user_data_, static_cast<const uint8_t*>(mapped.pData), width,
                height, static_cast<int>(mapped.RowPitch));
    }
    d3d_context_->Unmap(staging_.get(), 0);
  }

  HWND hwnd_;
  FrameCallback callback_;
  void* user_data_;

  std::thread worker_;
  std::mutex mutex_;
  std::condition_variable stop_cv_;
  bool running_ = false;
  bool stop_requested_ = false;

  winrt::com_ptr<ID3D11Device> d3d_device_;
  winrt::com_ptr<ID3D11DeviceContext> d3d_context_;
  winrt::com_ptr<ID3D11Texture2D> staging_;
  IDirect3DDevice device_{nullptr};
  GraphicsCaptureItem item_{nullptr};
  Direct3D11CaptureFramePool frame_pool_{nullptr};
  GraphicsCaptureSession session_{nullptr};
  Direct3D11CaptureFramePool::FrameArrived_revoker frame_arrived_;
  SizeInt32 pool_size_{0, 0};
};

}  // namespace

std::unique_ptr<WgcWindowCapture> WgcWindowCapture::Start(void* hwnd,
                                                          FrameCallback callback,
                                                          void* user_data) {
  if (!hwnd || !callback) {
    return nullptr;
  }
  std::unique_ptr<WgcWindowCaptureImpl> capture(new WgcWindowCaptureImpl(
      reinterpret_cast<HWND>(hwnd), callback, user_data));
  if (!capture->Start()) {
    return nullptr;
  }
  return capture;
}

}  // namespace flutter_webrtc_plugin
