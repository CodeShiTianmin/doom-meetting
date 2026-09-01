package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.dto.LikeDtos.LikeRecordResponse;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomLike;
import com.doommeeting.server.entity.RoomMember;
import com.doommeeting.server.enums.RoomEventType;
import com.doommeeting.server.enums.RoomStatus;
import com.doommeeting.server.repository.RoomLikeRepository;
import com.doommeeting.server.repository.RoomRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataIntegrityViolationException;
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
    private final MemberService memberService;
    private final RoomLikeRepository likeRepository;
    private final RoomService roomService;
    private final EventLogService eventLogService;
    private final NotificationService notificationService;

    @Transactional
    public long like(String roomCode, String identity, String memberToken) {
        // 行锁串行化同一房间的点赞计数, 避免并发 read-increment-write 丢失更新
        Room room = roomRepository.findByRoomCodeForUpdate(roomCode)
                .orElseThrow(() -> new BusinessException(404, "房间不存在"));
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭, 无法点赞");
        }
        RoomMember member = memberService.requireOnlineMember(room, identity, memberToken);
        if (likeRepository.countByRoomAndMemberIdentity(room, member.getIdentity()) > 0) {
            throw new BusinessException(409, "每人仅可点赞一次");
        }

        RoomLike like = new RoomLike();
        like.setRoom(room);
        like.setMemberIdentity(member.getIdentity());
        like.setNickname(member.getNickname());
        try {
            likeRepository.saveAndFlush(like);
        } catch (DataIntegrityViolationException e) {
            // 并发重复点赞由唯一约束兑底
            throw new BusinessException(409, "每人仅可点赞一次");
        }

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
