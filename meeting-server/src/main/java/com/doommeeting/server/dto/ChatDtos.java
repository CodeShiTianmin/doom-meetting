package com.doommeeting.server.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.LocalDateTime;

public class ChatDtos {

    public record ChatSendRequest(
            @NotBlank(message = "身份标识不能为空") String identity,
            @NotBlank(message = "成员凭证不能为空") String memberToken,
            @NotBlank(message = "消息内容不能为空")
            @Size(max = 500, message = "消息内容不能超过500字") String content) {
    }

    public record AdminChatSendRequest(
            @NotBlank(message = "消息内容不能为空")
            @Size(max = 500, message = "消息内容不能超过500字") String content) {
    }

    public record ChatMessageResponse(
            Long id,
            String identity,
            String nickname,
            Boolean fromAdmin,
            String content,
            LocalDateTime sentAt) {
    }
}
