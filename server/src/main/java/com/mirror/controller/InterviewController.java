package com.mirror.controller;

import com.mirror.common.ApiResponse;
import com.mirror.dto.AnswerRequest;
import com.mirror.dto.StartInterviewRequest;
import com.mirror.service.InterviewService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/interview")
@RequiredArgsConstructor
public class InterviewController {

    private final InterviewService service;

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
}