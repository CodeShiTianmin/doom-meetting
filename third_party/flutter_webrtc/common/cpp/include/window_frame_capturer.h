#ifndef WINDOW_FRAME_CAPTURER_H_
#define WINDOW_FRAME_CAPTURER_H_

#include <memory>
#include <string>

#include "loopback_capturer.h"
#include "rtc_audio_source.h"
#include "rtc_types.h"
#include "rtc_video_device.h"
#include "rtc_video_source.h"

namespace flutter_webrtc_plugin {

using namespace libwebrtc;

// Platform window capturer that feeds frames into a custom RTCVideoSource,
// bypassing libwebrtc's built-in desktop capturers. Used for getDisplayMedia
// on window sources where the built-in capturer cannot read the window
// surface (hardware-accelerated video players, off-screen windows) and
// would otherwise deliver black frames.
//
// Registered in FlutterWebRTCBase::video_capturers_ so that disposing the
// video track stops capture (and the attached loopback audio) like any
// other capturer.
class WindowFrameCapturer : public RTCVideoCapturer {
 public:
  // Takes ownership of the loopback audio capturer that belongs to this
  // capture session; it is stopped together with the video capture.
  virtual void AttachLoopback(std::unique_ptr<LoopbackCapturer> capturer,
                              scoped_refptr<RTCAudioSource> source) = 0;
};

// Creates the platform capturer for |source_id| (Windows: HWND as decimal
// string). Returns nullptr when the platform has no implementation or the
// source id is not a window. The returned capturer is not started.
//
// Implemented in:
//   windows/wgc_video_capturer.cc — Windows.Graphics.Capture
// All other platforms: inline null implementation below.
#if defined(_WIN32)
scoped_refptr<WindowFrameCapturer> CreateWindowFrameCapturer(
    const std::string& source_id,
    uint32_t fps,
    scoped_refptr<RTCVideoSource> video_source);
#else
inline scoped_refptr<WindowFrameCapturer> CreateWindowFrameCapturer(
    const std::string& /*source_id*/,
    uint32_t /*fps*/,
    scoped_refptr<RTCVideoSource> /*video_source*/) {
  return nullptr;
}
#endif

}  // namespace flutter_webrtc_plugin

#endif  // WINDOW_FRAME_CAPTURER_H_
