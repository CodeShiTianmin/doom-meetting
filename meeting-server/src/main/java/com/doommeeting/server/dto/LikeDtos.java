package com.doommeeting.server.dto;

import java.time.LocalDateTime;

public class LikeDtos {

    public record LikeRecordResponse(
            Long id,
            Long roomId,
            String roomCode,
            String roomName,
            String memberIdentity,
            String nickname,
            LocalDateTime likedAt) {
    }
}
