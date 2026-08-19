package com.doommeeting.server.enums;

/**
 * 房间事件类型(元数据日志 + 实时推送)
 */
public enum RoomEventType {
    ROOM_CREATED,
    MEMBER_JOINED,
    MEMBER_LEFT,
    ROOM_RUNNING,
    ROOM_CLOSED,
    PLAYBACK_CONTROL,
    CONTENT_CAST,
    CAST_STOPPED,
    LIKE,
    COUNTDOWN_REMINDER,
    UNDERSTAFFED_ALERT,
    UNDERSTAFFED_RECOVERED,
    RECORDING_DETECTED,
    SETTINGS_CHANGED
}
