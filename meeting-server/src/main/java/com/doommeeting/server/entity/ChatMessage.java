package com.doommeeting.server.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 文字聊天消息: 手机端成员与 PC 管理端均可发送, 房间内实时同步
 */
@Getter
@Setter
@Entity
@Table(name = "chat_message", indexes = @Index(columnList = "room_id"))
public class ChatMessage {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "room_id")
    private Room room;

    /** 发送者身份(成员 identity, PC 端为 admin 用户名) */
    @Column(nullable = false, length = 64)
    private String senderIdentity;

    @Column(nullable = false, length = 64)
    private String senderNickname;

    /** 是否为 PC 管理端发送 */
    @Column(nullable = false)
    private Boolean fromAdmin = false;

    @Column(nullable = false, length = 500)
    private String content;

    @Column(nullable = false)
    private LocalDateTime sentAt = LocalDateTime.now();
}
