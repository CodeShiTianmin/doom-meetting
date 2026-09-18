#ifndef WGC_WINDOW_CAPTURE_H_
#define WGC_WINDOW_CAPTURE_H_

#include <cstdint>
#include <memory>

namespace flutter_webrtc_plugin {

// Windows.Graphics.Capture (WGC) based capturer for a single top-level
// window. Unlike the GDI/DXGI window capturers inside libwebrtc, WGC reads
// the composited surface of the window straight from DWM, so windows that
// are covered, partially off-screen or rendered through a hardware video
// pipeline (media_kit / libmpv, browsers, games) are captured correctly
// instead of producing black frames.
//
// Frames are delivered as top-down 32-bit BGRA on a capture thread. The
// buffer is only valid for the duration of the callback.
//
// The implementation is compiled in its own static library with C++/WinRT
// enabled so that the main plugin target keeps the standard Flutter compile
// settings.
class WgcWindowCapture {
 public:
  typedef void (*FrameCallback)(void* user_data,
                                const uint8_t* bgra,
                                int width,
                                int height,
                                int stride);

  virtual ~WgcWindowCapture() = default;

  // Starts capturing the window identified by |hwnd| (a raw HWND). Returns
  // nullptr when capture is unavailable (Windows < 10 1903, invalid window,
  // Direct3D failure). |callback| is invoked from a capture thread until
  // Stop() returns.
  static std::unique_ptr<WgcWindowCapture> Start(void* hwnd,
                                                 FrameCallback callback,
                                                 void* user_data);

  // Stops capture and releases all Direct3D/WinRT resources. Safe to call
  // more than once. No callbacks are delivered after Stop() returns.
  virtual void Stop() = 0;
};

}  // namespace flutter_webrtc_plugin

#endif  // WGC_WINDOW_CAPTURE_H_
