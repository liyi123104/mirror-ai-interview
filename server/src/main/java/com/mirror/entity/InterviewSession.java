package com.mirror.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 面试会话表
 */
@Data
@TableName("interview_session")
public class InterviewSession {

    @TableId(type = IdType.ASSIGN_UUID)
    private String id;

    private String userId;

    private String job;

    /** 简历解析结果，JSON */
    private String resumeJson;

    /** 岗位 JD，JSON */
    private String jdJson;

    /** 状态：ongoing / finished */
    private String status;

    /** 已进行的提问轮数 */
    private Integer turnCount;

    /** 当前追问深度 */
    private Integer depth;

    /** 最后一道问题 */
    private String lastQuestion;

    /** 总评分 */
    private Double totalScore;

    private LocalDateTime startedAt;

    private LocalDateTime finishedAt;
}
