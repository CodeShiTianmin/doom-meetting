package com.doommeeting.server.dto;

import java.time.LocalDateTime;

public class ContentDtos {

    public record ContentResponse(
            Long id,
            String name,
            String description,
            String type,
            Integer durationSeconds,
            String fileUrl,
            Long fileSize,
            String mimeType,
            Long roomId,
            Boolean enabled,
            String createdBy,
            LocalDateTime createdAt) {
    }
}
