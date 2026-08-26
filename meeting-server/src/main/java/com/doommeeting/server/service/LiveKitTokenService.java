package com.doommeeting.server.service;

import com.doommeeting.server.config.AppProperties;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;

/**
 * LiveKit 入会 Token(自部署 SFU, 关闭录制功能即零留存)。
 * Token 为 HS256 JWT: iss=apiKey, sub=identity, video=授权范围。
 */
@Service
public class LiveKitTokenService {

    private final AppProperties.Livekit livekit;
    private final SecretKey key;

    public LiveKitTokenService(AppProperties properties) {
        this.livekit = properties.getLivekit();
        this.key = Keys.hmacShaKeyFor(livekit.getApiSecret().getBytes(StandardCharsets.UTF_8));
    }

    /** 手机客户端: 可发布 + 可订阅 */
    public String createClientToken(String roomCode, String identity, String nickname) {
        Map<String, Object> grants = baseGrants(roomCode);
        grants.put("canPublish", true);
        grants.put("canSubscribe", true);
        return buildToken(identity, nickname, grants, false);
    }

    /**
     * PC 隐藏推流端: 只发不收, hidden=true 不出现在成员列表
     * (公司 PC 端以后台身份推流, 不作为房间成员)
     */
    public String createHiddenPublisherToken(String roomCode, String identity) {
        Map<String, Object> grants = baseGrants(roomCode);
        grants.put("canPublish", true);
        grants.put("canSubscribe", false);
        grants.put("hidden", true);
        return buildToken(identity, "PC投屏端", grants, true);
    }

    public String getWsUrl() {
        return livekit.getWsUrl();
    }

    private Map<String, Object> baseGrants(String roomCode) {
        Map<String, Object> grants = new HashMap<>();
        grants.put("room", roomCode);
        grants.put("roomJoin", true);
        grants.put("canPublishData", true);
        // 禁止录制: 不授予任何 recorder 权限
        grants.put("recorder", false);
        return grants;
    }

    private String buildToken(String identity, String name, Map<String, Object> videoGrants, boolean hidden) {
        long now = System.currentTimeMillis();
        return Jwts.builder()
                .issuer(livekit.getApiKey())
                .subject(identity)
                .claim("name", name)
                .claim("video", videoGrants)
                .claim("hidden", hidden)
                .issuedAt(new Date(now))
                .notBefore(new Date(now))
                .expiration(new Date(now + livekit.getTokenTtlMinutes() * 60_000L))
                // LiveKit 仅接受 HS256, 显式指定避免 jjwt 按密钥长度自动升级为 HS384/HS512
                .signWith(key, Jwts.SIG.HS256)
                .compact();
    }
}
