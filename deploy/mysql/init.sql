-- 多房并发投屏会议软件 - MySQL 8 初始化脚本(PC 端 LiveKit 实时推流, 无服务器文件存储)
CREATE DATABASE IF NOT EXISTS doom_meeting DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE doom_meeting;

-- 公司账号(PC 管理端登录)
CREATE TABLE IF NOT EXISTS user_account (
    id            BIGINT AUTO_INCREMENT PRIMARY KEY,
    username      VARCHAR(64)  NOT NULL,
    password_hash VARCHAR(128) NOT NULL,
    display_name  VARCHAR(64),
    role          VARCHAR(32)  NOT NULL DEFAULT 'ADMIN',
    created_at    DATETIME     NOT NULL,
    UNIQUE KEY uk_user_account_username (username)
) ENGINE = InnoDB;

-- 会议房间(单房间 2 个手机客户端; PC 端为后台隐藏角色)
CREATE TABLE IF NOT EXISTS room (
    id                        BIGINT AUTO_INCREMENT PRIMARY KEY,
    room_code                 VARCHAR(16) NOT NULL,
    name                      VARCHAR(64) NOT NULL,
    status                    VARCHAR(16) NOT NULL DEFAULT 'WAITING',
    video_call_enabled        TINYINT(1)  NOT NULL DEFAULT 1,
    camera_enabled            TINYINT(1)  NOT NULL DEFAULT 1,
    screenshot_allowed        TINYINT(1)  NOT NULL DEFAULT 1,
    recording_forbidden       TINYINT(1)  NOT NULL DEFAULT 1,
    duration_minutes          INT         NOT NULL,
    meeting_start_at          DATETIME,
    meeting_end_at            DATETIME,
    cast_type                 VARCHAR(16),
    cast_label                VARCHAR(128),
    cast_by                   VARCHAR(64),
    like_count                BIGINT      NOT NULL DEFAULT 0,
    understaffed_alert        TINYINT(1)  NOT NULL DEFAULT 0,
    understaffed_since        DATETIME,
    reminder5_sent            TINYINT(1)  NOT NULL DEFAULT 0,
    reminder1_sent            TINYINT(1)  NOT NULL DEFAULT 0,
    close_reason              VARCHAR(16),
    closed_at                 DATETIME,
    created_by                VARCHAR(64) NOT NULL,
    created_at                DATETIME    NOT NULL,
    UNIQUE KEY uk_room_code (room_code),
    KEY idx_room_status (status)
) ENGINE = InnoDB;

-- 手机客户端入会记录
CREATE TABLE IF NOT EXISTS room_member (
    id                BIGINT AUTO_INCREMENT PRIMARY KEY,
    room_id           BIGINT      NOT NULL,
    identity          VARCHAR(64) NOT NULL,
    nickname          VARCHAR(64) NOT NULL,
    device_info       VARCHAR(128),
    online            TINYINT(1)  NOT NULL DEFAULT 1,
    joined_at         DATETIME    NOT NULL,
    left_at           DATETIME,
    last_heartbeat_at DATETIME,
    KEY idx_room_member_room (room_id),
    CONSTRAINT fk_member_room FOREIGN KEY (room_id) REFERENCES room (id)
) ENGINE = InnoDB;

-- 一次性入会凭证
CREATE TABLE IF NOT EXISTS invite_token (
    id         BIGINT AUTO_INCREMENT PRIMARY KEY,
    room_id    BIGINT      NOT NULL,
    token      VARCHAR(64) NOT NULL,
    expire_at  DATETIME    NOT NULL,
    max_uses   INT         NOT NULL DEFAULT 2,
    used_count INT         NOT NULL DEFAULT 0,
    revoked    TINYINT(1)  NOT NULL DEFAULT 0,
    created_at DATETIME    NOT NULL,
    UNIQUE KEY uk_invite_token (token),
    CONSTRAINT fk_invite_room FOREIGN KEY (room_id) REFERENCES room (id)
) ENGINE = InnoDB;

-- 点赞记录(手机端点赞 -> PC 端实时展示 -> 后端记录)
CREATE TABLE IF NOT EXISTS room_like (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    room_id         BIGINT      NOT NULL,
    member_identity VARCHAR(64) NOT NULL,
    nickname        VARCHAR(64) NOT NULL,
    liked_at        DATETIME    NOT NULL,
    KEY idx_room_like_room (room_id),
    CONSTRAINT fk_like_room FOREIGN KEY (room_id) REFERENCES room (id)
) ENGINE = InnoDB;

-- 房间事件日志
CREATE TABLE IF NOT EXISTS room_event_log (
    id         BIGINT AUTO_INCREMENT PRIMARY KEY,
    room_id    BIGINT      NOT NULL,
    type       VARCHAR(32) NOT NULL,
    detail     VARCHAR(512),
    created_at DATETIME    NOT NULL,
    KEY idx_room_event_room (room_id),
    CONSTRAINT fk_event_room FOREIGN KEY (room_id) REFERENCES room (id)
) ENGINE = InnoDB;
