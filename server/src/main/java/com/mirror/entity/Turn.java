package com.mirror.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 对话轮次表
 */
@Data
@TableName("turn")
public class Turn {

    @TableId(type = IdType.ASSIGN_UUID)
    private String id;

    private String sessionId;

    /** 轮次序号，从 1 开始 */
    private Integer seq;

    /** 角色：user / ai */
    private String role;

    private String content;

    /** 本题来源：resume / jd / dimension */
    private String basedOn;

    private String dimension;

    private Integer depth;

    /** 本轮评分 */
    private Integer score;

    private Integer tokensIn;

    private Integer tokensOut;

    private Double cost;

    private LocalDateTime createdAt;
}
