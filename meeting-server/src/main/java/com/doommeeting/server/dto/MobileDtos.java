package com.doommeeting.server.dto;

import jakarta.validation.constraints.NotBlank;

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
            String memberToken,
            Integer seatNo,
            Boolean pendingApproval,
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
            String castType,
            String castLabel,
            Boolean muted,
            Boolean cameraDisabled,
            String livekitToken,
            String livekitWsUrl) {
    }

    public record LeaveRequest(
            @NotBlank(message = "身份标识不能为空") String identity,
            @NotBlank(message = "成员凭证不能为空") String memberToken) {
    }

    public record HeartbeatRequest(
            @NotBlank(message = "身份标识不能为空") String identity,
            @NotBlank(message = "成员凭证不能为空") String memberToken) {
    }

    public record LikeRequest(
            @NotBlank(message = "身份标识不能为空") String identity,
            @NotBlank(message = "成员凭证不能为空") String memberToken) {
    }

    /** 手机端播放控制(统一推流的播放/暂停/进度) */
    public record CastControlRequest(
            @NotBlank(message = "身份标识不能为空") String identity,
            @NotBlank(message = "成员凭证不能为空") String memberToken,
            @NotBlank(message = "控制动作不能为空") String action,
            Long positionMs) {
    }

    public record RecordingReportRequest(
            @NotBlank(message = "身份标识不能为空") String identity,
            @NotBlank(message = "成员凭证不能为空") String memberToken,
            String detail) {
    }
}
