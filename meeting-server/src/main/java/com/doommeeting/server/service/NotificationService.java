package com.doommeeting.server.service;

import com.doommeeting.server.dto.WsEvent;
import lombok.RequiredArgsConstructor;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;

import java.util.Map;

/**
 * 实时推送: 房间频道(手机端) + 管理端看板频道(PC 端)
 */
@Service
@RequiredArgsConstructor
public class NotificationService {

    public static final String ADMIN_DASHBOARD_TOPIC = "/topic/admin/dashboard";

    private final SimpMessagingTemplate messagingTemplate;

    /** 推送到房间内全部手机客户端 */
    public void pushToRoom(String roomCode, String type, Map<String, Object> payload) {
        messagingTemplate.convertAndSend("/topic/rooms/" + roomCode,
                WsEvent.of(type, roomCode, payload));
    }

    /** 推送到管理端(PC)实时看板 */
    public void pushToAdmin(String type, String roomCode, Map<String, Object> payload) {
        messagingTemplate.convertAndSend(ADMIN_DASHBOARD_TOPIC,
                WsEvent.of(type, roomCode, payload));
    }

    /** 同时推送房间与管理端 */
    public void pushToRoomAndAdmin(String roomCode, String type, Map<String, Object> payload) {
        pushToRoom(roomCode, type, payload);
        pushToAdmin(type, roomCode, payload);
    }
}
