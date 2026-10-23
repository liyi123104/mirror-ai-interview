package com.mirror.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * AI 调用成本记录表
 */
@Data
@TableName("cost_log")
public class CostLog {

    @TableId(type = IdType.ASSIGN_UUID)
    private String id;

    private String sessionId;

    /** 调用场景，如 resume / question / evaluate */
    private String scene;

    private Integer tokensIn;

    private Integer tokensOut;

    private Double cost;

    private LocalDateTime createdAt;
}
