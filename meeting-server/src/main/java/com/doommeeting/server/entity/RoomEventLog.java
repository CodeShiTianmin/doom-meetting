package com.doommeeting.server.entity;

import com.doommeeting.server.enums.RoomEventType;
import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 房间事件日志(仅元数据, 无任何媒体内容)
 */
@Getter
@Setter
@Entity
@Table(name = "room_event_log", indexes = @Index(columnList = "room_id"))
public class RoomEventLog {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "room_id")
    private Room room;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 32)
    private RoomEventType type;

    @Column(length = 512)
    private String detail;

    @Column(nullable = false)
    private LocalDateTime createdAt = LocalDateTime.now();
}
