package com.doommeeting.server.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

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
            Long contentId) {
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
            Long contentId,
            String contentName,
            String contentType,
            String contentFileUrl,
            String contentMimeType,
            Integer contentDurationSeconds,
            String playbackState,
            Double playbackPositionSeconds,
            Long likeCount,
            Boolean understaffedAlert,
            LocalDateTime understaffedSince,
            Integer onlineMemberCount,
            List<MemberResponse> members,
            String inviteUrl,
            String qrContent,
            LocalDateTime inviteExpireAt,
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
            LocalDateTime joinedAt,
            LocalDateTime leftAt) {
    }

    public record CastRequest(
            @NotNull(message = "内容不能为空") Long contentId,
            Boolean replace) {
    }

    public record AdminPlaybackRequest(
            @NotBlank(message = "操作类型不能为空") String action,
            Double positionSeconds,
            Double value) {
    }

    public record RoomEventResponse(Long id, String type, String detail, LocalDateTime createdAt) {
    }
}
