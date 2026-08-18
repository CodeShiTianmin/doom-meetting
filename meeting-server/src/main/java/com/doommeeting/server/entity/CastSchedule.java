package com.doommeeting.server.entity;

import com.doommeeting.server.enums.CastScheduleStatus;
import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 定时投放计划: PC 端在不同时间选择不同内容投给不同房间。
 * 例如 8:00 投内容1到 A 房间, 8:01 投内容2到 B 房间, 两房并行、不串音不串频
 * (每房间独立播放器实例 + 独立 RTC 连接 + 独立音频轨)。
 */
@Getter
@Setter
@Entity
@Table(name = "cast_schedule", indexes = @Index(columnList = "castAt"))
public class CastSchedule {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "room_id")
    private Room room;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "content_id")
    private ContentItem content;

    /** 计划投放时间 */
    @Column(nullable = false)
    private LocalDateTime castAt;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private CastScheduleStatus status = CastScheduleStatus.PENDING;

    private LocalDateTime executedAt;

    @Column(length = 256)
    private String note;

    @Column(nullable = false, length = 64)
    private String createdBy;

    @Column(nullable = false)
    private LocalDateTime createdAt = LocalDateTime.now();
}
