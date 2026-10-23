package com.mirror.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 用户表
 */
@Data
@TableName("app_user")
public class AppUser {

    @TableId(type = IdType.ASSIGN_UUID)
    private String id;

    private String username;

    private String passwordHash;

    private LocalDateTime createdAt;
}
