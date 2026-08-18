/**
 * 录屏防护(允许截屏, 禁止录制):
 * 不使用会连截屏一起禁掉的 FLAG_SECURE 方案, 改为"录屏检测 + 遮挡上报"。
 * Web 端为尽力而为方案:
 * 1. 拦截页面内 getDisplayMedia 屏幕采集请求(拒绝并上报)
 * 2. 检测 MediaRecorder 对页面媒体流的录制(拒绝并上报)
 * 原生 App 端(Android 15+ ScreenRecordingCallback / iOS UIScreen.isCaptured)
 * 通过 WebView 桥接 window.__nativeRecordingDetected 回调接入同一处理链路。
 */
export function installRecordingGuard(onDetected) {
  const restorers = []

  if (navigator.mediaDevices && navigator.mediaDevices.getDisplayMedia) {
    const original = navigator.mediaDevices.getDisplayMedia.bind(navigator.mediaDevices)
    navigator.mediaDevices.getDisplayMedia = () => {
      onDetected('页面内屏幕采集请求(getDisplayMedia)被拦截')
      return Promise.reject(new DOMException('会议内容禁止录制', 'NotAllowedError'))
    }
    restorers.push(() => {
      navigator.mediaDevices.getDisplayMedia = original
    })
  }

  if (typeof window.MediaRecorder === 'function') {
    const OriginalRecorder = window.MediaRecorder
    function GuardedRecorder() {
      onDetected('检测到 MediaRecorder 录制请求, 已拦截')
      throw new DOMException('会议内容禁止录制', 'NotAllowedError')
    }
    GuardedRecorder.isTypeSupported = OriginalRecorder.isTypeSupported?.bind(OriginalRecorder)
    window.MediaRecorder = GuardedRecorder
    restorers.push(() => {
      window.MediaRecorder = OriginalRecorder
    })
  }

  // 原生壳(Android/iOS WebView)录屏检测回调桥
  window.__nativeRecordingDetected = (detail) => {
    onDetected(detail || '系统级录屏行为(原生检测)')
  }
  restorers.push(() => {
    delete window.__nativeRecordingDetected
  })

  return () => restorers.forEach((restore) => restore())
}
