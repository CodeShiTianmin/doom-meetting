package com.doommeeting.server.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDateTime;

public class MobileDtos {

    public record JoinRoomRequest(
            @NotBlank(message = "房号不能为空") String roomCode,
            @NotBlank(message = "入会凭证不能为空") String inviteToken,
            @NotBlank(message = "昵称不能为空") String nickname,
            String deviceInfo) {
    }

    public record JoinRoomResponse(
            Long memberId,
            String identity,
            String roomCode,
            String roomName,
            String roomStatus,
            Boolean videoCallEnabled,
            Boolean cameraEnabled,
            Boolean screenshotAllowed,
            Boolean recordingForbidden,
            Integer durationMinutes,
            LocalDateTime meetingStartAt,
            LocalDateTime meetingEndAt,
            String playbackState,
            Double playbackPositionSeconds,
            Long contentId,
            String contentName,
            String livekitToken,
            String livekitWsUrl) {
    }

    public record LeaveRequest(@NotBlank(message = "身份标识不能为空") String identity) {
    }

    public record HeartbeatRequest(@NotBlank(message = "身份标识不能为空") String identity) {
    }

    public record LikeRequest(@NotBlank(message = "身份标识不能为空") String identity) {
    }

    public record PlaybackControlRequest(
            @NotBlank(message = "身份标识不能为空") String identity,
            @NotBlank(message = "指令不能为空") String action,
            @DecimalMin(value = "0", message = "播放进度不能为负") Double positionSeconds,
            @DecimalMin(value = "0", message = "调节值范围 0~100")
            @DecimalMax(value = "100", message = "调节值范围 0~100") Double value,
            @NotNull(message = "指令序号不能为空") Long seq) {
    }

    public record RecordingReportRequest(
            @NotBlank(message = "身份标识不能为空") String identity,
            String detail) {
    }
}
