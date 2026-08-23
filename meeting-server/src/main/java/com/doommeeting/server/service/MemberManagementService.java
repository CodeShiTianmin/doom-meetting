package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomMember;
import com.doommeeting.server.enums.RoomEventType;
import com.doommeeting.server.enums.RoomStatus;
import com.doommeeting.server.repository.RoomMemberRepository;
import com.doommeeting.server.repository.RoomRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.Map;
import java.util.UUID;

/**
 * 主持人成员管理: 踢人 / 单人静音 / 全员静音 / 禁止开摄像头 / 等候室审批。
 * 状态落库 + 房间广播, 并尽力调用 LiveKit 服务端 API 立即生效。
 */
@Service
@RequiredArgsConstructor
public class MemberManagementService {

    private final RoomRepository roomRepository;
    private final RoomMemberRepository memberRepository;
    private final RoomService roomService;
    private final MemberService memberService;
    private final EventLogService eventLogService;
    private final NotificationService notificationService;
    private final LiveKitAdminService liveKitAdminService;

    /** 踢出成员: 下线、作废其会话凭证并禁止再次入会 */
    @Transactional
    public void kick(Long roomId, String identity, String operator) {
        Room room = roomService.getRoomById(roomId);
        RoomMember member = requireExistingMember(room, identity);
        member.setKicked(true);
        member.setOnline(false);
        member.setLeftAt(LocalDateTime.now());
        memberService.settleOnlineSeconds(member, LocalDateTime.now());
        // 轮换凭证, 防止被踢成员继续使用旧凭证调用接口
        member.setMemberToken(UUID.randomUUID().toString().replace("-", ""));
        memberRepository.save(member);

        eventLogService.log(room, RoomEventType.MEMBER_KICKED,
                "PC(" + operator + ") 将 " + member.getNickname() + " 移出会议");
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "MEMBER_KICKED", Map.of(
                "identity", member.getIdentity(),
                "nickname", member.getNickname()));
        liveKitAdminService.removeParticipant(room.getRoomCode(), member.getIdentity());
    }

    /** 单人静音/取消静音 */
    @Transactional
    public void mute(Long roomId, String identity, boolean muted, String operator) {
        Room room = roomService.getRoomById(roomId);
        RoomMember member = requireExistingMember(room, identity);
        member.setMuted(muted);
        memberRepository.save(member);

        eventLogService.log(room, RoomEventType.MEMBER_MUTED,
                "PC(" + operator + ") " + (muted ? "静音 " : "取消静音 ") + member.getNickname());
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "MEMBER_MUTED", Map.of(
                "identity", member.getIdentity(),
                "nickname", member.getNickname(),
                "muted", muted));
        liveKitAdminService.muteParticipantTracks(room.getRoomCode(), member.getIdentity(), muted);
    }

    /** 全员静音/解除全员静音 */
    @Transactional
    public void muteAll(Long roomId, boolean muted, String operator) {
        Room room = roomService.getRoomById(roomId);
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭");
        }
        room.setAllMuted(muted);
        roomRepository.save(room);
        for (RoomMember member : memberRepository.findByRoomAndOnlineTrue(room)) {
            member.setMuted(muted);
            memberRepository.save(member);
            liveKitAdminService.muteParticipantTracks(room.getRoomCode(), member.getIdentity(), muted);
        }
        eventLogService.log(room, RoomEventType.MEMBER_MUTED,
                "PC(" + operator + ") " + (muted ? "全员静音" : "解除全员静音"));
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "ALL_MUTED", Map.of("muted", muted));
    }

    /** 禁止/允许成员开启摄像头 */
    @Transactional
    public void setCameraDisabled(Long roomId, String identity, boolean disabled, String operator) {
        Room room = roomService.getRoomById(roomId);
        RoomMember member = requireExistingMember(room, identity);
        member.setCameraDisabled(disabled);
        memberRepository.save(member);

        eventLogService.log(room, RoomEventType.MEMBER_CAMERA_CHANGED,
                "PC(" + operator + ") " + (disabled ? "禁止 " : "允许 ")
                        + member.getNickname() + " 开启摄像头");
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "MEMBER_CAMERA_DISABLED", Map.of(
                "identity", member.getIdentity(),
                "nickname", member.getNickname(),
                "disabled", disabled));
    }

    /** 等候室审批: 批准后成员通过重试 join 正式入会 */
    @Transactional
    public void approve(Long roomId, String identity, boolean approved, String operator) {
        Room room = roomService.getRoomById(roomId);
        RoomMember member = requireExistingMember(room, identity);
        if (approved) {
            member.setApproved(true);
            memberRepository.save(member);
            eventLogService.log(room, RoomEventType.JOIN_APPROVED,
                    "PC(" + operator + ") 批准 " + member.getNickname() + " 入会");
            notificationService.pushToRoomAndAdmin(room.getRoomCode(), "JOIN_APPROVED", Map.of(
                    "identity", member.getIdentity(),
                    "nickname", member.getNickname()));
        } else {
            member.setApproved(false);
            member.setKicked(true);
            member.setMemberToken(UUID.randomUUID().toString().replace("-", ""));
            memberRepository.save(member);
            eventLogService.log(room, RoomEventType.JOIN_REJECTED,
                    "PC(" + operator + ") 拒绝 " + member.getNickname() + " 入会");
            notificationService.pushToRoomAndAdmin(room.getRoomCode(), "JOIN_REJECTED", Map.of(
                    "identity", member.getIdentity(),
                    "nickname", member.getNickname()));
        }
    }

    private RoomMember requireExistingMember(Room room, String identity) {
        return memberRepository.findByRoomAndIdentity(room, identity)
                .orElseThrow(() -> new BusinessException(404, "成员不存在"));
    }
}
