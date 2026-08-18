package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.config.AppProperties;
import com.doommeeting.server.dto.RoomDtos.*;
import com.doommeeting.server.entity.ContentItem;
import com.doommeeting.server.entity.InviteToken;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomMember;
import com.doommeeting.server.enums.CloseReason;
import com.doommeeting.server.enums.PlaybackState;
import com.doommeeting.server.enums.RoomEventType;
import com.doommeeting.server.enums.RoomStatus;
import com.doommeeting.server.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Comparator;
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
    private final ContentItemRepository contentItemRepository;
    private final RoomEventLogRepository eventLogRepository;
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
        room.setCreatedBy(createdBy);
        // 创建即进入缺人等待状态, 超过阈值(默认3分钟)后台亮红灯预警
        room.setUnderstaffedSince(LocalDateTime.now());
        if (request.contentId() != null) {
            room.setCurrentContent(getContent(request.contentId()));
        }
        roomRepository.save(room);

        InviteToken invite = createInviteToken(room);
        eventLogService.log(room, RoomEventType.ROOM_CREATED,
                "房间创建, 会议时长 " + room.getDurationMinutes() + " 分钟");
        notificationService.pushToAdmin("ROOM_CREATED", room.getRoomCode(),
                Map.of("roomId", room.getId(), "name", room.getName()));
        return toResponse(room, invite);
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
            InviteToken activeInvite = latestInvite(room);
            if (activeInvite != null) {
                activeInvite.setMaxUses(Math.max(activeInvite.getUsedCount(), request.maxMembers()));
                inviteTokenRepository.save(activeInvite);
            }
            if (onlineCount >= request.maxMembers()) {
                if (room.getStatus() == RoomStatus.WAITING) {
                    startMeeting(room);
                }
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

    /** 成员数上限调整后已满员的等待房间立即进入运行状态 */
    private void startMeeting(Room room) {
        room.setStatus(RoomStatus.RUNNING);
        room.setMeetingStartAt(LocalDateTime.now());
        room.setMeetingEndAt(LocalDateTime.now().plusMinutes(room.getDurationMinutes()));
        eventLogService.log(room, RoomEventType.ROOM_RUNNING,
                "成员数上限调整后已满员, 会议开始计时");
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "ROOM_RUNNING", Map.of(
                "meetingStartAt", String.valueOf(room.getMeetingStartAt()),
                "meetingEndAt", String.valueOf(room.getMeetingEndAt()),
                "durationMinutes", room.getDurationMinutes()));
    }

    /** PC 端立即投放内容到指定房间(不同房间不同内容并行, 不串音不串频) */
    @Transactional
    public RoomResponse castContent(Long roomId, Long contentId, String operator) {
        Room room = getRoomById(roomId);
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭, 无法投放内容");
        }
        ContentItem content = getContent(contentId);
        room.setCurrentContent(content);
        room.setPlaybackState(PlaybackState.IDLE);
        room.setPlaybackPositionSeconds(0.0);
        room.setPlaybackUpdatedAt(LocalDateTime.now());
        roomRepository.save(room);
        eventLogService.log(room, RoomEventType.CONTENT_CAST,
                operator + " 投放内容: " + content.getName());
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "CONTENT_CAST", Map.of(
                "contentId", content.getId(),
                "contentName", content.getName(),
                "operator", operator));
        return toResponse(room, latestInvite(room));
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
        room.setPlaybackState(PlaybackState.IDLE);
        roomRepository.save(room);

        for (RoomMember member : memberRepository.findByRoomAndOnlineTrue(room)) {
            member.setOnline(false);
            member.setLeftAt(LocalDateTime.now());
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
        InviteToken invite = createInviteToken(room);
        return toResponse(room, invite);
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

    public Room getRoomById(Long id) {
        return roomRepository.findById(id)
                .orElseThrow(() -> new BusinessException(404, "房间不存在"));
    }

    public Room getRoomByCode(String roomCode) {
        return roomRepository.findByRoomCode(roomCode)
                .orElseThrow(() -> new BusinessException(404, "房间不存在"));
    }

    public InviteToken createInviteToken(Room room) {
        InviteToken invite = new InviteToken();
        invite.setRoom(room);
        invite.setToken(UUID.randomUUID().toString().replace("-", ""));
        invite.setExpireAt(LocalDateTime.now().plusMinutes(properties.getInvite().getExpireMinutes()));
        invite.setMaxUses(room.getMaxMembers() == null
                ? properties.getRoom().getMaxClients() : room.getMaxMembers());
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
        ContentItem content = room.getCurrentContent();
        String inviteUrl = buildInviteUrl(room, invite);
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
                content == null ? null : content.getId(),
                content == null ? null : content.getName(),
                room.getPlaybackState().name(),
                room.getPlaybackPositionSeconds(),
                room.getLikeCount(),
                room.getUnderstaffedAlert(),
                room.getUnderstaffedSince(),
                onlineCount,
                members,
                inviteUrl,
                inviteUrl,
                invite == null ? null : invite.getExpireAt(),
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
                member.getJoinedAt(),
                member.getLeftAt());
    }

    private ContentItem getContent(Long contentId) {
        return contentItemRepository.findById(contentId)
                .orElseThrow(() -> new BusinessException(404, "投放内容不存在"));
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
