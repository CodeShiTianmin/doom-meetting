package com.doommeeting.server.event;

/**
 * 房间关闭事件(手动结束/重置/删除/到期), 供依赖 RoomService 的服务清理该房间的内存状态,
 * 避免与 RoomService 形成循环依赖。
 */
public record RoomClosedEvent(Long roomId, String roomCode) {
}
