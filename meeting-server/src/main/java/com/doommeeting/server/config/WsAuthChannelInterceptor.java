package com.doommeeting.server.config;

import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomMember;
import com.doommeeting.server.repository.RoomMemberRepository;
import com.doommeeting.server.repository.RoomRepository;
import com.doommeeting.server.security.JwtService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.MessageDeliveryException;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.stereotype.Component;

import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * STOMP CONNECT/SUBSCRIBE 访问控制:
 * - CONNECT 携带 Authorization: Bearer <管理端JWT> -> 管理端会话, 可订阅全部 topic;
 * - CONNECT 携带 roomCode + identity(入会返回的成员身份) -> 手机端会话, 仅可订阅对应房间 topic;
 * - /topic/admin/** 仅管理端可订阅; /topic/rooms/{roomCode} 需管理端或该房间成员。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class WsAuthChannelInterceptor implements ChannelInterceptor {

    private static final String ADMIN_TOPIC_PREFIX = "/topic/admin/";
    private static final String ROOM_TOPIC_PREFIX = "/topic/rooms/";

    private final JwtService jwtService;
    private final RoomRepository roomRepository;
    private final RoomMemberRepository memberRepository;

    /** sessionId -> 该会话允许订阅的房间号集合; ADMIN 会话用特殊标记 */
    private final Map<String, Set<String>> sessionRooms = new ConcurrentHashMap<>();
    private final Set<String> adminSessions = ConcurrentHashMap.newKeySet();

    @Override
    public Message<?> preSend(Message<?> message, MessageChannel channel) {
        StompHeaderAccessor accessor = StompHeaderAccessor.wrap(message);
        StompCommand command = accessor.getCommand();
        if (command == null) {
            return message;
        }
        String sessionId = accessor.getSessionId();
        switch (command) {
            case CONNECT -> handleConnect(accessor, sessionId);
            case SUBSCRIBE -> handleSubscribe(accessor, sessionId);
            case DISCONNECT -> {
                if (sessionId != null) {
                    sessionRooms.remove(sessionId);
                    adminSessions.remove(sessionId);
                }
            }
            default -> { }
        }
        return message;
    }

    private void handleConnect(StompHeaderAccessor accessor, String sessionId) {
        if (sessionId == null) {
            return;
        }
        String auth = accessor.getFirstNativeHeader("Authorization");
        if (auth != null && auth.startsWith("Bearer ")) {
            try {
                String role = jwtService.parseToken(auth.substring(7)).get("role", String.class);
                if ("ADMIN".equals(role)) {
                    adminSessions.add(sessionId);
                    return;
                }
            } catch (Exception e) {
                throw new MessageDeliveryException("管理端凭证无效");
            }
        }
        String roomCode = accessor.getFirstNativeHeader("roomCode");
        String identity = accessor.getFirstNativeHeader("identity");
        if (roomCode != null && identity != null) {
            Room room = roomRepository.findByRoomCode(roomCode).orElse(null);
            if (room == null) {
                throw new MessageDeliveryException("房间不存在");
            }
            RoomMember member = memberRepository.findByRoomAndIdentity(room, identity).orElse(null);
            if (member == null) {
                throw new MessageDeliveryException("非房间成员, 禁止连接");
            }
            sessionRooms.computeIfAbsent(sessionId, k -> new HashSet<>()).add(roomCode);
        }
        // 未携带任何凭证的连接允许建立, 但后续订阅受限
    }

    private void handleSubscribe(StompHeaderAccessor accessor, String sessionId) {
        String destination = accessor.getDestination();
        if (destination == null || sessionId == null) {
            return;
        }
        if (adminSessions.contains(sessionId)) {
            return;
        }
        if (destination.startsWith(ADMIN_TOPIC_PREFIX)) {
            throw new MessageDeliveryException("管理端 topic 需要管理员凭证");
        }
        if (destination.startsWith(ROOM_TOPIC_PREFIX)) {
            String roomCode = destination.substring(ROOM_TOPIC_PREFIX.length());
            int slash = roomCode.indexOf('/');
            if (slash > 0) {
                roomCode = roomCode.substring(0, slash);
            }
            Set<String> allowed = sessionRooms.get(sessionId);
            if (allowed == null || !allowed.contains(roomCode)) {
                throw new MessageDeliveryException("未认证的房间订阅: " + roomCode);
            }
        }
    }
}
