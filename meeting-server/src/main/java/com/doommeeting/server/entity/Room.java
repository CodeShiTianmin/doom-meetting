package com.doommeeting.server.entity;

import com.doommeeting.server.enums.CloseReason;
import com.doommeeting.server.enums.PlaybackState;
import com.doommeeting.server.enums.RoomStatus;
import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 会议房间。单房间成员数可设置(默认 2 个手机客户端);
 * 公司 PC 端以后台身份推流与管理, 不出现在房间成员中。
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
    @Column(nullable = false)
    private Integer maxMembers = 2;

    /** 手机端"视频通话"功能开关(PC 端按房间设置) */
    @Column(nullable = false)
    private Boolean videoCallEnabled = true;

    /** 手机端"摄像头"功能开关(PC 端按房间设置) */
    @Column(nullable = false)
    private Boolean cameraEnabled = true;

    /** 允许截屏(固定放开) */
    @Column(nullable = false)
    private Boolean screenshotAllowed = true;

    /** 禁止录制(录屏检测 + 遮挡上报) */
    @Column(nullable = false)
    private Boolean recordingForbidden = true;

    /** 会议时长(分钟), PC 端设置, 到期自动关闭 */
    @Column(nullable = false)
    private Integer durationMinutes;

    /** 全部成员就位, 会议开始时间 */
    private LocalDateTime meetingStartAt;

    /** 会议自动关闭时间 = meetingStartAt + durationMinutes */
    private LocalDateTime meetingEndAt;

    /** 当前投放内容 */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "current_content_id")
    private ContentItem currentContent;

    /** 播放状态(手机端控制, 后端串行转发权威状态) */
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private PlaybackState playbackState = PlaybackState.IDLE;

    /** 播放进度(秒) */
    @Column(nullable = false)
    private Double playbackPositionSeconds = 0.0;

    /** 最后一条播放控制指令序号(解决两客户端同时操作冲突) */
    @Column(nullable = false)
    private Long lastCommandSeq = 0L;

    private LocalDateTime playbackUpdatedAt;

    /** PC 端屏幕/窗口共享中(跨端冲突检查用) */
    @Column(nullable = false)
    private Boolean screenSharing = false;

    /** 屏幕共享发起人 */
    @Column(length = 64)
    private String screenShareBy;

    /** 点赞总数 */
    @Column(nullable = false)
    private Long likeCount = 0L;

    /** 红灯预警: 缺人状态超过阈值 */
    @Column(nullable = false)
    private Boolean understaffedAlert = false;

    /** 缺人状态开始时间(在线手机客户端 < 成员数上限时记录) */
    private LocalDateTime understaffedSince;

    /** 到期前提醒标记(剩余5分钟 / 剩余1分钟) */
    @Column(nullable = false)
    private Boolean reminder5Sent = false;

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
