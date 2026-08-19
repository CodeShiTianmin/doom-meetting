package com.doommeeting.server.config;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/**
 * 启动时检查默认密钥/默认管理员密码:
 * 默认仅告警; app.security.reject-default-secrets=true(生产)时拒绝启动。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class DefaultSecretsChecker {

    private static final String DEFAULT_JWT_SECRET =
            "ZG9vbS1tZWV0aW5nLXNlcnZlci1qd3Qtc2VjcmV0LWtleS0yMDI2LXZlcnktbG9uZw==";
    private static final String DEFAULT_LIVEKIT_KEY = "devkey";
    private static final String DEFAULT_LIVEKIT_SECRET = "devsecret-devsecret-devsecret-32";
    private static final String DEFAULT_ADMIN_PASSWORD = "admin123";

    private final AppProperties properties;

    @Value("${default-admin.password:}")
    private String adminPassword;

    @EventListener(ApplicationReadyEvent.class)
    public void checkDefaults() {
        List<String> defaults = new ArrayList<>();
        if (DEFAULT_JWT_SECRET.equals(properties.getJwt().getSecret())) {
            defaults.add("APP_JWT_SECRET");
        }
        if (DEFAULT_LIVEKIT_KEY.equals(properties.getLivekit().getApiKey())
                || DEFAULT_LIVEKIT_SECRET.equals(properties.getLivekit().getApiSecret())) {
            defaults.add("LIVEKIT_API_KEY/LIVEKIT_API_SECRET");
        }
        if (DEFAULT_ADMIN_PASSWORD.equals(adminPassword)) {
            defaults.add("DEFAULT_ADMIN_PASSWORD");
        }
        if (defaults.isEmpty()) {
            return;
        }
        String message = "检测到默认密钥/密码未覆盖, 生产环境必须通过环境变量修改: " + defaults;
        if (properties.getSecurity().isRejectDefaultSecrets()) {
            throw new IllegalStateException(message);
        }
        log.warn("{} (置 APP_REJECT_DEFAULT_SECRETS=true 可在启动时强制拒绝)", message);
    }
}
