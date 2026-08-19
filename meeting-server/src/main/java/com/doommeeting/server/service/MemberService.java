package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.config.AppProperties;
import com.doommeeting.server.dto.MobileDtos.*;
import com.doommeeting.server.entity.ContentItem;
import com.doommeeting.server.entity.InviteToken;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomMember;
import com.doommeeting.server.enums.RoomEventType;
import com.doommeeting.server.enums.RoomStatus;
import com.doommeeting.server.repository.InviteTokenRepository;
import com.doommeeting.server.repository.RoomMemberRepository;
import com.doommeeting.server.repository.RoomRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.Map;
import java.util.UUID;

/**
 * 手机客户端入会/离会/心跳。
 * 全部成员就位(人数上限可设置, 默认 2) -> 推送 PC 端显示"该房间已运行" -> 开始会议计时。
 */
@Service
@RequiredArgsConstructor
public class MemberService {

    private final RoomRepository roomRepository;
    private final RoomMemberRepository memberRepository;
    private final InviteTokenRepository inviteTokenRepository;
    private final RoomService roomService;
    private final LiveKitTokenService liveKitTokenService;
    private final EventLogService eventLogService;
    private final NotificationService notificationService;
    private final AppProperties properties;

    @Transactional
    public synchronized JoinRoomResponse join(JoinRoomRequest request) {
        Room room = roomService.getRoomByCode(request.roomCode());
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭");
        }
        InviteToken invite = inviteTokenRepository.findByToken(request.inviteToken())
                .orElseThrow(() -> new BusinessException(403, "入会凭证无效"));
        if (!invite.getRoom().getId().equals(room.getId())) {
            throw new BusinessException(403, "入会凭证与房间不匹配");
        }
        if (invite.getRevoked()) {
            throw new BusinessException(403, "入会凭证已失效");
        }
        if (invite.getExpireAt().isBefore(LocalDateTime.now())) {
            throw new BusinessException(403, "入会凭证已过期");
        }
        // 房间人数硬限制: 手机客户端 ≤ 成员数上限 (PC 投屏端为后台隐藏角色, 不计入)
        long onlineCount = memberRepository.countByRoomAndOnlineTrue(room);
        if (onlineCount >= maxMembers(room)) {
            throw new BusinessException(403, "房间人数已满");
        }

        // 离会重进优先复用离线成员记录, 不重复消耗邀请凭证使用次数
        RoomMember member = memberRepository.findByRoomAndOnlineFalse(room).stream()
                .filter(m -> m.getNickname().equals(request.nickname()))
                .filter(m -> m.getDeviceInfo() == null || request.deviceInfo() == null
                        || m.getDeviceInfo().equals(request.deviceInfo()))
                .findFirst()
                .orElse(null);
        if (member == null) {
            if (invite.getUsedCount() >= invite.getMaxUses()) {
                throw new BusinessException(403, "入会凭证使用次数已达上限");
            }
            invite.setUsedCount(invite.getUsedCount() + 1);
            inviteTokenRepository.save(invite);
            member = new RoomMember();
            member.setRoom(room);
            member.setIdentity("client-" + UUID.randomUUID().toString().substring(0, 12));
            member.setNickname(request.nickname());
            member.setDeviceInfo(request.deviceInfo());
        } else {
            member.setOnline(true);
            member.setLeftAt(null);
            member.setDeviceInfo(request.deviceInfo());
        }
        member.setLastHeartbeatAt(LocalDateTime.now());
        memberRepository.save(member);

        eventLogService.log(room, RoomEventType.MEMBER_JOINED, request.nickname() + " 入会");
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "MEMBER_JOINED", Map.of(
                "identity", member.getIdentity(),
                "nickname", member.getNickname(),
                "onlineCount", onlineCount + 1));

        startOrRecoverIfFull(room, onlineCount + 1);

        ContentItem content = room.getCurrentContent();
        return new JoinRoomResponse(
                member.getId(),
                member.getIdentity(),
                room.getRoomCode(),
                room.getName(),
                room.getStatus().name(),
                room.getVideoCallEnabled(),
                room.getCameraEnabled(),
                room.getScreenshotAllowed(),
                room.getRecordingForbidden(),
                room.getDurationMinutes(),
                room.getMeetingStartAt(),
                room.getMeetingEndAt(),
                room.getPlaybackState().name(),
                room.getPlaybackPositionSeconds(),
                content == null ? null : content.getId(),
                content == null ? null : content.getName(),
                liveKitTokenService.createClientToken(
                        room.getRoomCode(), member.getIdentity(), member.getNickname()),
                liveKitTokenService.getWsUrl());
    }

    @Transactional
    public void leave(String roomCode, String identity) {
        Room room = roomService.getRoomByCode(roomCode);
        RoomMember member = memberRepository.findByRoomAndIdentity(room, identity)
                .orElseThrow(() -> new BusinessException(404, "成员不存在"));
        if (!member.getOnline()) {
            return;
        }
        member.setOnline(false);
        member.setLeftAt(LocalDateTime.now());
        memberRepository.save(member);

        eventLogService.log(room, RoomEventType.MEMBER_LEFT, member.getNickname() + " 离会");
        long onlineCount = memberRepository.countByRoomAndOnlineTrue(room);
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "MEMBER_LEFT", Map.of(
                "identity", member.getIdentity(),
                "nickname", member.getNickname(),
                "onlineCount", onlineCount));

        // 进入缺人状态, 开始计时(超过阈值后台亮红灯)
        if (room.getStatus() != RoomStatus.CLOSED
                && onlineCount < maxMembers(room)
                && room.getUnderstaffedSince() == null) {
            room.setUnderstaffedSince(LocalDateTime.now());
            roomRepository.save(room);
        }
    }

    @Transactional
    public void heartbeat(String roomCode, String identity) {
        Room room = roomService.getRoomByCode(roomCode);
        RoomMember member = memberRepository.findByRoomAndIdentity(room, identity)
                .orElseThrow(() -> new BusinessException(404, "成员不存在, 会话已失效"));
        member.setLastHeartbeatAt(LocalDateTime.now());
        // 心跳超时被判定离线的成员恢复心跳后自动重新上线
        if (!member.getOnline()
                && room.getStatus() != RoomStatus.CLOSED
                && memberRepository.countByRoomAndOnlineTrue(room) < maxMembers(room)) {
            member.setOnline(true);
            member.setLeftAt(null);
            memberRepository.save(member);
            long onlineCount = memberRepository.countByRoomAndOnlineTrue(room);
            eventLogService.log(room, RoomEventType.MEMBER_JOINED,
                    member.getNickname() + " 心跳恢复, 重新上线");
            notificationService.pushToRoomAndAdmin(room.getRoomCode(), "MEMBER_JOINED", Map.of(
                    "identity", member.getIdentity(),
                    "nickname", member.getNickname(),
                    "onlineCount", onlineCount));
            startOrRecoverIfFull(room, onlineCount);
        } else {
            memberRepository.save(member);
        }
    }

    /** 心跳超时的在线成员判定离线(进入缺人计时, 超阈值后台亮红灯) */
    @Transactional
    public void markStaleMembersOffline(LocalDateTime now) {
        LocalDateTime threshold = now.minusSeconds(properties.getRoom().getHeartbeatTimeoutSeconds());
        for (RoomMember member : memberRepository.findByOnlineTrueAndLastHeartbeatAtBefore(threshold)) {
            Room room = member.getRoom();
            if (room.getStatus() == RoomStatus.CLOSED) {
                continue;
            }
            member.setOnline(false);
            member.setLeftAt(now);
            memberRepository.save(member);

            eventLogService.log(room, RoomEventType.MEMBER_LEFT,
                    member.getNickname() + " 心跳超时, 判定离线");
            long onlineCount = memberRepository.countByRoomAndOnlineTrue(room);
            notificationService.pushToRoomAndAdmin(room.getRoomCode(), "MEMBER_LEFT", Map.of(
                    "identity", member.getIdentity(),
                    "nickname", member.getNickname(),
                    "onlineCount", onlineCount,
                    "reason", "HEARTBEAT_TIMEOUT"));

            if (onlineCount < maxMembers(room)
                    && room.getUnderstaffedSince() == null) {
                room.setUnderstaffedSince(now);
                roomRepository.save(room);
            }
        }
    }

    /** 手机端检测到录屏 -> 遮挡画面并上报 */
    @Transactional
    public void reportRecording(String roomCode, RecordingReportRequest request) {
        Room room = roomService.getRoomByCode(roomCode);
        RoomMember member = requireOnlineMember(room, request.identity());
        eventLogService.log(room, RoomEventType.RECORDING_DETECTED,
                member.getNickname() + " 检测到录屏行为: "
                        + (request.detail() == null ? "" : request.detail()));
        notificationService.pushToAdmin("RECORDING_DETECTED", room.getRoomCode(), Map.of(
                "identity", member.getIdentity(),
                "nickname", member.getNickname(),
                "detail", request.detail() == null ? "" : request.detail()));
    }

    /** 全部成员就位 -> 房间运行开始会议计时; 运行中重新满员 -> 解除缺人预警 */
    private void startOrRecoverIfFull(Room room, long onlineCount) {
        if (onlineCount < maxMembers(room)) {
            return;
        }
        if (room.getStatus() == RoomStatus.WAITING) {
            room.setStatus(RoomStatus.RUNNING);
            room.setMeetingStartAt(LocalDateTime.now());
            room.setMeetingEndAt(LocalDateTime.now().plusMinutes(room.getDurationMinutes()));
            room.setUnderstaffedAlert(false);
            room.setUnderstaffedSince(null);
            roomRepository.save(room);
            eventLogService.log(room, RoomEventType.ROOM_RUNNING,
                    maxMembers(room) + " 个手机客户端已就位, 会议开始计时");
            notificationService.pushToRoomAndAdmin(room.getRoomCode(), "ROOM_RUNNING", Map.of(
                    "meetingStartAt", String.valueOf(room.getMeetingStartAt()),
                    "meetingEndAt", String.valueOf(room.getMeetingEndAt()),
                    "durationMinutes", room.getDurationMinutes()));
        } else {
            clearUnderstaffed(room);
        }
    }

    /** 校验身份为房间在线成员 */
    public RoomMember requireOnlineMember(Room room, String identity) {
        RoomMember member = memberRepository.findByRoomAndIdentity(room, identity)
                .orElseThrow(() -> new BusinessException(403, "非房间成员, 禁止操作"));
        if (!Boolean.TRUE.equals(member.getOnline())) {
            throw new BusinessException(403, "成员已离会, 禁止操作");
        }
        return member;
    }

    private int maxMembers(Room room) {
        return room.getMaxMembers() == null
                ? properties.getRoom().getMaxClients() : room.getMaxMembers();
    }

    public long countOnline(Room room) {
        return memberRepository.countByRoomAndOnlineTrue(room);
    }

    public int maxMembersOf(Room room) {
        return maxMembers(room);
    }

    private void clearUnderstaffed(Room room) {
        if (Boolean.TRUE.equals(room.getUnderstaffedAlert()) || room.getUnderstaffedSince() != null) {
            room.setUnderstaffedAlert(false);
            room.setUnderstaffedSince(null);
            roomRepository.save(room);
            eventLogService.log(room, RoomEventType.UNDERSTAFFED_RECOVERED, "人员已满, 解除缺人预警");
            notificationService.pushToAdmin("UNDERSTAFFED_RECOVERED", room.getRoomCode(), Map.of());
        }
    }
}
