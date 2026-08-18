package com.doommeeting.server.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 投放内容。支持两种模式:
 * - UPLOADED_FILE: 真实文件上传到服务器存储, 各端可下载打开, 会议结束后自动删除
 * - LOCAL_FILE / SCREEN / WINDOW: 仅登记元数据, 媒体由 PC 端本地推流
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

    /** UPLOADED_FILE: 服务器存储文件 / LOCAL_FILE: 本地视频文件 / SCREEN: 整屏投屏 / WINDOW: 窗口投屏 */
    @Column(nullable = false, length = 16)
    private String type = "LOCAL_FILE";

    /** 本地 PC 上的文件路径或窗口标识(仅元数据) */
    @Column(length = 512)
    private String localPath;

    /** 内容时长(秒, 本地视频文件) */
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
