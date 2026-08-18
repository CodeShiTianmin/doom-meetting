package com.doommeeting.server.dto;

import jakarta.validation.constraints.NotNull;

import java.time.LocalDateTime;

public class CastScheduleDtos {

    public record CastScheduleRequest(
            @NotNull(message = "房间不能为空") Long roomId,
            @NotNull(message = "内容不能为空") Long contentId,
            @NotNull(message = "投放时间不能为空") LocalDateTime castAt,
            String note) {
    }

    public record CastScheduleResponse(
            Long id,
            Long roomId,
            String roomCode,
            String roomName,
            Long contentId,
            String contentName,
            LocalDateTime castAt,
            String status,
            LocalDateTime executedAt,
            String note,
            String createdBy,
            LocalDateTime createdAt) {
    }
}
