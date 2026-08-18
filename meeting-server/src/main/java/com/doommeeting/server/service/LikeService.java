package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.dto.LikeDtos.LikeRecordResponse;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomLike;
import com.doommeeting.server.entity.RoomMember;
import com.doommeeting.server.enums.RoomEventType;
import com.doommeeting.server.enums.RoomStatus;
import com.doommeeting.server.repository.RoomLikeRepository;
import com.doommeeting.server.repository.RoomMemberRepository;
import com.doommeeting.server.repository.RoomRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;

/**
 * 点赞: 手机端点赞按钮 -> 实时推送 PC 端展示 -> 后端记录
 */
@Service
@RequiredArgsConstructor
public class LikeService {

    private final RoomRepository roomRepository;
    private final RoomMemberRepository memberRepository;
    private final RoomLikeRepository likeRepository;
    private final RoomService roomService;
    private final EventLogService eventLogService;
    private final NotificationService notificationService;

    @Transactional
    public long like(String roomCode, String identity) {
        Room room = roomService.getRoomByCode(roomCode);
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭, 无法点赞");
        }
        RoomMember member = memberRepository.findByRoomAndIdentity(room, identity)
                .orElseThrow(() -> new BusinessException(403, "非房间成员, 禁止点赞"));
        if (!member.getOnline()) {
            throw new BusinessException(403, "成员已离会, 禁止点赞");
        }

        RoomLike like = new RoomLike();
        like.setRoom(room);
        like.setMemberIdentity(member.getIdentity());
        like.setNickname(member.getNickname());
        likeRepository.save(like);

        room.setLikeCount(room.getLikeCount() + 1);
        roomRepository.save(room);

        eventLogService.log(room, RoomEventType.LIKE, member.getNickname() + " 点赞");
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "LIKE", Map.of(
                "identity", member.getIdentity(),
                "nickname", member.getNickname(),
                "likeCount", room.getLikeCount()));
        return room.getLikeCount();
    }

    @Transactional(readOnly = true)
    public List<LikeRecordResponse> listByRoom(Long roomId) {
        Room room = roomService.getRoomById(roomId);
        return likeRepository.findByRoomOrderByLikedAtDesc(room).stream()
                .map(this::toResponse).toList();
    }

    @Transactional(readOnly = true)
    public List<LikeRecordResponse> listAll() {
        return likeRepository.findAllByOrderByLikedAtDesc().stream()
                .map(this::toResponse).toList();
    }

    private LikeRecordResponse toResponse(RoomLike like) {
        return new LikeRecordResponse(
                like.getId(),
                like.getRoom().getId(),
                like.getRoom().getRoomCode(),
                like.getRoom().getName(),
                like.getMemberIdentity(),
                like.getNickname(),
                like.getLikedAt());
    }
}
