package com.doommeeting.server.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 一次性入会凭证(短时效 + 绑定房间 + 限用次数)
 */
@Getter
@Setter
@Entity
@Table(name = "invite_token", uniqueConstraints = @UniqueConstraint(columnNames = "token"))
public class InviteToken {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "room_id")
    private Room room;

    @Column(nullable = false, length = 64)
    private String token;

    @Column(nullable = false)
    private LocalDateTime expireAt;

    /** 限用次数(默认 2, 与房间人数上限一致) */
    @Column(nullable = false)
    private Integer maxUses = 2;

    @Column(nullable = false)
    private Integer usedCount = 0;

    @Column(nullable = false)
    private Boolean revoked = false;

    @Column(nullable = false)
    private LocalDateTime createdAt = LocalDateTime.now();
}
