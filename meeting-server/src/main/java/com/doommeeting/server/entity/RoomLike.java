package com.doommeeting.server.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 点赞记录: 手机端点赞按钮 -> 实时连接到 PC 端展示 -> 后端记录
 */
@Getter
@Setter
@Entity
@Table(name = "room_like", indexes = @Index(columnList = "room_id"))
public class RoomLike {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "room_id")
    private Room room;

    @Column(nullable = false, length = 64)
    private String memberIdentity;

    @Column(nullable = false, length = 64)
    private String nickname;

    @Column(nullable = false)
    private LocalDateTime likedAt = LocalDateTime.now();
}
