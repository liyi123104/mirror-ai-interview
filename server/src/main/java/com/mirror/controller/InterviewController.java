package com.mirror.controller;

import com.mirror.common.ApiResponse;
import com.mirror.dto.AnswerRequest;
import com.mirror.dto.StartInterviewRequest;
import com.mirror.service.InterviewService;
import com.mirror.service.ReportService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.util.Map;
import java.util.concurrent.CompletableFuture;

@Slf4j
@RestController
@RequestMapping("/api/interview")
@RequiredArgsConstructor
public class InterviewController {

    private final InterviewService service;
    private final ReportService reportService;

    @PostMapping("/start")
    public ApiResponse<Map<String, Object>> start(@Valid @RequestBody StartInterviewRequest req,
                                                  HttpServletRequest http) {
        String userId = (String) http.getAttribute("userId");
        return ApiResponse.ok(service.start(userId, req.job(), req.resumeJson(), req.jdJson()));
    }

    @PostMapping("/{id}/answer")
    public ApiResponse<Map<String, Object>> answer(@PathVariable String id,
                                                   @Valid @RequestBody AnswerRequest req,
                                                   HttpServletRequest http) {
        String userId = (String) http.getAttribute("userId");
        return ApiResponse.ok(service.answer(userId, id, req.answer()));
    }

    @GetMapping("/{id}/state")
    public ApiResponse<Map<String, Object>> state(@PathVariable String id,
                                                  HttpServletRequest http) {
        String userId = (String) http.getAttribute("userId");
        return ApiResponse.ok(service.state(userId, id));
    }

    /** 流式提交回答：先算完，再把题干一个字一个字推给前端 */
    @PostMapping("/{id}/stream")
    public SseEmitter stream(@PathVariable String id,
                             @Valid @RequestBody AnswerRequest req,
                             HttpServletRequest http) {
        String userId = (String) http.getAttribute("userId");
        SseEmitter emitter = new SseEmitter(180_000L);

        // SSE 会长时间占用连接，不能堵住 Tomcat 的请求线程
        CompletableFuture.runAsync(() -> {
            try {
                Map<String, Object> result = service.answer(userId, id, req.answer());

                emitter.send(SseEmitter.event().data(Map.of("type", "meta")));

                if (Boolean.TRUE.equals(result.get("finished"))) {
                    emitter.send(SseEmitter.event().data(Map.of("type", "finished")));
                    emitter.complete();
                    return;
                }

                String stem = String.valueOf(result.get("stem"));
                for (int i = 0; i < stem.length(); i++) {
                    emitter.send(SseEmitter.event().data(Map.of(
                            "type", "delta", "content", String.valueOf(stem.charAt(i)))));
                    Thread.sleep(18);
                }

                emitter.send(SseEmitter.event().data(Map.of(
                        "type", "done",
                        "basedOn", String.valueOf(result.getOrDefault("basedOn", "")),
                        "qtype", String.valueOf(result.getOrDefault("type", "new_question")))));

                emitter.complete();
            } catch (Exception e) {
                log.error("流式回答失败 session={}", id, e);
                try {
                    emitter.send(SseEmitter.event().data(
                            Map.of("type", "error", "message", "生成失败，请重试")));
                } catch (Exception ignored) {
                    // 连接已经断了，忽略
                }
                emitter.completeWithError(e);
            }
        });

        return emitter;
    }

    @GetMapping("/{id}/report")
    public ApiResponse<Map<String, Object>> report(@PathVariable String id,
                                                   HttpServletRequest http) {
        String userId = (String) http.getAttribute("userId");
        return ApiResponse.ok(reportService.build(userId, id));
    }

    @GetMapping("/{id}/report/markdown")
    public ResponseEntity<String> markdown(@PathVariable String id, HttpServletRequest http) {
        String userId = (String) http.getAttribute("userId");
        String md = reportService.toMarkdown(userId, id);

        return ResponseEntity.ok()
                .header("Content-Type", "text/markdown; charset=utf-8")
                .header("Content-Disposition", "attachment; filename=\"report-" + id + ".md\"")
                .body(md);
    }

    /** AI 调用成本统计 */
    @GetMapping("/stats")
    public ApiResponse<Map<String, Object>> stats() {
        return ApiResponse.ok(service.stats());
    }
}
