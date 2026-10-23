package com.mirror.controller;

import com.mirror.common.ApiResponse;
import com.mirror.common.PublicApi;
import com.mirror.dto.AuthRequest;
import com.mirror.service.UserService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

    private final UserService service;

    @PublicApi
    @PostMapping("/register")
    public ApiResponse<Map<String, Object>> register(@Valid @RequestBody AuthRequest req) {
        String token = service.register(req.username(), req.password());
        return ApiResponse.ok(Map.of("token", token, "username", req.username()));
    }

    @PublicApi
    @PostMapping("/login")
    public ApiResponse<Map<String, Object>> login(@Valid @RequestBody AuthRequest req) {
        String token = service.login(req.username(), req.password());
        return ApiResponse.ok(Map.of("token", token, "username", req.username()));
    }
}