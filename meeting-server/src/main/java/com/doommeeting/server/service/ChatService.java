package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.dto.MobileDtos.ChatMessageResponse;
import com.doommeeting.server.entity.ChatMessage;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomMember;
import com.doommeeting.server.enums.RoomEventType;
import com.doommeeting.server.enums.RoomStatus;
import com.doommeeting.server.repository.ChatMessageRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * 会中文字聊天/表情: 复用房间 STOMP 通道 /topic/rooms/{code} 广播,
 * 内容持久化, 支持中文与 emoji(UTF-8)。
 */
@Service
@RequiredArgsConstructor
public class ChatService {

    private final ChatMessageRepository chatMessageRepository;
    private final RoomService roomService;
    private final MemberService memberService;
    private final EventLogService eventLogService;
    private final NotificationService notificationService;

    /** 手机端成员发送(校验会话级凭证) */
    @Transactional
    public ChatMessageResponse sendAsMember(String roomCode, String identity,
                                            String memberToken, String content) {
        Room room = roomService.getRoomByCode(roomCode);
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭, 无法发送消息");
        }
        RoomMember member = memberService.requireOnlineMember(room, identity, memberToken);
        return send(room, member.getIdentity(), member.getNickname(), content);
    }

    /** PC 管理端以主持人身份发送 */
    @Transactional
    public ChatMessageResponse sendAsAdmin(Long roomId, String operator, String content) {
        Room room = roomService.getRoomById(roomId);
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭, 无法发送消息");
        }
        return send(room, "admin-" + operator, "主持人", content);
    }

    private ChatMessageResponse send(Room room, String senderIdentity,
                                     String senderNickname, String content) {
        String trimmed = content == null ? "" : content.trim();
        if (trimmed.isEmpty()) {
            throw new BusinessException("消息内容不能为空");
        }
        if (trimmed.length() > 500) {
            throw new BusinessException("消息最长 500 字");
        }
        ChatMessage message = new ChatMessage();
        message.setRoom(room);
        message.setSenderIdentity(senderIdentity);
        message.setSenderNickname(senderNickname);
        message.setContent(trimmed);
        chatMessageRepository.save(message);

        eventLogService.log(room, RoomEventType.CHAT_MESSAGE, senderNickname + " 发送消息");
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "CHAT_MESSAGE", Map.of(
                "id", message.getId(),
                "identity", senderIdentity,
                "nickname", senderNickname,
                "content", trimmed,
                "sentAt", String.valueOf(message.getCreatedAt())));
        return toResponse(message);
    }

    /** 手机端拉取最近 100 条历史(校验成员凭证) */
    @Transactional(readOnly = true)
    public List<ChatMessageResponse> history(String roomCode, String identity, String memberToken) {
        Room room = roomService.getRoomByCode(roomCode);
        memberService.requireMember(room, identity, memberToken);
        return historyOf(room);
    }

    /** PC 管理端拉取历史 */
    @Transactional(readOnly = true)
    public List<ChatMessageResponse> historyByRoomId(Long roomId) {
        return historyOf(roomService.getRoomById(roomId));
    }

    private List<ChatMessageResponse> historyOf(Room room) {
        List<ChatMessage> messages =
                new ArrayList<>(chatMessageRepository.findTop100ByRoomOrderByCreatedAtDesc(room));
        Collections.reverse(messages);
        return messages.stream().map(this::toResponse).toList();
    }

    private ChatMessageResponse toResponse(ChatMessage message) {
        return new ChatMessageResponse(
                message.getId(),
                message.getSenderIdentity(),
                message.getSenderNickname(),
                message.getContent(),
                message.getCreatedAt());
    }
}
