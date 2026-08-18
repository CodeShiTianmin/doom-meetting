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

    @Column(nullable = false, length = 64)
    private String nickname;

    @Column(length = 128)
    private String deviceInfo;

    @Column(nullable = false)
    private Boolean online = true;

    @Column(nullable = false)
    private LocalDateTime joinedAt = LocalDateTime.now();

    private LocalDateTime leftAt;

    private LocalDateTime lastHeartbeatAt;
}
