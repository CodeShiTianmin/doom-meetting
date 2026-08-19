package com.doommeeting.server.service;

import com.doommeeting.server.config.AppProperties;
import org.springframework.stereotype.Service;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.InvalidKeyException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Base64;

/**
 * 文件访问短时效签名 token: 防止 /api/files/{id} 被枚举下载。
 * token = base64url(HMAC-SHA256(contentId + "." + expiresEpochSeconds))
 */
@Service
public class FileAccessTokenService {

    private static final String ALGORITHM = "HmacSHA256";

    private final byte[] secret;
    private final long ttlSeconds;

    public FileAccessTokenService(AppProperties properties) {
        this.secret = properties.getJwt().getSecret().getBytes(StandardCharsets.UTF_8);
        this.ttlSeconds = properties.getFileToken().getTtlMinutes() * 60L;
    }

    /** 生成带过期时间的访问 token, 形如 {expiresEpochSeconds}.{signature} */
    public String issueToken(Long contentId) {
        long expires = System.currentTimeMillis() / 1000 + ttlSeconds;
        return expires + "." + sign(contentId, expires);
    }

    public boolean validate(Long contentId, String token) {
        if (token == null || token.isBlank()) {
            return false;
        }
        int dot = token.indexOf('.');
        if (dot <= 0 || dot == token.length() - 1) {
            return false;
        }
        long expires;
        try {
            expires = Long.parseLong(token.substring(0, dot));
        } catch (NumberFormatException e) {
            return false;
        }
        if (expires < System.currentTimeMillis() / 1000) {
            return false;
        }
        String expected = sign(contentId, expires);
        return MessageDigest.isEqual(
                expected.getBytes(StandardCharsets.UTF_8),
                token.substring(dot + 1).getBytes(StandardCharsets.UTF_8));
    }

    private String sign(Long contentId, long expires) {
        try {
            Mac mac = Mac.getInstance(ALGORITHM);
            mac.init(new SecretKeySpec(secret, ALGORITHM));
            byte[] raw = mac.doFinal((contentId + "." + expires).getBytes(StandardCharsets.UTF_8));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(raw);
        } catch (NoSuchAlgorithmException | InvalidKeyException e) {
            throw new IllegalStateException("无法生成文件访问签名", e);
        }
    }
}
