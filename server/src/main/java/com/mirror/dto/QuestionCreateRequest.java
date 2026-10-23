package com.mirror.dto;

import jakarta.validation.constraints.NotBlank;

public record QuestionCreateRequest(
        @NotBlank(message = "不能为空") String job,
        @NotBlank(message = "不能为空") String dimension,
        @NotBlank(message = "不能为空") String stem,
        String keyPoints,
        String refAnswer,
        Integer difficulty
) {
}