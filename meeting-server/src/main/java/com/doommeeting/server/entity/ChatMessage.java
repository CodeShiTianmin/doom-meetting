package com.doommeeting.server.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 会中文字聊天/表情消息(复用房间 STOMP 通道广播)
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

    /** 发送者身份(成员 identity 或 admin-<用户名>) */
    @Column(nullable = false, length = 64)
    private String senderIdentity;

    @Column(nullable = false, length = 64)
    private String senderNickname;

    /** 文本内容(含 emoji, UTF-8) */
    @Column(nullable = false, length = 512)
    private String content;

    @Column(nullable = false)
    private LocalDateTime createdAt = LocalDateTime.now();
}
