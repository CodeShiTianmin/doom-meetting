package com.doommeeting.server.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 手机客户端入会记录(PC 投屏端为后台隐藏角色, 不计入成员)
 */
@Getter
@Setter
@Entity
@Table(name = "room_member", indexes = @Index(columnList = "room_id"))
public class RoomMember {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "room_id")
    private Room room;

    /** 会内唯一身份标识(免注册匿名入会) */
    @Column(nullable = false, length = 64)
    private String identity;

    /** 会话级成员凭证: 入会时签发, 后续 REST/WS 请求校验 */
    @Column(nullable = false, length = 64)
    private String memberToken;

    /** 绑定的入会凭证(座位), 离线复用按凭证匹配而非昵称 */
    @Column(name = "invite_token_id")
    private Long inviteTokenId;

    /** 座位号(每个座位独立二维码) */
    private Integer seatNo;

    @Column(nullable = false, length = 64)
    private String nickname;

    @Column(length = 128)
    private String deviceInfo;

    @Column(nullable = false)
    private Boolean online = true;

    /** 主持人静音 */
    @Column(nullable = false)
    private Boolean muted = false;

    /** 主持人禁止开摄像头 */
    @Column(nullable = false)
    private Boolean cameraDisabled = false;

    /** 已被主持人移出会议, 禁止再次入会 */
    @Column(nullable = false)
    private Boolean kicked = false;

    /** 等候室审批: 需管理员批准后才能入会 */
    @Column(nullable = false)
    private Boolean approved = true;

    /** 累计出席时长(秒), 离线时结算 */
    @Column(nullable = false)
    private Long onlineSeconds = 0L;

    /** 上线次数(joinCount-1 即离会/掉线次数) */
    @Column(nullable = false)
    private Integer joinCount = 0;

    /** 本次上线开始时间(结算出席时长用) */
    private LocalDateTime lastOnlineAt;

    @Column(nullable = false)
    private LocalDateTime joinedAt = LocalDateTime.now();

    private LocalDateTime leftAt;

    private LocalDateTime lastHeartbeatAt;
}
