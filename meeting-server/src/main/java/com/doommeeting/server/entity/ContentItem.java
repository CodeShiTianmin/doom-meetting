package com.doommeeting.server.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 投放内容(仅上传文件模式):
 * UPLOADED_FILE: 真实文件上传到服务器存储, 各端可下载打开, 会议结束后自动删除。
 * PC 屏幕共享直接经 LiveKit 推流, 不产生内容记录。
 */
@Getter
@Setter
@Entity
@Table(name = "content_item")
public class ContentItem {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 128)
    private String name;

    @Column(length = 512)
    private String description;

    /** UPLOADED_FILE: 服务器存储文件 */
    @Column(nullable = false, length = 16)
    private String type = "UPLOADED_FILE";

    /** 内容时长(秒, 媒体文件) */
    private Integer durationSeconds;

    /** 服务器存储相对路径(UPLOADED_FILE) */
    @Column(length = 512)
    private String storagePath;

    /** 文件大小(字节) */
    private Long fileSize;

    /** MIME 类型 */
    @Column(length = 128)
    private String mimeType;

    /** 关联房间(会议结束后自动删除该房间的上传文件) */
    private Long roomId;

    @Column(nullable = false)
    private Boolean enabled = true;

    @Column(nullable = false, length = 64)
    private String createdBy;

    @Column(nullable = false)
    private LocalDateTime createdAt = LocalDateTime.now();
}
