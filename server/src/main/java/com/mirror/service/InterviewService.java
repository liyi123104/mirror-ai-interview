package com.mirror.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.mirror.client.AiClient;
import com.mirror.common.BizException;
import com.mirror.config.AiProperties;
import com.mirror.entity.CostLog;
import com.mirror.entity.InterviewSession;
import com.mirror.entity.Turn;
import com.mirror.mapper.CostLogMapper;
import com.mirror.mapper.InterviewSessionMapper;
import com.mirror.mapper.TurnMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class InterviewService {

    private final InterviewSessionMapper sessionMapper;
    private final TurnMapper turnMapper;
    private final CostLogMapper costLogMapper;
    private final AiClient ai;
    private final AiProperties aiProps;
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
        recordCost(s.getId(), "question", data);

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

        // 先给这道题打分，再决定要不要出下一题。评分失败不影响面试继续
        try {
            JsonNode scoreData = ai.score(Map.of(
                    "question", s.getLastQuestion() == null ? "" : s.getLastQuestion(),
                    "answer", answer,
                    "dimensions", scoreDimensions()));
            updateLatestScore(sessionId,
                    (int) Math.round(scoreData.path("total").asDouble(3.0)),
                    scoreData.path("dimensions"));
            recordCost(sessionId, "score", scoreData);
        } catch (Exception e) {
            log.warn("评分失败，本题不计分：{}", e.getMessage());
        }

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
        recordCost(sessionId, "question", data);

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

    /** 评分维度来自配置，默认两维（四维双评一场要六十多次调用，太贵） */
    private List<String> scoreDimensions() {
        return Arrays.stream(aiProps.getScoreDimensions().split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .toList();
    }

    /** 把分数写到“刚答的那道题”上：最后一条 interviewer 记录。 */
    private void updateLatestScore(String sessionId, int score, JsonNode dimensions) {
        Turn last = turnMapper.selectOne(new LambdaQueryWrapper<Turn>()
                .eq(Turn::getSessionId, sessionId)
                .eq(Turn::getRole, "interviewer")
                .orderByDesc(Turn::getSeq)
                .last("LIMIT 1"));

        if (last != null) {
            last.setScore(score);
            if (dimensions != null && !dimensions.isMissingNode() && !dimensions.isNull()) {
                try {
                    last.setDimensionsJson(json.writeValueAsString(dimensions));
                } catch (Exception e) {
                    log.warn("维度分序列化失败：{}", e.getMessage());
                }
            }
            turnMapper.updateById(last);
        }
    }

    private void recordCost(String sessionId, String scene, JsonNode data) {
        JsonNode usage = data.path("usage");
        if (usage.isMissingNode()) {
            return;
        }

        try {
            CostLog log = new CostLog();
            log.setSessionId(sessionId);
            log.setScene(scene);
            log.setTokensIn(usage.path("tokensIn").asInt());
            log.setTokensOut(usage.path("tokensOut").asInt());
            log.setCost(usage.path("cost").asDouble());
            log.setCreatedAt(LocalDateTime.now());
            costLogMapper.insert(log);
        } catch (Exception e) {
            log.warn("成本记录失败 scene={} {}", scene, e.getMessage());
        }
    }

    /** 成本统计：总花费、总 token、场次、单场均值 */
    public Map<String, Object> stats() {
        List<CostLog> logs = costLogMapper.selectList(null);

        double totalCost = logs.stream().mapToDouble(l -> l.getCost() == null ? 0 : l.getCost()).sum();
        int totalIn = logs.stream().mapToInt(l -> l.getTokensIn() == null ? 0 : l.getTokensIn()).sum();
        int totalOut = logs.stream().mapToInt(l -> l.getTokensOut() == null ? 0 : l.getTokensOut()).sum();
        long sessions = logs.stream().map(CostLog::getSessionId).filter(s -> s != null).distinct().count();

        Map<String, Object> out = new HashMap<>();
        out.put("totalCost", Math.round(totalCost * 10000) / 10000.0);
        out.put("totalTokensIn", totalIn);
        out.put("totalTokensOut", totalOut);
        out.put("sessions", sessions);
        out.put("avgCostPerSession", sessions == 0 ? 0
                : Math.round(totalCost / sessions * 10000) / 10000.0);
        return out;
    }
}
