package com.doommeeting.server.enums;

/**
 * 房间状态: 等待就位 -> 运行中 -> 已关闭
 */
public enum RoomStatus {
    /** 等待就位: 房间已创建, 等待 2 个手机客户端全部入会 */
    WAITING,
    /** 运行中: 2 个手机客户端已就位, 会议计时开始 */
    RUNNING,
    /** 已关闭: 手动结束或会议时长到期自动关闭 */
    CLOSED
}
