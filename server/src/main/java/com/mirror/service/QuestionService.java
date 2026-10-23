package com.mirror.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.mirror.common.BizException;
import com.mirror.dto.QuestionCreateRequest;
import com.mirror.entity.Question;
import com.mirror.mapper.QuestionMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
public class QuestionService {

    private final QuestionMapper mapper;

    public Question create(QuestionCreateRequest req) {
        Question q = new Question();
        q.setJob(req.job());
        q.setDimension(req.dimension());
        q.setStem(req.stem());
        q.setKeyPoints(req.keyPoints());
        q.setRefAnswer(req.refAnswer());
        q.setDifficulty(req.difficulty() == null ? 3 : req.difficulty());
        q.setUsedCount(0);
        q.setCreatedAt(LocalDateTime.now());

        mapper.insert(q);
        return q;
    }

    public Question get(String id) {
        Question q = mapper.selectById(id);
        if (q == null) {
            throw new BizException("题目不存在");
        }
        return q;
    }

    public Page<Question> page(String job, int pageNo, int size) {
        LambdaQueryWrapper<Question> wrapper = new LambdaQueryWrapper<>();
        if (job != null && !job.isBlank()) {
            wrapper.eq(Question::getJob, job);
        }
        wrapper.orderByDesc(Question::getCreatedAt);

        return mapper.selectPage(new Page<>(pageNo, size), wrapper);
    }

    public List<Question> listByJob(String job, int limit) {
        LambdaQueryWrapper<Question> wrapper = new LambdaQueryWrapper<>();
        if (job != null && !job.isBlank()) {
            wrapper.eq(Question::getJob, job);
        }
        wrapper.last("LIMIT " + limit);
        return mapper.selectList(wrapper);
    }

    public void delete(String id) {
        mapper.deleteById(id);
    }
}