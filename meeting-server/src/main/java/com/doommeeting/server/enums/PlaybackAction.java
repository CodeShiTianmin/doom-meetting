package com.doommeeting.server.enums;

/**
 * 手机端播放控制指令(明暗/音量为手机本地调节, 也上报用于状态展示)
 */
public enum PlaybackAction {
    PLAY,
    PAUSE,
    SEEK,
    BRIGHTNESS,
    VOLUME
}
