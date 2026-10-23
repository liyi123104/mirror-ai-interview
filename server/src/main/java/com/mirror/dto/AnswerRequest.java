package com.mirror.dto;

import jakarta.validation.constraints.NotBlank;

public record AnswerRequest(@NotBlank(message = "不能为空") String answer) {
}