package com.mirror.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.mirror.client.AiClient;
import com.mirror.common.BizException;
import com.mirror.dto.QuestionCreateRequest;
import com.mirror.entity.Question;
import com.mirror.mapper.QuestionMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class QuestionService {

    private final QuestionMapper mapper;
    private final AiClient ai;
    private final ObjectMapper json = new ObjectMapper();

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

        // 通知 AI 服务建索引。失败不影响主流程：题目已经在库里了
        try {
            ai.indexQuestions(Map.of("questions", List.of(Map.of(
                    "id", q.getId(),
                    "stem", q.getStem(),
                    "job", q.getJob(),
                    "dimension", q.getDimension() == null ? "" : q.getDimension()))));
        } catch (Exception e) {
            log.warn("索引同步失败，题目已存但暂时检索不到：{}", e.getMessage());
        }

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
        try {
            ai.removeQuestionIndex(id);
        } catch (Exception e) {
            log.warn("索引删除失败，Python 侧可能还留着这道题：{}", e.getMessage());
        }
    }

    /** 语义检索走 Python 的向量索引，Java 不自己算。 */
    public List<Map<String, Object>> search(String query, String job, int topK) {
        if (query == null || query.isBlank()) {
            throw new BizException("搜索词不能为空");
        }

        JsonNode data = ai.searchQuestions(query.strip(), job, topK);
        return json.convertValue(data.path("items"),
                new TypeReference<List<Map<String, Object>>>() {});
    }

    /** 全量题目，启动时推给 Python 建索引用。 */
    public List<Question> all() {
        return mapper.selectList(null);
    }
}
