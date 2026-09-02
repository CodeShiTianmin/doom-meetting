package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.config.AppProperties;
import com.doommeeting.server.dto.MobileDtos.*;
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
import java.util.HashMap;
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
        if (room.getStatus() == RoomStatus.SCHEDULED) {
            throw new BusinessException(403, "会议尚未开始, 预约时间: " + room.getScheduledStartAt());
        }
        InviteToken invite = inviteTokenRepository.findByToken(request.inviteToken())
                .orElseThrow(() -> new BusinessException(403, "入会凭证无效"));
        if (!invite.getRoom().getId().equals(room.getId())) {
            throw new BusinessException(403, "入会凭证与房间不匹配");
        }
        if (invite.getRevoked()) {
            throw new BusinessException(403, "入会凭证已失效");
        }
        // 凭证有效期与会议生命周期关联: expireAt 为空时随房间关闭统一撤销
        if (invite.getExpireAt() != null && invite.getExpireAt().isBefore(LocalDateTime.now())) {
            throw new BusinessException(403, "入会凭证已过期");
        }

        // 离线复用按座位凭证绑定匹配(不可伪造), 而非昵称
        RoomMember member = memberRepository.findByRoomAndInviteTokenId(room, invite.getId())
                .orElse(null);
        if (member != null && Boolean.TRUE.equals(member.getKicked())) {
            throw new BusinessException(403, "已被主持人移出会议, 禁止再次入会");
        }
        if (member != null && Boolean.TRUE.equals(member.getOnline())) {
            throw new BusinessException(403, "该座位已在会中, 禁止顶替");
        }

        long onlineCount = memberRepository.countByRoomAndOnlineTrue(room);
        boolean newMember = member == null;
        if (member == null) {
            if (invite.getUsedCount() >= invite.getMaxUses()) {
                throw new BusinessException(403, "入会凭证使用次数已达上限");
            }
            invite.setUsedCount(invite.getUsedCount() + 1);
            inviteTokenRepository.save(invite);
            member = new RoomMember();
            member.setRoom(room);
            member.setIdentity("client-" + UUID.randomUUID().toString().substring(0, 12));
            member.setMemberToken(UUID.randomUUID().toString().replace("-", ""));
            member.setInviteTokenId(invite.getId());
            member.setSeatNo(invite.getSeatNo());
            member.setNickname(request.nickname());
            member.setDeviceInfo(request.deviceInfo());
            member.setApproved(!Boolean.TRUE.equals(room.getApprovalRequired()));
            member.setOnline(false);
        } else {
            member.setDeviceInfo(request.deviceInfo());
        }
        member.setLastHeartbeatAt(LocalDateTime.now());

        // 等候室: 未批准前不上线、不发 LiveKit token; 客户端重试 join 轮询审批结果
        if (Boolean.TRUE.equals(room.getApprovalRequired()) && !Boolean.TRUE.equals(member.getApproved())) {
            memberRepository.save(member);
            // 客户端轮询审批结果会重复调用 join, 只在首次申请时记录/通知, 避免刷屏
            if (newMember) {
                eventLogService.log(room, RoomEventType.JOIN_REQUEST, request.nickname() + " 申请入会, 等待审批");
                notificationService.pushToAdmin("JOIN_REQUEST", room.getRoomCode(), Map.of(
                        "identity", member.getIdentity(),
                        "nickname", member.getNickname(),
                        "seatNo", member.getSeatNo() == null ? 0 : member.getSeatNo()));
            }
            return pendingResponse(room, member);
        }

        // 房间人数硬限制: 手机客户端 ≤ 成员数上限 (PC 投屏端为后台隐藏角色, 不计入)
        if (onlineCount >= maxMembers(room)) {
            throw new BusinessException(403, "房间人数已满");
        }
        member.setOnline(true);
        member.setLeftAt(null);
        member.setLastOnlineAt(LocalDateTime.now());
        member.setJoinCount(member.getJoinCount() + 1);
        memberRepository.save(member);

        eventLogService.log(room, RoomEventType.MEMBER_JOINED, request.nickname() + " 入会");
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "MEMBER_JOINED", Map.of(
                "identity", member.getIdentity(),
                "nickname", member.getNickname(),
                "onlineCount", onlineCount + 1));

        startOrRecoverIfFull(room, onlineCount + 1);

        return new JoinRoomResponse(
                member.getId(),
                member.getIdentity(),
                member.getMemberToken(),
                member.getSeatNo(),
                false,
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
                room.getCastType() == null ? null : room.getCastType().name(),
                room.getCastLabel(),
                Boolean.TRUE.equals(member.getMuted()) || Boolean.TRUE.equals(room.getAllMuted()),
                member.getCameraDisabled(),
                liveKitTokenService.createClientToken(
                        room.getRoomCode(), member.getIdentity(), member.getNickname()),
                liveKitTokenService.getWsUrl());
    }

    /** 等候室待审批响应: 不下发 LiveKit 凭证 */
    private JoinRoomResponse pendingResponse(Room room, RoomMember member) {
        return new JoinRoomResponse(
                member.getId(),
                member.getIdentity(),
                member.getMemberToken(),
                member.getSeatNo(),
                true,
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
                null,
                null,
                null,
                null,
                null,
                null);
    }

    /** 离线结算累计出席时长 */
    public void settleOnlineSeconds(RoomMember member, LocalDateTime now) {
        if (member.getLastOnlineAt() != null) {
            long seconds = java.time.Duration.between(member.getLastOnlineAt(), now).getSeconds();
            member.setOnlineSeconds(member.getOnlineSeconds() + Math.max(0, seconds));
            member.setLastOnlineAt(null);
        }
    }

    @Transactional
    public void leave(String roomCode, String identity, String memberToken) {
        Room room = roomService.getRoomByCode(roomCode);
        RoomMember member = requireMember(room, identity, memberToken);
        if (!member.getOnline()) {
            return;
        }
        member.setOnline(false);
        member.setLeftAt(LocalDateTime.now());
        settleOnlineSeconds(member, LocalDateTime.now());
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
    public void heartbeat(String roomCode, String identity, String memberToken) {
        Room room = roomService.getRoomByCode(roomCode);
        RoomMember member = requireMember(room, identity, memberToken);
        member.setLastHeartbeatAt(LocalDateTime.now());
        // 心跳超时被判定离线的成员恢复心跳后自动重新上线
        if (!member.getOnline()
                && Boolean.TRUE.equals(member.getApproved())
                && room.getStatus() != RoomStatus.CLOSED
                && memberRepository.countByRoomAndOnlineTrue(room) < maxMembers(room)) {
            member.setOnline(true);
            member.setLeftAt(null);
            member.setLastOnlineAt(LocalDateTime.now());
            member.setJoinCount(member.getJoinCount() + 1);
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
            settleOnlineSeconds(member, now);
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

    /** 手机端播放控制: 转发给 PC 端本房间播放器执行(播放/暂停/进度) */
    @Transactional(readOnly = true)
    public void castControl(String roomCode, CastControlRequest request) {
        Room room = roomService.getRoomByCode(roomCode);
        RoomMember member = requireOnlineMember(room, request.identity(), request.memberToken());
        if (room.getCastType() == null) {
            throw new BusinessException("当前没有推流内容");
        }
        if (!"playOrPause".equals(request.action()) && !"seek".equals(request.action())) {
            throw new BusinessException("不支持的控制动作: " + request.action());
        }
        if ("seek".equals(request.action()) && request.positionMs() == null) {
            throw new BusinessException("进度调节需要提供目标位置");
        }
        Map<String, Object> payload = new HashMap<>();
        payload.put("action", request.action());
        payload.put("operator", member.getNickname());
        if (request.positionMs() != null) {
            payload.put("positionMs", request.positionMs());
        }
        notificationService.pushToAdmin("CAST_CONTROL", room.getRoomCode(), payload);
    }

    /** 手机端检测到录屏 -> 遮挡画面并上报 */
    @Transactional
    public void reportRecording(String roomCode, RecordingReportRequest request) {
        Room room = roomService.getRoomByCode(roomCode);
        RoomMember member = requireOnlineMember(room, request.identity(), request.memberToken());
        eventLogService.log(room, RoomEventType.RECORDING_DETECTED,
                member.getNickname() + " 检测到录屏行为: "
                        + (request.detail() == null ? "" : request.detail()));
        notificationService.pushToAdmin("RECORDING_DETECTED", room.getRoomCode(), Map.of(
                "identity", member.getIdentity(),
                "nickname", member.getNickname(),
                "detail", request.detail() == null ? "" : request.detail()));
    }

    /**
     * 全部成员就位 -> 房间进入运行状态并开始会议倒计时; 运行中重新满员 -> 解除缺人预警;
     * 首位成员就位后仍缺人 -> 开始缺人计时(超时亮红灯), 空闲房间不计入缺人预警
     */
    private void startOrRecoverIfFull(Room room, long onlineCount) {
        if (onlineCount < maxMembers(room)) {
            if (onlineCount > 0 && room.getUnderstaffedSince() == null) {
                room.setUnderstaffedSince(LocalDateTime.now());
                roomRepository.save(room);
            }
            return;
        }
        if (room.getStatus() == RoomStatus.WAITING) {
            roomService.startMeeting(room, maxMembers(room) + " 个手机客户端已就位");
        } else {
            clearUnderstaffed(room);
        }
    }

    /** 校验会话级成员凭证(identity + memberToken) */
    public RoomMember requireMember(Room room, String identity, String memberToken) {
        RoomMember member = memberRepository.findByRoomAndIdentity(room, identity)
                .orElseThrow(() -> new BusinessException(403, "非房间成员, 禁止操作"));
        if (memberToken == null || !memberToken.equals(member.getMemberToken())) {
            throw new BusinessException(403, "成员凭证无效, 禁止操作");
        }
        if (Boolean.TRUE.equals(member.getKicked())) {
            throw new BusinessException(403, "已被主持人移出会议, 禁止操作");
        }
        return member;
    }

    /** 校验身份为房间在线成员(含会话凭证校验) */
    public RoomMember requireOnlineMember(Room room, String identity, String memberToken) {
        RoomMember member = requireMember(room, identity, memberToken);
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
