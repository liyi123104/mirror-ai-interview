package com.mirror.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.mirror.client.AiClient;
import com.mirror.common.ApiResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/resume")
@RequiredArgsConstructor
public class ResumeController {

    private final AiClient ai;

    @PostMapping("/upload")
    public ApiResponse<Map<String, Object>> upload(@RequestParam("file") MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new com.mirror.common.BizException("请选择一份 PDF 文件");
        }

        JsonNode data = ai.parseResume(file);

        Map<String, Object> parsed = new HashMap<>();
        parsed.put("name", data.path("name").asText());
        parsed.put("phone", data.path("phone").asText());
        parsed.put("email", data.path("email").asText());
        parsed.put("education", data.path("education").asText());
        parsed.put("projects", data.path("projects"));
        parsed.put("skills", data.path("skills"));
        parsed.put("needsReview", data.path("needsReview").asBoolean(false));

        Map<String, Object> out = new HashMap<>();
        out.put("parsed", parsed);
        out.put("rawText", data.path("rawText").asText());
        return ApiResponse.ok(out);
    }
}
