package com.doommeeting.server.dto;

import jakarta.validation.constraints.NotBlank;

import java.time.LocalDateTime;

public class ContentDtos {

    public record ContentRequest(
            @NotBlank(message = "内容名称不能为空") String name,
            String description,
            String type,
            String localPath,
            Integer durationSeconds,
            Boolean enabled) {
    }

    public record ContentResponse(
            Long id,
            String name,
            String description,
            String type,
            String localPath,
            Integer durationSeconds,
            Boolean enabled,
            String createdBy,
            LocalDateTime createdAt) {
    }
}
