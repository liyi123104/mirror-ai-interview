package com.mirror.config;

import com.mirror.client.AiClient;
import com.mirror.entity.Question;
import com.mirror.mapper.QuestionMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

/**
 * Python 的向量索引在内存里，重启就没了。
 * Java 每次启动补推一次全量题目，两边就对齐了。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class StartupSync {

    private final QuestionMapper questionMapper;
    private final AiClient ai;

    @EventListener(ApplicationReadyEvent.class)
    public void sync() {
        List<Question> all = questionMapper.selectList(null);
        if (all.isEmpty()) {
            log.info("题库为空，跳过启动同步");
            return;
        }

        try {
            List<Map<String, Object>> items = all.stream()
                    .map(q -> Map.<String, Object>of(
                            "id", q.getId(),
                            "stem", q.getStem(),
                            "job", q.getJob(),
                            "dimension", q.getDimension() == null ? "" : q.getDimension()))
                    .toList();

            ai.indexQuestions(Map.of("questions", items));
            log.info("启动时同步了 {} 道题到向量索引", items.size());
        } catch (Exception e) {
            log.warn("启动同步失败，AI 服务可能还没起来：{}", e.getMessage());
        }
    }
}
