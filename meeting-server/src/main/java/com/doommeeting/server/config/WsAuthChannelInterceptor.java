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

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * STOMP CONNECT/SUBSCRIBE 访问控制:
 * - CONNECT 携带 Authorization: Bearer <管理端JWT> -> 管理端会话, 可订阅全部 topic;
 * - CONNECT 携带 roomCode + identity + memberToken(入会签发的会话级凭证) -> 手机端会话, 仅可订阅对应房间 topic;
 * - /topic/admin/** 仅管理端可订阅; /topic/rooms/{roomCode} 需管理端或该房间成员;
 * - SUBSCRIBE 时按当前数据库状态重新校验成员凭证/踢出/审批, 不信任 CONNECT 时的缓存结论。
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

    /** 成员会话在 CONNECT 时提交的凭证, SUBSCRIBE 时用于重新查库校验 */
    private record MemberCredential(String identity, String memberToken) {}

    /** sessionId -> roomCode -> 成员凭证 */
    private final Map<String, Map<String, MemberCredential>> sessionCredentials = new ConcurrentHashMap<>();
    /** sessionId -> 管理端 JWT(SUBSCRIBE 时重新校验有效期) */
    private final Map<String, String> adminTokens = new ConcurrentHashMap<>();

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
                    sessionCredentials.remove(sessionId);
                    adminTokens.remove(sessionId);
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
            String token = auth.substring(7);
            requireAdminToken(token);
            adminTokens.put(sessionId, token);
            return;
        }
        String roomCode = accessor.getFirstNativeHeader("roomCode");
        String identity = accessor.getFirstNativeHeader("identity");
        String memberToken = accessor.getFirstNativeHeader("memberToken");
        if (roomCode != null && identity != null) {
            requireValidMember(roomCode, identity, memberToken);
            sessionCredentials.computeIfAbsent(sessionId, k -> new ConcurrentHashMap<>())
                    .put(roomCode, new MemberCredential(identity, memberToken));
        }
        // 未携带任何凭证的连接允许建立, 但后续订阅受限
    }

    private void handleSubscribe(StompHeaderAccessor accessor, String sessionId) {
        String destination = accessor.getDestination();
        if (destination == null || sessionId == null) {
            return;
        }
        String adminToken = adminTokens.get(sessionId);
        if (adminToken != null) {
            // 重新校验管理端 JWT(过期后拒绝新订阅)
            try {
                requireAdminToken(adminToken);
                return;
            } catch (MessageDeliveryException e) {
                adminTokens.remove(sessionId);
                throw e;
            }
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
            Map<String, MemberCredential> credentials = sessionCredentials.get(sessionId);
            MemberCredential credential = credentials == null ? null : credentials.get(roomCode);
            if (credential == null) {
                throw new MessageDeliveryException("未认证的房间订阅: " + roomCode);
            }
            // 按当前数据库状态重新校验: 凭证轮换/被踢/审批被拒后立即失效
            requireValidMember(roomCode, credential.identity(), credential.memberToken());
        }
    }

    private void requireAdminToken(String token) {
        try {
            String role = jwtService.parseToken(token).get("role", String.class);
            if (!"ADMIN".equals(role)) {
                throw new MessageDeliveryException("管理端凭证无效");
            }
        } catch (MessageDeliveryException e) {
            throw e;
        } catch (Exception e) {
            throw new MessageDeliveryException("管理端凭证无效");
        }
    }

    private void requireValidMember(String roomCode, String identity, String memberToken) {
        Room room = roomRepository.findByRoomCode(roomCode).orElse(null);
        if (room == null) {
            throw new MessageDeliveryException("房间不存在");
        }
        RoomMember member = memberRepository.findByRoomAndIdentity(room, identity).orElse(null);
        if (member == null) {
            throw new MessageDeliveryException("非房间成员, 禁止连接");
        }
        // 会话级凭证校验: 仅知道房间码/广播可见的 identity 无法订阅房间事件
        if (memberToken == null || !memberToken.equals(member.getMemberToken())) {
            throw new MessageDeliveryException("成员凭证无效, 禁止连接");
        }
        // 审批被拒/被踢均置 kicked=true 并轮换 memberToken, 上面两项校验已覆盖;
        // 等候室待审批成员允许订阅(需接收 JOIN_APPROVED/JOIN_REJECTED 事件)
        if (Boolean.TRUE.equals(member.getKicked())) {
            throw new MessageDeliveryException("已被移出会议, 禁止连接");
        }
    }
}
