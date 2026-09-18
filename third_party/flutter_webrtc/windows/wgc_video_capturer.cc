#include <windows.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdlib>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "rtc_video_frame.h"
#include "wgc_window_capture.h"
#include "window_frame_capturer.h"

namespace flutter_webrtc_plugin {

namespace {

// When the captured window stops repainting (paused video, static slide)
// WGC delivers no new frames. Re-send the last frame at this interval so the
// encoder keeps producing key frames and late-joining viewers get a picture.
constexpr int kKeepAliveIntervalMs = 500;

inline uint8_t ClampToByte(int value) {
  if (value < 0) return 0;
  if (value > 255) return 255;
  return static_cast<uint8_t>(value);
}

// BT.601 limited range BGRA -> I420. |width| and |height| must be even.
void ConvertBgraToI420(const uint8_t* bgra,
                       int stride,
                       int width,
                       int height,
                       uint8_t* y_plane,
                       uint8_t* u_plane,
                       uint8_t* v_plane) {
  const int chroma_width = width / 2;
  for (int row = 0; row < height; row += 2) {
    const uint8_t* line0 = bgra + static_cast<size_t>(row) * stride;
    const uint8_t* line1 = line0 + stride;
    uint8_t* y0 = y_plane + static_cast<size_t>(row) * width;
    uint8_t* y1 = y0 + width;
    uint8_t* u = u_plane + static_cast<size_t>(row / 2) * chroma_width;
    uint8_t* v = v_plane + static_cast<size_t>(row / 2) * chroma_width;
    for (int col = 0; col < width; col += 2) {
      int sum_r = 0;
      int sum_g = 0;
      int sum_b = 0;
      const uint8_t* pixels[4] = {line0 + col * 4, line0 + (col + 1) * 4,
                                  line1 + col * 4, line1 + (col + 1) * 4};
      uint8_t* ys[4] = {y0 + col, y0 + col + 1, y1 + col, y1 + col + 1};
      for (int i = 0; i < 4; ++i) {
        const int b = pixels[i][0];
        const int g = pixels[i][1];
        const int r = pixels[i][2];
        sum_r += r;
        sum_g += g;
        sum_b += b;
        *ys[i] = ClampToByte(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
      }
      const int avg_r = sum_r / 4;
      const int avg_g = sum_g / 4;
      const int avg_b = sum_b / 4;
      u[col / 2] = ClampToByte(
          ((-38 * avg_r - 74 * avg_g + 112 * avg_b + 128) >> 8) + 128);
      v[col / 2] = ClampToByte(
          ((112 * avg_r - 94 * avg_g - 18 * avg_b + 128) >> 8) + 128);
    }
  }
}

class WgcVideoCapturer : public WindowFrameCapturer {
 public:
  WgcVideoCapturer(HWND hwnd,
                   uint32_t fps,
                   scoped_refptr<RTCVideoSource> video_source)
      : hwnd_(hwnd),
        min_frame_interval_ms_(fps > 0 ? 1000 / static_cast<int>(fps) : 33),
        video_source_(video_source) {}

  ~WgcVideoCapturer() override { StopCapture(); }

  bool StartCapture() override {
    if (capture_) {
      return true;
    }
    capture_ = WgcWindowCapture::Start(hwnd_, &WgcVideoCapturer::OnFrameThunk,
                                       this);
    if (!capture_) {
      return false;
    }
    stop_keepalive_ = false;
    keepalive_thread_ = std::thread([this]() { KeepAliveLoop(); });
    return true;
  }

  bool CaptureStarted() override { return capture_ != nullptr; }

  void StopCapture() override {
    {
      std::lock_guard<std::mutex> lock(keepalive_mutex_);
      stop_keepalive_ = true;
    }
    keepalive_cv_.notify_all();
    if (keepalive_thread_.joinable()) {
      keepalive_thread_.join();
    }
    if (capture_) {
      capture_->Stop();
      capture_.reset();
    }
    if (loopback_) {
      loopback_->Stop();
      loopback_.reset();
    }
    loopback_source_ = nullptr;
  }

  void AttachLoopback(std::unique_ptr<LoopbackCapturer> capturer,
                      scoped_refptr<RTCAudioSource> source) override {
    loopback_ = std::move(capturer);
    loopback_source_ = source;
  }

 private:
  static void OnFrameThunk(void* user_data,
                           const uint8_t* bgra,
                           int width,
                           int height,
                           int stride) {
    static_cast<WgcVideoCapturer*>(user_data)->OnFrame(bgra, width, height,
                                                       stride);
  }

  static int64_t NowMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
  }

  void OnFrame(const uint8_t* bgra, int width, int height, int stride) {
    // I420 needs even dimensions; drop the last row/column when odd.
    width &= ~1;
    height &= ~1;
    if (width < 2 || height < 2 || stride < width * 4) {
      return;
    }

    std::lock_guard<std::mutex> lock(frame_mutex_);
    const int64_t now = NowMs();
    if (last_delivered_ms_ != 0 &&
        now - last_delivered_ms_ < min_frame_interval_ms_ - 2) {
      return;
    }

    const size_t y_size = static_cast<size_t>(width) * height;
    const size_t chroma_size = y_size / 4;
    y_plane_.resize(y_size);
    u_plane_.resize(chroma_size);
    v_plane_.resize(chroma_size);
    ConvertBgraToI420(bgra, stride, width, height, y_plane_.data(),
                      u_plane_.data(), v_plane_.data());
    frame_width_ = width;
    frame_height_ = height;
    DeliverLocked(now);
  }

  // Requires frame_mutex_.
  void DeliverLocked(int64_t now) {
    if (frame_width_ <= 0 || frame_height_ <= 0 || !video_source_) {
      return;
    }
    scoped_refptr<RTCVideoFrame> frame = RTCVideoFrame::Create(
        frame_width_, frame_height_, y_plane_.data(), frame_width_,
        u_plane_.data(), frame_width_ / 2, v_plane_.data(), frame_width_ / 2);
    if (!frame) {
      return;
    }
    video_source_->OnCapturedFrame(frame);
    last_delivered_ms_ = now;
  }

  void KeepAliveLoop() {
    std::unique_lock<std::mutex> lock(keepalive_mutex_);
    while (!stop_keepalive_) {
      keepalive_cv_.wait_for(lock,
                             std::chrono::milliseconds(kKeepAliveIntervalMs));
      if (stop_keepalive_) {
        break;
      }
      lock.unlock();
      {
        std::lock_guard<std::mutex> frame_lock(frame_mutex_);
        const int64_t now = NowMs();
        if (last_delivered_ms_ != 0 &&
            now - last_delivered_ms_ >= kKeepAliveIntervalMs) {
          DeliverLocked(now);
        }
      }
      lock.lock();
    }
  }

  HWND hwnd_;
  const int min_frame_interval_ms_;
  scoped_refptr<RTCVideoSource> video_source_;
  std::unique_ptr<WgcWindowCapture> capture_;

  std::unique_ptr<LoopbackCapturer> loopback_;
  scoped_refptr<RTCAudioSource> loopback_source_;

  std::mutex frame_mutex_;
  std::vector<uint8_t> y_plane_;
  std::vector<uint8_t> u_plane_;
  std::vector<uint8_t> v_plane_;
  int frame_width_ = 0;
  int frame_height_ = 0;
  int64_t last_delivered_ms_ = 0;

  std::thread keepalive_thread_;
  std::mutex keepalive_mutex_;
  std::condition_variable keepalive_cv_;
  bool stop_keepalive_ = false;
};

}  // namespace

scoped_refptr<WindowFrameCapturer> CreateWindowFrameCapturer(
    const std::string& source_id,
    uint32_t fps,
    scoped_refptr<RTCVideoSource> video_source) {
  // Screen sources use "0" (or a small display index); window sources carry
  // their HWND as a decimal string.
  if (source_id.empty() || source_id == "0" || !video_source) {
    return nullptr;
  }
  char* end = nullptr;
  const unsigned long long raw = std::strtoull(source_id.c_str(), &end, 10);
  if (end == nullptr || *end != '\0' || raw == 0) {
    return nullptr;
  }
  HWND hwnd = reinterpret_cast<HWND>(static_cast<uintptr_t>(raw));
  if (!IsWindow(hwnd)) {
    return nullptr;
  }
  return new RefCountedObject<WgcVideoCapturer>(hwnd, fps, video_source);
}

}  // namespace flutter_webrtc_plugin
