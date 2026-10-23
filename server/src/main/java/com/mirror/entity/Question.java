package com.mirror.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 题库表
 */
@Data
@TableName("question")
public class Question {

    @TableId(type = IdType.ASSIGN_UUID)
    private String id;

    /** 岗位，如 Java 后端 */
    private String job;

    /** 考察维度 */
    private String dimension;

    /** 难度 1-5 */
    private Integer difficulty;

    /** 题干 */
    private String stem;

    /** 考察要点，JSON 数组 */
    private String keyPoints;

    /** 参考答案 */
    private String refAnswer;

    /** 被使用次数 */
    private Integer usedCount;

    private LocalDateTime createdAt;
}
