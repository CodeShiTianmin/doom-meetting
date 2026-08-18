package com.doommeeting.server.controller;

import com.doommeeting.server.dto.MobileDtos.PlaybackControlRequest;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomMember;
import com.doommeeting.server.repository.RoomMemberRepository;
import com.doommeeting.server.service.NotificationService;
import com.doommeeting.server.service.PlaybackService;
import com.doommeeting.server.service.RoomService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.handler.annotation.DestinationVariable;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Controller;

import java.util.Map;

/**
 * STOMP 信令入口:
 * - 播放控制指令(WS 通道, 与 REST 等效)
 * - WebRTC SDP/ICE 转发(自研信令备选方案, LiveKit 场景下由其自带信令处理)
 */
@Slf4j
@Controller
@RequiredArgsConstructor
public class SignalingController {

    private final PlaybackService playbackService;
    private final NotificationService notificationService;
    private final RoomService roomService;
    private final RoomMemberRepository memberRepository;

    /** 手机端经 WS 发送播放控制指令 */
    @MessageMapping("/rooms/{roomCode}/playback")
    public void playback(@DestinationVariable String roomCode,
                         @Payload PlaybackControlRequest request) {
        try {
            playbackService.control(roomCode, request);
        } catch (Exception e) {
            log.warn("房间 {} 播放控制失败: {}", roomCode, e.getMessage());
        }
    }

    /** SDP/ICE 信令转发(备选自研信令: 客户端间交换 offer/answer/candidate), 仅限房间在线成员 */
    @MessageMapping("/rooms/{roomCode}/signal")
    public void signal(@DestinationVariable String roomCode,
                       @Payload Map<String, Object> signal) {
        Object identity = signal.get("identity");
        if (!(identity instanceof String senderIdentity) || senderIdentity.isBlank()) {
            log.warn("房间 {} 信令缺少发送者身份, 已丢弃", roomCode);
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
        notificationService.pushToRoom(roomCode, "WEBRTC_SIGNAL", signal);
    }

    /** 通用房间事件回声(客户端调试/连通性检测) */
    @MessageMapping("/rooms/{roomCode}/ping")
    public void ping(@DestinationVariable String roomCode) {
        notificationService.pushToRoom(roomCode, "PONG", Map.of());
    }
}
