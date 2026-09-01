package com.doommeeting.server.controller;

import com.doommeeting.server.config.WsAuthChannelInterceptor;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomMember;
import com.doommeeting.server.repository.RoomMemberRepository;
import com.doommeeting.server.service.NotificationService;
import com.doommeeting.server.service.RoomService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.handler.annotation.DestinationVariable;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Controller;

import java.util.HashMap;
import java.util.Map;

/**
 * STOMP 信令入口:
 * - WebRTC SDP/ICE 转发(自研信令备选方案, LiveKit 场景下由其自带信令处理)
 * 发送权限由 {@link WsAuthChannelInterceptor} 在 SEND 时校验, 这里只负责补全可信的发送者身份。
 */
@Slf4j
@Controller
@RequiredArgsConstructor
public class SignalingController {

    private final NotificationService notificationService;
    private final RoomService roomService;
    private final RoomMemberRepository memberRepository;
    private final WsAuthChannelInterceptor wsAuthChannelInterceptor;

    /** SDP/ICE 信令转发(备选自研信令: 客户端间交换 offer/answer/candidate), 仅限房间在线成员 */
    @MessageMapping("/rooms/{roomCode}/signal")
    public void signal(@DestinationVariable String roomCode,
                       @Header("simpSessionId") String sessionId,
                       @Payload Map<String, Object> signal) {
        String senderIdentity = resolveSender(roomCode, sessionId, signal.get("identity"));
        if (senderIdentity == null) {
            log.warn("房间 {} 信令缺少可信发送者身份, 已丢弃", roomCode);
            return;
        }
        Room room;
        try {
            room = roomService.getRoomByCode(roomCode);
        } catch (Exception e) {
            log.warn("房间 {} 不存在, 信令已丢弃", roomCode);
            return;
        }
        boolean onlineMember = memberRepository.findByRoomAndIdentity(room, senderIdentity)
                .map(RoomMember::getOnline)
                .orElse(false);
        if (!onlineMember) {
            log.warn("房间 {} 信令发送者 {} 非在线成员, 已丢弃", roomCode, senderIdentity);
            return;
        }
        Map<String, Object> forwarded = new HashMap<>(signal);
        forwarded.put("identity", senderIdentity);
        notificationService.pushToRoom(roomCode, "WEBRTC_SIGNAL", forwarded);
    }

    /**
     * 发送者身份以 CONNECT 时登记的成员凭证为准, 成员不能冒用他人 identity;
     * 管理端会话没有成员身份, 允许其在 payload 中显式声明。
     */
    private String resolveSender(String roomCode, String sessionId, Object claimed) {
        String authenticated = wsAuthChannelInterceptor.memberIdentityOf(sessionId, roomCode);
        if (authenticated != null) {
            return authenticated;
        }
        if (wsAuthChannelInterceptor.isAdminSession(sessionId)
                && claimed instanceof String claimedIdentity && !claimedIdentity.isBlank()) {
            return claimedIdentity;
        }
        return null;
    }

    /** 通用房间事件回声(客户端调试/连通性检测) */
    @MessageMapping("/rooms/{roomCode}/ping")
    public void ping(@DestinationVariable String roomCode) {
        notificationService.pushToRoom(roomCode, "PONG", Map.of());
    }
}
