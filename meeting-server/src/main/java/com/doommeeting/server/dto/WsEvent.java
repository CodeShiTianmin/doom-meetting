package com.doommeeting.server.dto;

import java.time.LocalDateTime;
import java.util.Map;

/**
 * WebSocket 实时事件统一载体
 */
public record WsEvent(
        String type,
        String roomCode,
        Map<String, Object> payload,
        LocalDateTime timestamp) {

    public static WsEvent of(String type, String roomCode, Map<String, Object> payload) {
        return new WsEvent(type, roomCode, payload, LocalDateTime.now());
    }
}
