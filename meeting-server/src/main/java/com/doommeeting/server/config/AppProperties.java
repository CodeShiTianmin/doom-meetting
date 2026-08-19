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
    private FileToken fileToken = new FileToken();
    private Cors cors = new Cors();
    private Security security = new Security();
    private Invite invite = new Invite();
    private Room room = new Room();
    private Livekit livekit = new Livekit();
    private MobileApp mobileApp = new MobileApp();

    @Getter
    @Setter
    public static class Jwt {
        private String secret;
        private int expireMinutes = 720;
    }

    /** 文件访问短时效签名 token */
    @Getter
    @Setter
    public static class FileToken {
        private int ttlMinutes = 240;
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
        private int tokenTtlMinutes = 180;
    }
}
