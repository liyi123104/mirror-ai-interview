package com.mirror.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.mirror.client.AiClient;
import com.mirror.common.BizException;
import com.mirror.entity.CostLog;
import com.mirror.entity.InterviewSession;
import com.mirror.entity.Report;
import com.mirror.entity.Turn;
import com.mirror.mapper.CostLogMapper;
import com.mirror.mapper.InterviewSessionMapper;
import com.mirror.mapper.ReportMapper;
import com.mirror.mapper.TurnMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;

@Slf4j
@Service
@RequiredArgsConstructor
public class ReportService {

    private final InterviewSessionMapper sessionMapper;
    private final TurnMapper turnMapper;
    private final ReportMapper reportMapper;
    private final CostLogMapper costLogMapper;
    private final AiClient ai;
    private final ObjectMapper json = new ObjectMapper();

    public Map<String, Object> build(String userId, String sessionId) {
        InterviewSession s = sessionMapper.selectById(sessionId);
        if (s == null || !s.getUserId().equals(userId)) {
            throw new BizException("面试不存在");
        }

        // 幂等：生成过就直接返回
        Report existing = reportMapper.selectOne(
                new LambdaQueryWrapper<Report>().eq(Report::getSessionId, sessionId));
        if (existing != null) {
            return toMap(existing);
        }

        List<Turn> questions = turnMapper.selectList(
                new LambdaQueryWrapper<Turn>()
                        .eq(Turn::getSessionId, sessionId)
                        .eq(Turn::getRole, "interviewer")
                        .orderByAsc(Turn::getSeq));

        if (questions.isEmpty()) {
            throw new BizException("这场面试还没有题目");
        }

        // 八题串行要四十秒，并发只要几秒
        long begin = System.currentTimeMillis();
        List<Map<String, Object>> usageSink = java.util.Collections.synchronizedList(new ArrayList<>());
        List<CompletableFuture<Map<String, Object>>> futures = questions.stream()
                .map(q -> CompletableFuture.supplyAsync(() -> buildItem(sessionId, q, usageSink)))
                .toList();

        List<Map<String, Object>> items = new ArrayList<>();
        for (CompletableFuture<Map<String, Object>> f : futures) {
            items.add(f.join());
        }
        log.info("复盘生成完成 session={} 题数={} 用时={}ms",
                sessionId, items.size(), System.currentTimeMillis() - begin);

        // 复盘也是花钱的，一样要记成本
        recordUsage(sessionId, "report", usageSink);

        double total = questions.stream()
                .mapToDouble(q -> q.getScore() == null ? 3 : q.getScore())
                .average().orElse(0);
        total = Math.round(total * 100) / 100.0;

        String verdict = verdictOf(total);

        List<String> nextSteps = items.stream()
                .map(i -> String.valueOf(i.get("gap")))
                .filter(g -> g != null && !g.isBlank())
                .distinct()
                .limit(3)
                .toList();

        List<Map<String, Object>> dimensions = dimensionAverages(questions);

        Report r = new Report();
        r.setSessionId(sessionId);
        r.setTotal(total);
        r.setVerdict(verdict);
        r.setDimensionsJson(writeJson(dimensions));
        r.setItemsJson(writeJson(items));
        r.setNextStepsJson(writeJson(nextSteps));
        r.setCreatedAt(LocalDateTime.now());
        reportMapper.insert(r);

        return toMap(r);
    }

    /** 雷达图的数据来源：把每题的各维度分按维度取平均。 */
    private List<Map<String, Object>> dimensionAverages(List<Turn> questions) {
        Map<String, Double> sum = new LinkedHashMap<>();
        Map<String, Integer> count = new HashMap<>();

        for (Turn q : questions) {
            if (q.getDimensionsJson() == null || q.getDimensionsJson().isBlank()) {
                continue;
            }
            try {
                JsonNode arr = json.readTree(q.getDimensionsJson());
                for (JsonNode d : arr) {
                    String name = d.path("dimension").asText("");
                    if (name.isBlank()) {
                        continue;
                    }
                    sum.merge(name, d.path("score").asDouble(0), Double::sum);
                    count.merge(name, 1, Integer::sum);
                }
            } catch (Exception e) {
                log.warn("维度分解析失败 seq={}", q.getSeq());
            }
        }

        List<Map<String, Object>> out = new ArrayList<>();
        for (Map.Entry<String, Double> e : sum.entrySet()) {
            int n = count.getOrDefault(e.getKey(), 1);
            double avg = Math.round(e.getValue() / n * 100) / 100.0;
            Map<String, Object> d = new LinkedHashMap<>();
            d.put("name", e.getKey());
            d.put("score", avg);
            out.add(d);
        }
        return out;
    }

    private Map<String, Object> buildItem(String sessionId, Turn q,
                                          List<Map<String, Object>> usageSink) {
        String answer = findAnswer(sessionId, q.getSeq());
        int score = q.getScore() == null ? 3 : q.getScore();

        try {
            JsonNode data = ai.reportItem(Map.of(
                    "question", q.getContent(),
                    "basedOn", q.getBasedOn() == null ? "" : q.getBasedOn(),
                    "answer", answer,
                    "score", score));

            JsonNode usage = data.path("usage");
            if (!usage.isMissingNode()) {
                usageSink.add(Map.of(
                        "tokensIn", usage.path("tokensIn").asInt(),
                        "tokensOut", usage.path("tokensOut").asInt(),
                        "cost", usage.path("cost").asDouble()));
            }

            Map<String, Object> item = new LinkedHashMap<>();
            item.put("seq", q.getSeq());
            item.put("question", q.getContent());
            item.put("basedOn", q.getBasedOn() == null ? "" : q.getBasedOn());
            item.put("answer", answer);
            item.put("score", score);
            item.put("gap", data.path("gap").asText(""));
            item.put("betterAnswer", data.path("betterAnswer").asText(""));
            return item;
        } catch (Exception e) {
            log.warn("复盘生成失败 seq={} {}", q.getSeq(), e.getMessage());

            Map<String, Object> item = new LinkedHashMap<>();
            item.put("seq", q.getSeq());
            item.put("question", q.getContent());
            item.put("basedOn", q.getBasedOn() == null ? "" : q.getBasedOn());
            item.put("answer", answer);
            item.put("score", score);
            item.put("gap", "复盘生成失败，请回看原文对照口径");
            item.put("betterAnswer", "");
            return item;
        }
    }

    private void recordUsage(String sessionId, String scene,
                             List<Map<String, Object>> sink) {
        if (sink.isEmpty()) {
            return;
        }

        int tin = sink.stream().mapToInt(m -> (int) m.get("tokensIn")).sum();
        int tout = sink.stream().mapToInt(m -> (int) m.get("tokensOut")).sum();
        double cost = sink.stream().mapToDouble(m -> (double) m.get("cost")).sum();

        CostLog log = new CostLog();
        log.setSessionId(sessionId);
        log.setScene(scene);
        log.setTokensIn(tin);
        log.setTokensOut(tout);
        log.setCost(Math.round(cost * 1_000_000) / 1_000_000.0);
        log.setCreatedAt(LocalDateTime.now());
        costLogMapper.insert(log);
    }

    /** 题目在 seq，回答在 seq + 1。 */
    private String findAnswer(String sessionId, int questionSeq) {
        Turn t = turnMapper.selectOne(new LambdaQueryWrapper<Turn>()
                .eq(Turn::getSessionId, sessionId)
                .eq(Turn::getSeq, questionSeq + 1));
        return t == null ? "" : t.getContent();
    }

    private String verdictOf(double total) {
        if (total >= 4.2) return "达到中高级水平，可以投递一线公司";
        if (total >= 3.5) return "达到中级水平，建议针对薄弱项补强";
        if (total >= 2.8) return "达到初级水平，基础可用，深度不足";
        if (total >= 2.0) return "有明显短板，建议系统复习后再练一轮";
        return "尚未准备好，先从基础概念补起";
    }

    public String toMarkdown(String userId, String sessionId) {
        Map<String, Object> r = build(userId, sessionId);

        StringBuilder sb = new StringBuilder();
        sb.append("# 面试报告\n\n");
        sb.append("总分：").append(r.get("total")).append(" / 5\n\n");
        sb.append("结论：").append(r.get("verdict")).append("\n\n");
        sb.append("## 逐题复盘\n\n");

        int i = 1;
        for (Object obj : (List<?>) r.get("items")) {
            Map<?, ?> item = (Map<?, ?>) obj;
            sb.append("### ").append(i++).append(". ").append(item.get("question")).append("\n\n");
            sb.append("- 考察依据：").append(item.get("basedOn")).append("\n");
            sb.append("- 得分：").append(item.get("score")).append(" 分\n");
            sb.append("- 差距：").append(item.get("gap")).append("\n");
            if (item.get("betterAnswer") != null && !String.valueOf(item.get("betterAnswer")).isBlank()) {
                sb.append("- 参考讲法：").append(item.get("betterAnswer")).append("\n");
            }
            sb.append("\n");
        }

        sb.append("## 下一步\n\n");
        for (Object s : (List<?>) r.get("nextSteps")) {
            sb.append("- ").append(s).append("\n");
        }
        return sb.toString();
    }

    private Map<String, Object> toMap(Report r) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("sessionId", r.getSessionId());
        m.put("total", r.getTotal());
        m.put("verdict", r.getVerdict());
        m.put("dimensions", readJson(r.getDimensionsJson(), List.class));
        m.put("items", readJson(r.getItemsJson(), List.class));
        m.put("nextSteps", readJson(r.getNextStepsJson(), List.class));
        return m;
    }

    private String writeJson(Object o) {
        try {
            return json.writeValueAsString(o);
        } catch (Exception e) {
            return "[]";
        }
    }

    private <T> T readJson(String s, Class<T> type) {
        try {
            return json.readValue(s, type);
        } catch (Exception e) {
            return null;
        }
    }
}
