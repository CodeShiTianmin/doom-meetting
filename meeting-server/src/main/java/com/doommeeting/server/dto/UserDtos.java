package com.doommeeting.server.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.LocalDateTime;

public class UserDtos {

    public record UserCreateRequest(
            @NotBlank(message = "用户名不能为空") @Size(max = 64) String username,
            @NotBlank(message = "密码不能为空") @Size(min = 6, max = 64, message = "密码长度需为 6-64 位") String password,
            @Size(max = 64) String displayName,
            String role) {
    }

    public record UserUpdateRequest(
            @Size(max = 64) String displayName,
            String role,
            @Size(min = 6, max = 64, message = "密码长度需为 6-64 位") String password) {
    }

    public record UserResponse(
            Long id,
            String username,
            String displayName,
            String role,
            LocalDateTime createdAt) {
    }
}
