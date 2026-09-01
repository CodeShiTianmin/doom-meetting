package com.doommeeting.server.dto;

import com.doommeeting.server.enums.CastType;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.LocalDateTime;
import java.util.List;

public class RoomDtos {

    public record CreateRoomRequest(
            @NotBlank(message = "房间名称不能为空") String name,
            @NotNull(message = "会议时长不能为空")
            @Min(value = 1, message = "会议时长至少1分钟")
            @Max(value = 720, message = "会议时长最多720分钟") Integer durationMinutes,
            @Min(value = 1, message = "成员数至少1人")
            @Max(value = 50, message = "成员数最多50人") Integer maxMembers,
            Boolean videoCallEnabled,
            Boolean cameraEnabled,
            LocalDateTime scheduledStartAt,
            Boolean approvalRequired) {
    }

    public record RoomSettingsRequest(
            Boolean videoCallEnabled,
            Boolean cameraEnabled,
            @Min(value = 1, message = "会议时长至少1分钟")
            @Max(value = 720, message = "会议时长最多720分钟") Integer durationMinutes,
            @Min(value = 1, message = "成员数至少1人")
            @Max(value = 50, message = "成员数最多50人") Integer maxMembers) {
    }

    public record RoomResponse(
            Long id,
            String roomCode,
            String name,
            String status,
            Boolean videoCallEnabled,
            Boolean cameraEnabled,
            Boolean screenshotAllowed,
            Boolean recordingForbidden,
            Integer durationMinutes,
            Integer maxMembers,
            LocalDateTime meetingStartAt,
            LocalDateTime meetingEndAt,
            Long remainingSeconds,
            String castType,
            String castLabel,
            String castBy,
            Long likeCount,
            Boolean understaffedAlert,
            LocalDateTime understaffedSince,
            Integer onlineMemberCount,
            List<MemberResponse> members,
            String inviteUrl,
            String qrContent,
            LocalDateTime inviteExpireAt,
            List<SeatInviteResponse> invites,
            LocalDateTime scheduledStartAt,
            Boolean approvalRequired,
            Boolean allMuted,
            String closeReason,
            LocalDateTime closedAt,
            String createdBy,
            LocalDateTime createdAt) {
    }

    public record MemberResponse(
            Long id,
            String identity,
            String nickname,
            String deviceInfo,
            Boolean online,
            Integer seatNo,
            Boolean muted,
            Boolean cameraDisabled,
            Boolean kicked,
            Boolean approved,
            LocalDateTime joinedAt,
            LocalDateTime leftAt) {
    }

    /** 每座位独立入会二维码 */
    public record SeatInviteResponse(
            Integer seatNo,
            String token,
            String inviteUrl,
            LocalDateTime expireAt,
            Boolean used,
            Boolean revoked) {
    }

    /** 会后出席统计 */
    public record AttendanceResponse(
            Long memberId,
            String identity,
            String nickname,
            Integer seatNo,
            Boolean online,
            LocalDateTime firstJoinedAt,
            LocalDateTime leftAt,
            Long onlineSeconds,
            Integer joinCount,
            Long likeCount) {
    }

    /** PC 端开始推流登记(屏幕/本地视频/摄像头) */
    public record CastStartRequest(
            @NotNull(message = "推流类型不能为空") CastType type,
            @Size(max = 128, message = "推流内容说明最长 128 字") String label,
            Boolean replace) {
    }

    public record RoomEventResponse(Long id, String type, String detail, LocalDateTime createdAt) {
    }

    /** PC 端统一播放状态广播(播放/暂停/进度) */
    public record PlaybackStateRequest(Boolean playing, Long positionMs, Long durationMs) {
    }
}
