package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.dto.ChatDtos.ChatMessageResponse;
import com.doommeeting.server.entity.ChatMessage;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomMember;
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
 * 文字聊天: 手机端成员/PC 管理端发送 -> 入库 -> WS 实时同步到房间与管理端
 */
@Service
@RequiredArgsConstructor
public class ChatService {

    private final ChatMessageRepository chatRepository;
    private final RoomService roomService;
    private final MemberService memberService;
    private final NotificationService notificationService;

    /** 手机端成员发送聊天消息 */
    @Transactional
    public ChatMessageResponse sendFromMember(String roomCode, String identity,
                                              String memberToken, String content) {
        Room room = roomService.getRoomByCode(roomCode);
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭, 无法发送消息");
        }
        RoomMember member = memberService.requireOnlineMember(room, identity, memberToken);
        return save(room, member.getIdentity(), member.getNickname(), false, content);
    }

    /** PC 管理端发送聊天消息 */
    @Transactional
    public ChatMessageResponse sendFromAdmin(Long roomId, String operator, String content) {
        Room room = roomService.getRoomById(roomId);
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭, 无法发送消息");
        }
        return save(room, operator, operator, true, content);
    }

    /** 房间聊天记录(按时间正序, 最多50条) */
    @Transactional(readOnly = true)
    public List<ChatMessageResponse> historyByRoomCode(String roomCode) {
        return history(roomService.getRoomByCode(roomCode));
    }

    @Transactional(readOnly = true)
    public List<ChatMessageResponse> historyByRoomId(Long roomId) {
        return history(roomService.getRoomById(roomId));
    }

    private List<ChatMessageResponse> history(Room room) {
        List<ChatMessageResponse> list = new ArrayList<>(
                chatRepository.findTop50ByRoomOrderByIdDesc(room).stream()
                        .map(this::toResponse).toList());
        Collections.reverse(list);
        return list;
    }

    private ChatMessageResponse save(Room room, String identity, String nickname,
                                     boolean fromAdmin, String content) {
        String trimmed = content.trim();
        if (trimmed.isEmpty()) {
            throw new BusinessException("消息内容不能为空");
        }
        ChatMessage message = new ChatMessage();
        message.setRoom(room);
        message.setSenderIdentity(identity);
        message.setSenderNickname(nickname);
        message.setFromAdmin(fromAdmin);
        message.setContent(trimmed);
        chatRepository.save(message);

        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "CHAT_MESSAGE", Map.of(
                "id", message.getId(),
                "identity", identity,
                "nickname", nickname,
                "fromAdmin", fromAdmin,
                "content", trimmed,
                "sentAt", String.valueOf(message.getSentAt())));
        return toResponse(message);
    }

    private ChatMessageResponse toResponse(ChatMessage message) {
        return new ChatMessageResponse(
                message.getId(),
                message.getSenderIdentity(),
                message.getSenderNickname(),
                message.getFromAdmin(),
                message.getContent(),
                message.getSentAt());
    }
}
