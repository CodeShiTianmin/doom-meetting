package com.doommeeting.server.entity;

import com.doommeeting.server.enums.CastType;
import com.doommeeting.server.enums.CloseReason;
import com.doommeeting.server.enums.RoomStatus;
import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;
import org.hibernate.annotations.ColumnDefault;

import java.time.LocalDateTime;

/**
 * 会议房间。单房间成员数可设置(默认 2 个手机客户端);
 * 公司 PC 端以后台身份推流与管理, 不出现在房间成员中。
 * 非空列均声明 @ColumnDefault: ddl-auto 在已有表上新增列时,
 * 已有数据行按该默认值回填, 与 Java 字段初始值保持一致。
 */
@Getter
@Setter
@Entity
@Table(name = "room", uniqueConstraints = @UniqueConstraint(columnNames = "roomCode"))
public class Room {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 房号(二维码/入会链接使用) */
    @Column(nullable = false, length = 16)
    private String roomCode;

    @Column(nullable = false, length = 64)
    private String name;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private RoomStatus status = RoomStatus.WAITING;

    /** 房间成员数上限(手机客户端, PC 端创建/设置时可指定) */
    @ColumnDefault("2")
    @Column(nullable = false)
    private Integer maxMembers = 2;

    /** 手机端"视频通话"功能开关(PC 端按房间设置) */
    @ColumnDefault("1")
    @Column(nullable = false)
    private Boolean videoCallEnabled = true;

    /** 手机端"摄像头"功能开关(PC 端按房间设置) */
    @ColumnDefault("0")
    @Column(nullable = false)
    private Boolean cameraEnabled = false;

    /** 允许截屏(固定放开) */
    @ColumnDefault("1")
    @Column(nullable = false)
    private Boolean screenshotAllowed = true;

    /** 禁止录制(录屏检测 + 遮挡上报) */
    @ColumnDefault("1")
    @Column(nullable = false)
    private Boolean recordingForbidden = true;

    /** 会议时长(分钟), PC 端设置, 到期自动关闭 */
    @Column(nullable = false)
    private Integer durationMinutes;

    /** 预约开始时间(为空表示创建即进入等待) */
    private LocalDateTime scheduledStartAt;

    /** 等候室: 入会需管理员批准 */
    @ColumnDefault("0")
    @Column(nullable = false)
    private Boolean approvalRequired = false;

    /** 全员静音 */
    @ColumnDefault("0")
    @Column(nullable = false)
    private Boolean allMuted = false;

    /** 全部成员就位, 会议开始时间 */
    private LocalDateTime meetingStartAt;

    /** 会议自动关闭时间 = meetingStartAt + durationMinutes */
    private LocalDateTime meetingEndAt;

    /** 当前推流投放类型(为空表示无投放) */
    @Enumerated(EnumType.STRING)
    @Column(length = 16)
    private CastType castType;

    /** 当前推流内容说明(视频文件名/摄像头/屏幕源名称) */
    @Column(length = 128)
    private String castLabel;

    /** 推流发起人 */
    @Column(length = 64)
    private String castBy;

    /** 点赞总数 */
    @ColumnDefault("0")
    @Column(nullable = false)
    private Long likeCount = 0L;

    /** 红灯预警: 缺人状态超过阈值 */
    @ColumnDefault("0")
    @Column(nullable = false)
    private Boolean understaffedAlert = false;

    /** 缺人状态开始时间(在线手机客户端 < 成员数上限时记录) */
    private LocalDateTime understaffedSince;

    /** 到期前提醒标记(剩余5分钟 / 剩余1分钟) */
    @ColumnDefault("0")
    @Column(nullable = false)
    private Boolean reminder5Sent = false;

    @ColumnDefault("0")
    @Column(nullable = false)
    private Boolean reminder1Sent = false;

    @Enumerated(EnumType.STRING)
    @Column(length = 16)
    private CloseReason closeReason;

    private LocalDateTime closedAt;

    @Column(nullable = false, length = 64)
    private String createdBy;

    @Column(nullable = false)
    private LocalDateTime createdAt = LocalDateTime.now();
}
