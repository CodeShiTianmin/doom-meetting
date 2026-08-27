package com.doommeeting.app

import android.app.PictureInPictureParams
import android.os.Build
import android.util.Rational
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * 防录制原生支持: 允许截屏(不设置 FLAG_SECURE), 禁止录制.
 *
 * - Android 15+ (API 35): registerScreenRecordCallback 精确检测录屏
 * - 检测到录屏时通过 EventChannel 通知 Flutter 层执行遮挡 + 上报
 */
class MainActivity : FlutterActivity() {

    private var eventSink: EventChannel.EventSink? = null
    private var recordCallback: java.util.function.Consumer<Int>? = null
    private var guarding = false
    private var autoPipOnLeave = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.doommeeting/recording_guard"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startGuard" -> {
                    startGuard()
                    result.success(null)
                }
                "stopGuard" -> {
                    stopGuard()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.doommeeting/pip"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAutoPipOnLeave" -> {
                    autoPipOnLeave = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.doommeeting/recording_events"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun startGuard() {
        if (guarding) return
        guarding = true
        // 明确允许截屏: 不设置 WindowManager.LayoutParams.FLAG_SECURE
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)

        if (Build.VERSION.SDK_INT >= 35) {
            val callback = java.util.function.Consumer<Int> { state ->
                if (state == 1) { // SCREEN_RECORDING_STATE_VISIBLE
                    runOnUiThread {
                        eventSink?.success("检测到系统录屏(Android ScreenRecordCallback)")
                    }
                }
            }
            recordCallback = callback
            try {
                windowManager.addScreenRecordingCallback(mainExecutor, callback)
            } catch (_: Throwable) {
                // 设备不支持时忽略, 保留水印与其他兜底手段
            }
        }
    }

    private fun stopGuard() {
        guarding = false
        if (Build.VERSION.SDK_INT >= 35) {
            recordCallback?.let {
                try {
                    windowManager.removeScreenRecordingCallback(it)
                } catch (_: Throwable) {
                }
            }
            recordCallback = null
        }
    }

    /**
     * Android 8~11 不支持 setAutoEnterEnabled(仅 API 31+),
     * 返回桌面/切换应用时在此手动进入画中画悬浮窗.
     */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!autoPipOnLeave) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                enterPictureInPictureMode(
                    PictureInPictureParams.Builder()
                        .setAspectRatio(Rational(16, 9))
                        .build()
                )
            } catch (_: Throwable) {
            }
        }
    }

    override fun onDestroy() {
        stopGuard()
        super.onDestroy()
    }
}
