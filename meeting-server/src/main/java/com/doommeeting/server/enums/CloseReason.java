package com.doommeeting.server.enums;

/**
 * 房间关闭原因
 */
public enum CloseReason {
    /** PC 端手动结束会议 */
    MANUAL,
    /** 会议时长到期自动关闭 */
    TIMEOUT
}
