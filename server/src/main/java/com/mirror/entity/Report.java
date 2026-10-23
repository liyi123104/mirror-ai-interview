package com.mirror.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 面试报告表
 */
@Data
@TableName("report")
public class Report {

    @TableId(type = IdType.ASSIGN_UUID)
    private String id;

    private String sessionId;

    /** 总分 */
    private Double total;

    /** 总体评价 */
    private String verdict;

    /** 各维度得分，JSON */
    private String dimensionsJson;

    /** 逐题点评，JSON */
    private String itemsJson;

    /** 提升建议，JSON */
    private String nextStepsJson;

    private LocalDateTime createdAt;
}
