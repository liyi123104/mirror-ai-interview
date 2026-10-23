package com.mirror.controller;

import com.mirror.common.ApiResponse;
import com.mirror.common.BizException;
import com.mirror.common.PublicApi;
import com.mirror.mapper.AppUserMapper;
import com.mirror.mapper.QuestionMapper;
import com.mirror.util.JwtUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.Map;

@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
public class DebugController {

    private final QuestionMapper questionMapper;
    private final AppUserMapper userMapper;
    private final JwtUtil jwtUtil;

    @PublicApi
    @GetMapping("/health")
    public ApiResponse<Map<String, Object>> health() {
        return ApiResponse.ok(Map.of(
                "status", "ok",
                "time", LocalDateTime.now().toString()
        ));
    }

    @GetMapping("/debug/boom")
    public ApiResponse<Void> boom() {
        throw new BizException("这是我主动抛的业务异常");
    }

    /** 临时接口（验证完可删）：检查数据库连通性 */
    @PublicApi
    @GetMapping("/debug/db")
    public ApiResponse<Object> db() {
        return ApiResponse.ok(Map.of(
                "questionCount", questionMapper.selectCount(null),
                "userCount", userMapper.selectCount(null)
        ));
    }

    @PublicApi
    @GetMapping("/debug/hash")
    public ApiResponse<String> hash(@RequestParam String raw) {
        return ApiResponse.ok(jwtUtil.hash(raw));
    }
}
