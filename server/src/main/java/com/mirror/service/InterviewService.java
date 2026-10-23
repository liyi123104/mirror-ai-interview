package com.mirror.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.mirror.client.AiClient;
import com.mirror.common.BizException;
import com.mirror.entity.InterviewSession;
import com.mirror.entity.Turn;
import com.mirror.mapper.InterviewSessionMapper;
import com.mirror.mapper.TurnMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class InterviewService {

    private final InterviewSessionMapper sessionMapper;
    private final TurnMapper turnMapper;
    private final AiClient ai;
    private final ObjectMapper json = new ObjectMapper();

    private static final int MAX_TURNS = 8;

    @Transactional
    public Map<String, Object> start(String userId, String job, String resumeJson, String jdJson) {
        InterviewSession s = new InterviewSession();
        s.setUserId(userId);
        s.setJob(job);
        s.setResumeJson(resumeJson == null ? "{}" : resumeJson);
        s.setJdJson(jdJson == null ? "[]" : jdJson);
        s.setStatus("ONGOING");
        s.setTurnCount(0);
        s.setDepth(0);
        s.setStartedAt(LocalDateTime.now());
        sessionMapper.insert(s);

        // 题干来自 Python（第 1–2 周是假数据，第 3 周起换成真生成）
        JsonNode data = ai.nextQuestion(buildRequest(s, "", "", 0));

        String stem = data.path("stem").asText();
        s.setLastQuestion(stem);
        sessionMapper.updateById(s);

        saveTurn(s.getId(), 1, "interviewer", stem,
                data.path("basedOn").asText(), data.path("dimension").asText(), 0);

        Map<String, Object> out = new HashMap<>();
        out.put("sessionId", s.getId());
        out.put("type", data.path("type").asText());
        out.put("stem", stem);
        out.put("basedOn", data.path("basedOn").asText());
        return out;
    }

    @Transactional
    public Map<String, Object> answer(String userId, String sessionId, String answer) {
        InterviewSession s = sessionMapper.selectById(sessionId);

        if (s == null) {
            throw new BizException("面试不存在");
        }
        if (!s.getUserId().equals(userId)) {
            throw new BizException(4030, "无权访问这场面试");
        }
        if (!"ONGOING".equals(s.getStatus())) {
            throw new BizException("这场面试已经结束");
        }
        if (answer == null || answer.strip().length() < 2) {
            throw new BizException("回答太短了");
        }

        int seq = s.getTurnCount() * 2 + 2;
        saveTurn(sessionId, seq, "candidate", answer, null, null, s.getDepth());

        s.setTurnCount(s.getTurnCount() + 1);

        // 结束判断在追问之前：最后一题答完直接结束
        if (s.getTurnCount() >= MAX_TURNS) {
            s.setStatus("FINISHED");
            s.setFinishedAt(LocalDateTime.now());
            sessionMapper.updateById(s);
            return Map.of("finished", true, "sessionId", sessionId);
        }

        JsonNode data = ai.nextQuestion(
                buildRequest(s, s.getLastQuestion(), answer, s.getDepth()));

        boolean follow = "follow_up".equals(data.path("type").asText());
        String stem = data.path("stem").asText();

        // 换新题时深度归零，否则第二题一上来就没法追问
        s.setDepth(follow ? s.getDepth() + 1 : 0);
        s.setLastQuestion(stem);
        sessionMapper.updateById(s);

        saveTurn(sessionId, seq + 1, "interviewer", stem,
                data.path("basedOn").asText(),
                data.path("dimension").asText(), s.getDepth());

        Map<String, Object> out = new HashMap<>();
        out.put("finished", false);
        out.put("type", data.path("type").asText());
        out.put("stem", stem);
        return out;
    }

    public Map<String, Object> state(String userId, String sessionId) {
        InterviewSession s = sessionMapper.selectById(sessionId);
        if (s == null) {
            throw new BizException("面试不存在");
        }
        if (!s.getUserId().equals(userId)) {
            throw new BizException(4030, "无权访问这场面试");
        }

        List<Turn> turns = turnMapper.selectList(
                new LambdaQueryWrapper<Turn>()
                        .eq(Turn::getSessionId, sessionId)
                        .orderByAsc(Turn::getSeq));

        Map<String, Object> out = new HashMap<>();
        out.put("sessionId", s.getId());
        out.put("status", s.getStatus());
        out.put("turnCount", s.getTurnCount());
        out.put("turns", turns);
        return out;
    }

    /** 组装契约五的请求体。JSON 解析失败就走空对象，不让脏数据卡住面试。 */
    private Map<String, Object> buildRequest(InterviewSession s, String lastQ,
                                             String lastA, int depth) {
        Map<String, Object> req = new HashMap<>();
        req.put("sessionId", s.getId());
        req.put("job", s.getJob());

        try {
            req.put("resume", json.readValue(s.getResumeJson(), Map.class));
            req.put("requirements", json.readValue(s.getJdJson(), List.class));
        } catch (Exception e) {
            req.put("resume", Map.of());
            req.put("requirements", List.of());
        }

        req.put("asked", recentQuestions(s.getId()));
        req.put("lastQuestion", lastQ);
        req.put("lastAnswer", lastA);
        req.put("depth", depth);
        req.put("maxDepth", 2);
        return req;
    }

    private List<String> recentQuestions(String sessionId) {
        return turnMapper.selectList(new LambdaQueryWrapper<Turn>()
                        .eq(Turn::getSessionId, sessionId)
                        .eq(Turn::getRole, "interviewer")
                        .orderByAsc(Turn::getSeq))
                .stream().map(Turn::getContent).toList();
    }

    private void saveTurn(String sessionId, int seq, String role, String content,
                          String basedOn, String dimension, int depth) {
        Turn t = new Turn();
        t.setSessionId(sessionId);
        t.setSeq(seq);
        t.setRole(role);
        t.setContent(content);
        t.setBasedOn(basedOn);
        t.setDimension(dimension);
        t.setDepth(depth);
        t.setCreatedAt(LocalDateTime.now());
        turnMapper.insert(t);
    }
}
