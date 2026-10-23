package com.mirror.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record AuthRequest(
        @NotBlank(message = "不能为空") @Size(min = 3, max = 32, message = "长度要在 3 到 32 之间") String username,
        @NotBlank(message = "不能为空") @Size(min = 6, max = 64, message = "长度要在 6 到 64 之间") String password
) {
}