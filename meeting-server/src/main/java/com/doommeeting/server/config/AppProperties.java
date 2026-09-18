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
    private Cors cors = new Cors();
    private Security security = new Security();
    private Invite invite = new Invite();
    private Room room = new Room();
    private Livekit livekit = new Livekit();
    private MobileApp mobileApp = new MobileApp();
    private Chat chat = new Chat();

    @Getter
    @Setter
    public static class Jwt {
        private String secret;
        private int expireMinutes = 720;
    }

    /** CORS 允许的前端域名(逗号分隔; * 表示开发环境全部允许) */
    @Getter
    @Setter
    public static class Cors {
        private String allowedOrigins = "*";
    }

    /** 生产安全开关: 开启后启动时拒绝默认密钥/默认管理员密码 */
    @Getter
    @Setter
    public static class Security {
        private boolean rejectDefaultSecrets = false;
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
        /** 固定房间数(1-N 号房, 启动时自动初始化) */
        private int fixedRoomCount = 24;
        /** 固定房间默认会议时长(分钟) */
        private int defaultDurationMinutes = 50;
    }

    /** 房间聊天图片: 保存在本地目录(按房间号分目录), 房间关闭时随聊天记录一并删除 */
    @Getter
    @Setter
    public static class Chat {
        private String imageDir = "./data/chat-images";
        /** 单张图片上限(MB) */
        private int imageMaxSizeMb = 10;
    }

    /** 手机 App 版本检查与 APK 私发下载(不上架应用商店) */
    @Getter
    @Setter
    public static class MobileApp {
        private int latestVersionCode = 1;
        private String latestVersionName = "1.0.0";
        private String apkDownloadUrl = "";
        private int minSupportedVersionCode = 1;
        private String releaseNotes = "";
    }

    @Getter
    @Setter
    public static class Livekit {
        private String apiKey;
        private String apiSecret;
        private String wsUrl;
        /** 服务端调用 LiveKit 管理 API 的内网地址, 为空时由 wsUrl 推导 */
        private String apiUrl;
        private int tokenTtlMinutes = 180;
    }
}
