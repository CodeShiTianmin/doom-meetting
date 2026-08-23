package com.doommeeting.server.service;

import com.doommeeting.server.config.AppProperties;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;

/**
 * LiveKit 服务端管理 API(Twirp): 踢出参与者等房间级操作。
 * 全部为尽力而为: LiveKit 不可达时不阻断业务, 客户端仍会依据 WS 事件自行退出。
 */
@Slf4j
@Service
public class LiveKitAdminService {

    private final AppProperties.Livekit livekit;
    private final SecretKey key;
    private final RestTemplate restTemplate;

    public LiveKitAdminService(AppProperties properties) {
        this.livekit = properties.getLivekit();
        this.key = Keys.hmacShaKeyFor(livekit.getApiSecret().getBytes(StandardCharsets.UTF_8));
        // 尽力而为调用: 设置超时, 避免 LiveKit 不可达时长时间阻塞业务线程
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(3_000);
        factory.setReadTimeout(5_000);
        this.restTemplate = new RestTemplate(factory);
    }

    /** 服务端强制移除参与者(踢人后立即断开其媒体连接) */
    public void removeParticipant(String roomCode, String identity) {
        callTwirp("RemoveParticipant", Map.of("room", roomCode, "identity", identity));
    }

    /** 服务端静音参与者的全部已发布音频轨 */
    public void muteParticipantTracks(String roomCode, String identity, boolean muted) {
        // MutePublishedTrack 需要 track_sid; 先查询参与者获取音频轨
        Map<?, ?> participant = callTwirp("GetParticipant",
                Map.of("room", roomCode, "identity", identity));
        if (participant == null || !(participant.get("tracks") instanceof Iterable<?> tracks)) {
            return;
        }
        for (Object item : tracks) {
            // 注意: protobuf JSON 会省略默认值字段, TrackType.AUDIO=0 时 type 可能缺失,
            // 因此把缺失的 type 也视为音频轨
            if (item instanceof Map<?, ?> track
                    && (track.get("type") == null || "AUDIO".equals(String.valueOf(track.get("type"))))
                    && track.get("sid") != null) {
                callTwirp("MutePublishedTrack", Map.of(
                        "room", roomCode,
                        "identity", identity,
                        "track_sid", String.valueOf(track.get("sid")),
                        "muted", muted));
            }
        }
    }

    private Map<?, ?> callTwirp(String method, Map<String, Object> body) {
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.setBearerAuth(adminToken(String.valueOf(body.get("room"))));
            return restTemplate.postForObject(
                    httpUrl() + "/twirp/livekit.RoomService/" + method,
                    new HttpEntity<>(body, headers),
                    Map.class);
        } catch (Exception e) {
            log.warn("LiveKit 管理 API {} 调用失败(忽略, 尽力而为): {}", method, e.getMessage());
            return null;
        }
    }

    private String httpUrl() {
        String wsUrl = livekit.getWsUrl();
        if (wsUrl.startsWith("wss://")) {
            return "https://" + wsUrl.substring(6);
        }
        if (wsUrl.startsWith("ws://")) {
            return "http://" + wsUrl.substring(5);
        }
        return wsUrl;
    }

    private String adminToken(String room) {
        long now = System.currentTimeMillis();
        Map<String, Object> grants = new HashMap<>();
        grants.put("roomAdmin", true);
        grants.put("room", room);
        return Jwts.builder()
                .issuer(livekit.getApiKey())
                .subject("meeting-server-admin")
                .claim("video", grants)
                .issuedAt(new Date(now))
                .expiration(new Date(now + 60_000L))
                .signWith(key)
                .compact();
    }
}
