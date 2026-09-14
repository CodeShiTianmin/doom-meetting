package com.doommeeting.server.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.LocalDateTime;

public class ChatDtos {

    public record MobileChatRequest(
            @NotBlank(message = "身份标识不能为空") String identity,
            @NotBlank(message = "成员凭证不能为空") String memberToken,
            @NotBlank(message = "消息内容不能为空") @Size(max = 200, message = "消息最长 200 字") String content) {
    }

    public record AdminChatRequest(
            @NotBlank(message = "消息内容不能为空") @Size(max = 200, message = "消息最长 200 字") String content) {
    }

    /** id 为服务端生成的消息唯一标识, 客户端用于实时事件与历史记录的合并去重 */
    public record ChatMessageResponse(
            String id,
            String sender,
            String identity,
            String content,
            Boolean fromAdmin,
            LocalDateTime sentAt) {
    }
}
