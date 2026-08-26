package com.doommeeting.server.enums;

/**
 * PC 端实时推流投放类型(全部走 LiveKit 实时流, 无服务器文件)
 */
public enum CastType {
    /** 屏幕/窗口共享 */
    SCREEN,
    /** 本地视频文件推流 */
    VIDEO,
    /** 摄像头推流 */
    CAMERA
}
