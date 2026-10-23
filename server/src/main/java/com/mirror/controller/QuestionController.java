package com.mirror.controller;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.mirror.common.ApiResponse;
import com.mirror.dto.QuestionCreateRequest;
import com.mirror.entity.Question;
import com.mirror.service.QuestionService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/question")
@RequiredArgsConstructor
public class QuestionController {

    private final QuestionService service;

    @PostMapping
    public ApiResponse<Question> create(@Valid @RequestBody QuestionCreateRequest req) {
        return ApiResponse.ok(service.create(req));
    }

    @GetMapping
    public ApiResponse<Page<Question>> list(
            @RequestParam(required = false) String job,
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ApiResponse.ok(service.page(job, page, size));
    }

    @GetMapping("/{id}")
    public ApiResponse<Question> get(@PathVariable String id) {
        return ApiResponse.ok(service.get(id));
    }

    /** 语义检索：走 Python 的向量索引 */
    @GetMapping("/search")
    public ApiResponse<Map<String, Object>> search(
            @RequestParam("q") String q,
            @RequestParam(required = false) String job,
            @RequestParam(defaultValue = "5") int topK) {
        List<Map<String, Object>> items = service.search(q, job, topK);
        return ApiResponse.ok(Map.of("items", items, "total", items.size()));
    }

    @DeleteMapping("/{id}")
    public ApiResponse<Void> delete(@PathVariable String id) {
        service.delete(id);
        return ApiResponse.ok(null);
    }
}