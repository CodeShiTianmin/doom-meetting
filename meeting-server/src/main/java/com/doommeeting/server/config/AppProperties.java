package com.doommeeting.server.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Getter
@Setter
@Component
@ConfigurationProperties(prefix = "app")
public class AppProperties {

    private Jwt jwt = new Jwt();
    private Invite invite = new Invite();
    private Room room = new Room();
    private Livekit livekit = new Livekit();

    @Getter
    @Setter
    public static class Jwt {
        private String secret;
        private int expireMinutes = 720;
    }

    @Getter
    @Setter
    public static class Invite {
        private int expireMinutes = 120;
        private String scheme = "meeting://join";
    }

    @Getter
    @Setter
    public static class Room {
        private int maxClients = 2;
        private int understaffedAlertMinutes = 3;
        private int heartbeatTimeoutSeconds = 60;
    }

    @Getter
    @Setter
    public static class Livekit {
        private String apiKey;
        private String apiSecret;
        private String wsUrl;
        private int tokenTtlMinutes = 180;
    }
}
