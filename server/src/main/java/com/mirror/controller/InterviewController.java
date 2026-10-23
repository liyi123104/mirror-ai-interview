package com.mirror.controller;

import com.mirror.common.ApiResponse;
import com.mirror.dto.AnswerRequest;
import com.mirror.dto.StartInterviewRequest;
import com.mirror.service.InterviewService;
import com.mirror.service.ReportService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

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
