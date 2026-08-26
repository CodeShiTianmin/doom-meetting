package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.dto.ChatDtos.ChatMessageResponse;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomMember;
import com.doommeeting.server.enums.RoomStatus;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 房间文字聊天: 内存保存近 100 条, 通过房间 STOMP 主题实时广播("CHAT" 事件)。
 */
@Service
@RequiredArgsConstructor
public class ChatService {

    private static final int MAX_HISTORY = 100;

    private final RoomService roomService;
    private final MemberService memberService;
    private final NotificationService notificationService;

    private final Map<String, Deque<ChatMessageResponse>> history = new ConcurrentHashMap<>();

    /** 手机端发送聊天消息(校验成员凭证) */
    public ChatMessageResponse sendFromMember(String roomCode, String identity,
                                              String memberToken, String content) {
        Room room = roomService.getRoomByCode(roomCode);
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭, 无法发送消息");
        }
        RoomMember member = memberService.requireOnlineMember(room, identity, memberToken);
        return append(room.getRoomCode(),
                new ChatMessageResponse(member.getNickname(), member.getIdentity(),
                        content.trim(), false, LocalDateTime.now()));
    }

    /** PC 管理端发送聊天消息 */
    public ChatMessageResponse sendFromAdmin(Long roomId, String operator, String content) {
        Room room = roomService.getRoomById(roomId);
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭, 无法发送消息");
        }
        return append(room.getRoomCode(),
                new ChatMessageResponse(operator, null, content.trim(), true, LocalDateTime.now()));
    }

    /** 近期聊天记录(时间正序) */
    public List<ChatMessageResponse> recent(String roomCode) {
        Deque<ChatMessageResponse> deque = history.get(roomCode);
        if (deque == null) {
            return List.of();
        }
        synchronized (deque) {
            return new ArrayList<>(deque);
        }
    }

    public List<ChatMessageResponse> recentByRoomId(Long roomId) {
        return recent(roomService.getRoomById(roomId).getRoomCode());
    }

    /** 房间关闭/删除时清理内存聊天记录 */
    public void clear(String roomCode) {
        history.remove(roomCode);
    }

    private ChatMessageResponse append(String roomCode, ChatMessageResponse message) {
        Deque<ChatMessageResponse> deque =
                history.computeIfAbsent(roomCode, key -> new ArrayDeque<>());
        synchronized (deque) {
            deque.addLast(message);
            while (deque.size() > MAX_HISTORY) {
                deque.removeFirst();
            }
        }
        Map<String, Object> payload = new HashMap<>();
        payload.put("sender", message.sender());
        if (message.identity() != null) {
            payload.put("identity", message.identity());
        }
        payload.put("content", message.content());
        payload.put("fromAdmin", message.fromAdmin());
        payload.put("sentAt", String.valueOf(message.sentAt()));
        notificationService.pushToRoomAndAdmin(roomCode, "CHAT", payload);
        return message;
    }
}
