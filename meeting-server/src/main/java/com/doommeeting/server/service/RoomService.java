package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.config.AppProperties;
import com.doommeeting.server.dto.RoomDtos.*;
import com.doommeeting.server.entity.InviteToken;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomMember;
import com.doommeeting.server.enums.CastType;
import com.doommeeting.server.enums.CloseReason;
import com.doommeeting.server.enums.RoomEventType;
import com.doommeeting.server.enums.RoomStatus;
import com.doommeeting.server.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * 房间业务: 创建/查询/设置/投放/关闭。
 * 房间模型: 单房间成员数可设置(默认 2 个手机客户端); 公司 PC 端以后台身份推流管理, 不出现在房间内。
 */
@Service
@RequiredArgsConstructor
public class RoomService {

    private static final String ROOM_CODE_CHARS = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
    private static final SecureRandom RANDOM = new SecureRandom();

    private final RoomRepository roomRepository;
    private final RoomMemberRepository memberRepository;
    private final InviteTokenRepository inviteTokenRepository;
    private final RoomEventLogRepository eventLogRepository;
    private final RoomLikeRepository likeRepository;
    private final ChatMessageRepository chatMessageRepository;
    private final EventLogService eventLogService;
    private final NotificationService notificationService;
    private final AppProperties properties;

    @Transactional
    public RoomResponse createRoom(CreateRoomRequest request, String createdBy) {
        Room room = new Room();
        room.setRoomCode(generateRoomCode());
        room.setName(request.name());
        room.setDurationMinutes(request.durationMinutes());
        room.setMaxMembers(request.maxMembers() == null
                ? properties.getRoom().getMaxClients() : request.maxMembers());
        room.setVideoCallEnabled(request.videoCallEnabled() == null || request.videoCallEnabled());
        room.setCameraEnabled(request.cameraEnabled() == null || request.cameraEnabled());
        room.setApprovalRequired(Boolean.TRUE.equals(request.approvalRequired()));
        room.setCreatedBy(createdBy);
        // 预约会议: 到达预约时间前不接受入会, 邀请二维码提前发放
        if (request.scheduledStartAt() != null && request.scheduledStartAt().isAfter(LocalDateTime.now())) {
            room.setScheduledStartAt(request.scheduledStartAt());
            room.setStatus(RoomStatus.SCHEDULED);
        } else {
            // 创建即进入缺人等待状态, 超过阈值(默认3分钟)后台亮红灯预警
            room.setUnderstaffedSince(LocalDateTime.now());
        }
        roomRepository.save(room);

        createSeatInvites(room);
        eventLogService.log(room, RoomEventType.ROOM_CREATED,
                "房间创建, 会议时长 " + room.getDurationMinutes() + " 分钟"
                        + (room.getScheduledStartAt() == null ? "" : ", 预约开始 " + room.getScheduledStartAt()));
        notificationService.pushToAdmin("ROOM_CREATED", room.getRoomCode(),
                Map.of("roomId", room.getId(), "name", room.getName()));
        return toResponse(room, latestInvite(room));
    }

    /** 到达预约时间的房间自动进入等待就位(调度器周期调用) */
    @Transactional
    public void activateScheduledRooms(LocalDateTime now) {
        for (Room room : roomRepository.findByStatusAndScheduledStartAtBefore(RoomStatus.SCHEDULED, now)) {
            room.setStatus(RoomStatus.WAITING);
            room.setUnderstaffedSince(now);
            roomRepository.save(room);
            eventLogService.log(room, RoomEventType.ROOM_ACTIVATED, "到达预约时间, 会议进入等待就位");
            notificationService.pushToRoomAndAdmin(room.getRoomCode(), "ROOM_ACTIVATED", Map.of(
                    "roomId", room.getId(), "name", room.getName()));
        }
    }

    @Transactional(readOnly = true)
    public List<RoomResponse> listRooms(String status) {
        List<Room> rooms;
        if (status == null || status.isBlank()) {
            rooms = roomRepository.findAllByOrderByCreatedAtDesc();
        } else {
            RoomStatus roomStatus;
            try {
                roomStatus = RoomStatus.valueOf(status.toUpperCase());
            } catch (IllegalArgumentException e) {
                throw new BusinessException("无效的房间状态: " + status);
            }
            rooms = roomRepository.findByStatusOrderByCreatedAtDesc(roomStatus);
        }
        return rooms.stream().map(room -> toResponse(room, latestInvite(room))).toList();
    }

    @Transactional(readOnly = true)
    public RoomResponse getRoom(Long id) {
        Room room = getRoomById(id);
        return toResponse(room, latestInvite(room));
    }

    @Transactional
    public RoomResponse updateSettings(Long id, RoomSettingsRequest request) {
        Room room = getRoomById(id);
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭, 无法修改设置");
        }
        StringBuilder detail = new StringBuilder("设置变更:");
        if (request.videoCallEnabled() != null) {
            room.setVideoCallEnabled(request.videoCallEnabled());
            detail.append(" 视频通话=").append(request.videoCallEnabled() ? "开" : "关");
        }
        if (request.cameraEnabled() != null) {
            room.setCameraEnabled(request.cameraEnabled());
            detail.append(" 摄像头=").append(request.cameraEnabled() ? "开" : "关");
        }
        if (request.durationMinutes() != null) {
            room.setDurationMinutes(request.durationMinutes());
            if (room.getStatus() == RoomStatus.RUNNING && room.getMeetingStartAt() != null) {
                room.setMeetingEndAt(room.getMeetingStartAt().plusMinutes(request.durationMinutes()));
                room.setReminder5Sent(false);
                room.setReminder1Sent(false);
            }
            detail.append(" 会议时长=").append(request.durationMinutes()).append("分钟");
        }
        if (request.maxMembers() != null) {
            long onlineCount = memberRepository.countByRoomAndOnlineTrue(room);
            if (request.maxMembers() < onlineCount) {
                throw new BusinessException("成员数上限不能小于当前在线人数(" + onlineCount + ")");
            }
            room.setMaxMembers(request.maxMembers());
            detail.append(" 成员数上限=").append(request.maxMembers()).append("人");
            // 新增座位补发独立二维码
            int existingSeats = (int) inviteTokenRepository.findByRoom(room).stream()
                    .filter(t -> !t.getRevoked()).count();
            for (int seat = existingSeats + 1; seat <= request.maxMembers(); seat++) {
                createInviteToken(room, seat);
            }
            if (onlineCount >= request.maxMembers()) {
                room.setUnderstaffedAlert(false);
                room.setUnderstaffedSince(null);
            } else if (room.getUnderstaffedSince() == null) {
                room.setUnderstaffedSince(LocalDateTime.now());
            }
        }
        roomRepository.save(room);
        eventLogService.log(room, RoomEventType.SETTINGS_CHANGED, detail.toString());
        // 功能开关实时下发到房间(手机端立即生效)
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "SETTINGS_CHANGED", Map.of(
                "videoCallEnabled", room.getVideoCallEnabled(),
                "cameraEnabled", room.getCameraEnabled(),
                "durationMinutes", room.getDurationMinutes(),
                "maxMembers", room.getMaxMembers(),
                "meetingEndAt", String.valueOf(room.getMeetingEndAt())));
        return toResponse(room, latestInvite(room));
    }

    /** 首次开始推流(播放视频/屏幕/摄像头) -> 会议开始计时 */
    private void startMeetingOnFirstCast(Room room) {
        if (room.getStatus() != RoomStatus.WAITING || room.getMeetingStartAt() != null) {
            return;
        }
        room.setStatus(RoomStatus.RUNNING);
        room.setMeetingStartAt(LocalDateTime.now());
        room.setMeetingEndAt(LocalDateTime.now().plusMinutes(room.getDurationMinutes()));
        eventLogService.log(room, RoomEventType.ROOM_RUNNING,
                "PC 端首次开始推流, 会议开始计时");
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "ROOM_RUNNING", Map.of(
                "meetingStartAt", String.valueOf(room.getMeetingStartAt()),
                "meetingEndAt", String.valueOf(room.getMeetingEndAt()),
                "durationMinutes", room.getDurationMinutes()));
    }

    /**
     * PC 端登记开始实时推流(屏幕/本地视频/摄像头, 均走 LiveKit 实时流)。
     * 不同房间独立推流并行, 不串音不串频。
     * 若房间已有投放且未确认替换(replace=false), 返回 409 提示先停止当前投放。
     */
    @Transactional
    public synchronized RoomResponse startCast(Long roomId, CastType type, String label,
                                               String operator, boolean replace) {
        Room room = getRoomById(roomId);
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭, 无法推流");
        }
        if (room.getCastType() != null && !replace) {
            throw new BusinessException(409,
                    "房间正在推流「" + castDescription(room) + "」, 请先停止当前推流后再开始新推流");
        }
        room.setCastType(type);
        room.setCastLabel(label);
        room.setCastBy(operator);
        // 会议计时以首次开始推流为准(不随成员就位触发)
        startMeetingOnFirstCast(room);
        roomRepository.save(room);
        eventLogService.log(room, RoomEventType.CAST_STARTED,
                operator + " 开始推流: " + castDescription(room));
        Map<String, Object> payload = new HashMap<>();
        payload.put("castType", type.name());
        payload.put("castLabel", label);
        payload.put("operator", operator);
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "CAST_STARTED", payload);
        return toResponse(room, latestInvite(room));
    }

    /** 停止当前推流: 清除房间推流状态 */
    @Transactional
    public synchronized RoomResponse stopCast(Long roomId, String operator) {
        Room room = getRoomById(roomId);
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭");
        }
        String previous = room.getCastType() == null ? null : castDescription(room);
        room.setCastType(null);
        room.setCastLabel(null);
        room.setCastBy(null);
        roomRepository.save(room);
        eventLogService.log(room, RoomEventType.CAST_STOPPED,
                operator + " 停止推流" + (previous == null ? "" : ": " + previous));
        Map<String, Object> payload = new HashMap<>();
        payload.put("operator", operator);
        payload.put("previousCastLabel", previous);
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "CAST_STOPPED", payload);
        return toResponse(room, latestInvite(room));
    }

    private String castDescription(Room room) {
        String typeName = switch (room.getCastType()) {
            case SCREEN -> "屏幕共享";
            case VIDEO -> "视频推流";
            case CAMERA -> "摄像头推流";
        };
        return room.getCastLabel() == null || room.getCastLabel().isBlank()
                ? typeName : typeName + "(" + room.getCastLabel() + ")";
    }

    /** 手动结束会议 */
    @Transactional
    public void closeRoom(Long id) {
        Room room = getRoomById(id);
        closeRoomInternal(room, CloseReason.MANUAL);
    }

    /** 关闭流程: 销毁房间 -> 全员离线 -> invite token 失效 -> 推送房间关闭事件 */
    @Transactional
    public void closeRoomInternal(Room room, CloseReason reason) {
        if (room.getStatus() == RoomStatus.CLOSED) {
            return;
        }
        room.setStatus(RoomStatus.CLOSED);
        room.setCloseReason(reason);
        room.setClosedAt(LocalDateTime.now());
        room.setUnderstaffedAlert(false);
        room.setUnderstaffedSince(null);
        room.setCastType(null);
        room.setCastLabel(null);
        room.setCastBy(null);
        roomRepository.save(room);

        LocalDateTime now = LocalDateTime.now();
        for (RoomMember member : memberRepository.findByRoomAndOnlineTrue(room)) {
            member.setOnline(false);
            member.setLeftAt(now);
            if (member.getLastOnlineAt() != null) {
                long seconds = Duration.between(member.getLastOnlineAt(), now).getSeconds();
                member.setOnlineSeconds(member.getOnlineSeconds() + Math.max(0, seconds));
                member.setLastOnlineAt(null);
            }
            memberRepository.save(member);
        }
        for (InviteToken token : inviteTokenRepository.findByRoom(room)) {
            token.setRevoked(true);
            inviteTokenRepository.save(token);
        }
        eventLogService.log(room, RoomEventType.ROOM_CLOSED,
                reason == CloseReason.MANUAL ? "PC 端手动结束会议" : "会议时长到期自动关闭");
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "ROOM_CLOSED",
                Map.of("reason", reason.name()));
    }

    /** 删除房间: 未关闭的房间先执行关闭流程, 再级联删除全部关联数据 */
    @Transactional
    public void deleteRoom(Long id) {
        Room room = getRoomById(id);
        if (room.getStatus() != RoomStatus.CLOSED) {
            closeRoomInternal(room, CloseReason.MANUAL);
        }
        String roomCode = room.getRoomCode();
        likeRepository.deleteByRoom(room);
        chatMessageRepository.deleteByRoom(room);
        eventLogRepository.deleteByRoom(room);
        memberRepository.deleteByRoom(room);
        inviteTokenRepository.deleteByRoom(room);
        roomRepository.delete(room);
        notificationService.pushToAdmin("ROOM_DELETED", roomCode, Map.of("roomId", id));
    }

    /** 重新生成入会二维码(旧凭证全部失效) */
    @Transactional
    public RoomResponse regenerateInvite(Long id) {
        Room room = getRoomById(id);
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭, 无法生成入会凭证");
        }
        for (InviteToken token : inviteTokenRepository.findByRoom(room)) {
            token.setRevoked(true);
            inviteTokenRepository.save(token);
        }
        createSeatInvites(room);
        return toResponse(room, latestInvite(room));
    }

    /** 会后出席统计: 出席时长/离会次数/点赞数 */
    @Transactional(readOnly = true)
    public List<AttendanceResponse> attendance(Long id) {
        Room room = getRoomById(id);
        LocalDateTime now = LocalDateTime.now();
        List<AttendanceResponse> result = new ArrayList<>();
        for (RoomMember member : memberRepository.findByRoomOrderByJoinedAtAsc(room)) {
            long onlineSeconds = member.getOnlineSeconds();
            if (Boolean.TRUE.equals(member.getOnline()) && member.getLastOnlineAt() != null) {
                onlineSeconds += Math.max(0, Duration.between(member.getLastOnlineAt(), now).getSeconds());
            }
            result.add(new AttendanceResponse(
                    member.getId(),
                    member.getIdentity(),
                    member.getNickname(),
                    member.getSeatNo(),
                    member.getOnline(),
                    member.getJoinedAt(),
                    member.getLeftAt(),
                    onlineSeconds,
                    member.getJoinCount(),
                    likeRepository.countByRoomAndMemberIdentity(room, member.getIdentity())));
        }
        return result;
    }

    @Transactional(readOnly = true)
    public List<MemberResponse> listMembers(Long id) {
        Room room = getRoomById(id);
        return memberRepository.findByRoomOrderByJoinedAtAsc(room).stream()
                .map(this::toMemberResponse).toList();
    }

    @Transactional(readOnly = true)
    public List<RoomEventResponse> listEvents(Long id) {
        Room room = getRoomById(id);
        return eventLogService.recentEvents(room).stream()
                .map(e -> new RoomEventResponse(e.getId(), e.getType().name(), e.getDetail(), e.getCreatedAt()))
                .toList();
    }

    /** 手机端房间实时状态(会议时间/剩余时长/推流状态/功能开关) */
    @Transactional(readOnly = true)
    public Map<String, Object> mobileState(String roomCode) {
        Room room = getRoomByCode(roomCode);
        Map<String, Object> state = new HashMap<>();
        state.put("roomCode", room.getRoomCode());
        state.put("name", room.getName());
        state.put("status", room.getStatus().name());
        state.put("videoCallEnabled", room.getVideoCallEnabled());
        state.put("cameraEnabled", room.getCameraEnabled());
        state.put("screenshotAllowed", room.getScreenshotAllowed());
        state.put("recordingForbidden", room.getRecordingForbidden());
        state.put("durationMinutes", room.getDurationMinutes());
        state.put("maxMembers", room.getMaxMembers());
        state.put("meetingStartAt", room.getMeetingStartAt());
        state.put("meetingEndAt", room.getMeetingEndAt());
        if (room.getStatus() == RoomStatus.RUNNING && room.getMeetingEndAt() != null) {
            state.put("remainingSeconds", Math.max(0,
                    Duration.between(LocalDateTime.now(), room.getMeetingEndAt()).getSeconds()));
        }
        state.put("likeCount", room.getLikeCount());
        state.put("castType", room.getCastType() == null ? null : room.getCastType().name());
        state.put("castLabel", room.getCastLabel());
        state.put("allMuted", room.getAllMuted());
        return state;
    }

    public Room getRoomById(Long id) {
        return roomRepository.findById(id)
                .orElseThrow(() -> new BusinessException(404, "房间不存在"));
    }

    public Room getRoomByCode(String roomCode) {
        return roomRepository.findByRoomCode(roomCode)
                .orElseThrow(() -> new BusinessException(404, "房间不存在"));
    }

    /** 每个座位生成一张独立二维码(限用1次) */
    public void createSeatInvites(Room room) {
        int seats = room.getMaxMembers() == null
                ? properties.getRoom().getMaxClients() : room.getMaxMembers();
        for (int seat = 1; seat <= seats; seat++) {
            createInviteToken(room, seat);
        }
    }

    public InviteToken createInviteToken(Room room, Integer seatNo) {
        InviteToken invite = new InviteToken();
        invite.setRoom(room);
        invite.setToken(UUID.randomUUID().toString().replace("-", ""));
        // 有效期与会议生命周期关联: 随房间关闭统一撤销, 不再固定分钟数过期
        invite.setExpireAt(null);
        invite.setSeatNo(seatNo);
        invite.setMaxUses(1);
        inviteTokenRepository.save(invite);
        return invite;
    }

    public InviteToken latestInvite(Room room) {
        return inviteTokenRepository.findByRoom(room).stream()
                .filter(t -> !t.getRevoked())
                .max(Comparator.comparing(InviteToken::getId))
                .orElse(null);
    }

    public String buildInviteUrl(Room room, InviteToken invite) {
        if (invite == null) {
            return null;
        }
        return properties.getInvite().getScheme()
                + "?room=" + room.getRoomCode()
                + "&token=" + invite.getToken();
    }

    public RoomResponse toResponse(Room room, InviteToken invite) {
        List<MemberResponse> members = memberRepository.findByRoomOrderByJoinedAtAsc(room).stream()
                .map(this::toMemberResponse).toList();
        int onlineCount = (int) members.stream().filter(MemberResponse::online).count();
        Long remainingSeconds = null;
        if (room.getStatus() == RoomStatus.RUNNING && room.getMeetingEndAt() != null) {
            remainingSeconds = Math.max(0,
                    Duration.between(LocalDateTime.now(), room.getMeetingEndAt()).getSeconds());
        }
        String inviteUrl = buildInviteUrl(room, invite);
        List<SeatInviteResponse> invites = inviteTokenRepository.findByRoom(room).stream()
                .filter(t -> !t.getRevoked())
                .sorted(Comparator.comparing(t -> t.getSeatNo() == null ? 0 : t.getSeatNo()))
                .map(t -> new SeatInviteResponse(
                        t.getSeatNo(),
                        t.getToken(),
                        buildInviteUrl(room, t),
                        t.getExpireAt(),
                        t.getUsedCount() >= t.getMaxUses(),
                        t.getRevoked()))
                .toList();
        return new RoomResponse(
                room.getId(),
                room.getRoomCode(),
                room.getName(),
                room.getStatus().name(),
                room.getVideoCallEnabled(),
                room.getCameraEnabled(),
                room.getScreenshotAllowed(),
                room.getRecordingForbidden(),
                room.getDurationMinutes(),
                room.getMaxMembers(),
                room.getMeetingStartAt(),
                room.getMeetingEndAt(),
                remainingSeconds,
                room.getCastType() == null ? null : room.getCastType().name(),
                room.getCastLabel(),
                room.getCastBy(),
                room.getLikeCount(),
                room.getUnderstaffedAlert(),
                room.getUnderstaffedSince(),
                onlineCount,
                members,
                inviteUrl,
                inviteUrl,
                invite == null ? null : invite.getExpireAt(),
                invites,
                room.getScheduledStartAt(),
                room.getApprovalRequired(),
                room.getAllMuted(),
                room.getCloseReason() == null ? null : room.getCloseReason().name(),
                room.getClosedAt(),
                room.getCreatedBy(),
                room.getCreatedAt());
    }

    private MemberResponse toMemberResponse(RoomMember member) {
        return new MemberResponse(
                member.getId(),
                member.getIdentity(),
                member.getNickname(),
                member.getDeviceInfo(),
                member.getOnline(),
                member.getSeatNo(),
                member.getMuted(),
                member.getCameraDisabled(),
                member.getKicked(),
                member.getApproved(),
                member.getJoinedAt(),
                member.getLeftAt());
    }

    private String generateRoomCode() {
        for (int attempt = 0; attempt < 10; attempt++) {
            StringBuilder sb = new StringBuilder(8);
            for (int i = 0; i < 8; i++) {
                sb.append(ROOM_CODE_CHARS.charAt(RANDOM.nextInt(ROOM_CODE_CHARS.length())));
            }
            String code = sb.toString();
            if (roomRepository.findByRoomCode(code).isEmpty()) {
                return code;
            }
        }
        throw new BusinessException("房号生成失败, 请重试");
    }
}
