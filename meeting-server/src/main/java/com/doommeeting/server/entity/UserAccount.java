package com.doommeeting.server.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 公司账号(PC 管理端登录)
 */
@Getter
@Setter
@Entity
@Table(name = "user_account", uniqueConstraints = @UniqueConstraint(columnNames = "username"))
public class UserAccount {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 64)
    private String username;

    @Column(nullable = false, length = 128)
    private String passwordHash;

    @Column(length = 64)
    private String displayName;

    @Column(nullable = false, length = 32)
    private String role = "ADMIN";

    @Column(nullable = false)
    private LocalDateTime createdAt = LocalDateTime.now();
}
