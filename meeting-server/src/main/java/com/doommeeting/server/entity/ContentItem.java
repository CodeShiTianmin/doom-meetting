package com.doommeeting.server.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 投放内容元数据。方案资料只存储在本地 PC, 不上传云端;
 * 服务器仅登记名称/本地路径等元数据, 不存储任何媒体内容。
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

    /** LOCAL_FILE: 本地视频文件 / SCREEN: 整屏投屏 / WINDOW: 窗口投屏 */
    @Column(nullable = false, length = 16)
    private String type = "LOCAL_FILE";

    /** 本地 PC 上的文件路径或窗口标识(仅元数据) */
    @Column(length = 512)
    private String localPath;

    /** 内容时长(秒, 本地视频文件) */
    private Integer durationSeconds;

    @Column(nullable = false)
    private Boolean enabled = true;

    @Column(nullable = false, length = 64)
    private String createdBy;

    @Column(nullable = false)
    private LocalDateTime createdAt = LocalDateTime.now();
}
