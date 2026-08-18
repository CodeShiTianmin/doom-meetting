package com.doommeeting.server.controller;

import com.doommeeting.server.dto.MobileDtos.PlaybackControlRequest;
import com.doommeeting.server.dto.WsEvent;
import com.doommeeting.server.service.NotificationService;
import com.doommeeting.server.service.PlaybackService;
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

    /** SDP/ICE 信令转发(备选自研信令: 客户端间交换 offer/answer/candidate) */
    @MessageMapping("/rooms/{roomCode}/signal")
    public void signal(@DestinationVariable String roomCode,
                       @Payload Map<String, Object> signal) {
        notificationService.pushToRoom(roomCode, "WEBRTC_SIGNAL", signal);
    }

    /** 通用房间事件回声(客户端调试/连通性检测) */
    @MessageMapping("/rooms/{roomCode}/ping")
    public void ping(@DestinationVariable String roomCode) {
        notificationService.pushToRoom(roomCode, "PONG", Map.of());
    }
}
